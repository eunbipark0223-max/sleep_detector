# ═══════════════════════════════════════════════════════════════
# services/face_service.py — 서버 확인 판정 (MediaPipe EAR · CNN)  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P0
# 수업 원본: road_hazard_api/services/yolo_service.py (🟡 이름 변경 + 수정, _mock / _real / _normalize 뼈대 그대로)
#
# [이 파일이 하는 일]
#   - 앱이 보낸 의심 사진에서 MediaPipe Face Landmarker 로 눈 점 12개 → EAR 계산 (항상)
#   -   왼눈 33·160·158·133·153·144  /  오른눈 362·385·387·263·373·380
#   - USE_CNN 이면 눈만 잘라 흑백 64×64 → eye_cnn.pt → 감았을 확률
#       (자르기 · 흑백 · 크기는 services/eye_preprocess.py 의 crop_eye → prep_eye 사용, 학습과 같은 함수)
#   - 결과: 감음 / 뜸 / 얼굴 없음 + ear · eye_closed_prob · method
#   - 확인 규칙: microsleep → 서버도 감음이면 확정 / 확실히 뜸이면 취소 / 얼굴 없음이면 앱 판단대로(method mlkit)
#   -           perclos → 앱 숫자로 확정 (method mlkit, 사진은 기록용)
#   - 개인 기준 EAR: /drive/calibrate 사진 5장 중간값 × 0.7 (0.15~0.25)
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - check_eyes(image_path, user_id) → 판정 결과 dict
#   - calibrate(image_paths) → 개인 기준 EAR
#
# [주의]
#   - mediapipe 1.1.0 에는 예전 mp.solutions.face_mesh 가 없음 → ml_models/face_landmarker.task 로 Face Landmarker 사용
#   - 가짜(_mock): 파일 이름에 closed → 감음, noface → 얼굴 없음
#
#   - CNN: torch 가 없거나 eye_cnn.pt 가 없으면 자동으로 EAR 만 씀 (method = ear)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import os
import sys
import statistics
import urllib.request
import cv2
import numpy as np
import mediapipe as mp
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

# 프로젝트 루트 경로 추가
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if BASE_DIR not in sys.path:
    sys.path.insert(0, BASE_DIR)

try:
    import config
except ImportError:
    config = None

EAR_THRESHOLD = getattr(config, "EAR_THRESHOLD", 0.20)
CONFIRM_OPEN_MARGIN = getattr(config, "CONFIRM_OPEN_MARGIN", 0.03)
USE_CNN = getattr(config, "USE_CNN", False)
CNN_CLOSED_PROB = getattr(config, "CNN_CLOSED_PROB", 0.5)
CNN_INPUT_SIZE = getattr(config, "CNN_INPUT_SIZE", 64)
CNN_MODEL_PATH = getattr(config, "CNN_MODEL_PATH", os.path.join(BASE_DIR, "ml_models", "eye_cnn.pt"))
# 감음 확률이 CNN_CLOSED_PROB - 이 값 보다 낮아야 '확실히 뜸' → 취소 (0.4~0.6 은 애매 → 경고 쪽, eye_cnn.ipynb 2-6)
CNN_OPEN_MARGIN = getattr(config, "CNN_OPEN_MARGIN", 0.1)
USE_REAL_AI = getattr(config, "USE_REAL_AI", True)
FALLBACK_ON_ERROR = getattr(config, "FALLBACK_ON_ERROR", True)

CALIB_MIN_FACES = getattr(config, "CALIB_MIN_FACES", 3)
CALIB_RATIO = getattr(config, "CALIB_RATIO", 0.7)
CALIB_MIN = getattr(config, "CALIB_MIN", 0.15)
CALIB_MAX = getattr(config, "CALIB_MAX", 0.25)

DEFAULT_MODEL_PATH = os.path.join(BASE_DIR, "ml_models", "face_landmarker.task")
FACE_LANDMARKER_PATH = getattr(config, "FACE_LANDMARKER_PATH", DEFAULT_MODEL_PATH)
if not os.path.isabs(FACE_LANDMARKER_PATH):
    FACE_LANDMARKER_PATH = os.path.join(BASE_DIR, FACE_LANDMARKER_PATH)

MODEL_URL = (
    "https://storage.googleapis.com/mediapipe-models/"
    "face_landmarker/face_landmarker/float16/1/face_landmarker.task"
)

LEFT_EYE = [33, 160, 158, 133, 153, 144]
RIGHT_EYE = [362, 385, 387, 263, 373, 380]

_detector = None
_cnn = None          # eye_cnn.pt 로 만든 모델 (처음 쓸 때 1번 읽음)
_cnn_failed = False  # 한 번 못 읽으면 다시 시도하지 않고 EAR 만 씀


def _get_cnn():
    """eye_cnn.pt → resnet18 (eye_cnn.ipynb 2-9 방식). torch · 파일이 없으면 None"""
    global _cnn, _cnn_failed
    if _cnn is None and not _cnn_failed:
        try:
            import torch
            import torchvision
            ck = torch.load(CNN_MODEL_PATH, map_location="cpu", weights_only=True)
            m = torchvision.models.resnet18(weights=None)
            m.fc = torch.nn.Linear(m.fc.in_features, 1)
            m.load_state_dict(ck["state_dict"])
            _cnn = m.eval()
        except Exception as e:
            _cnn_failed = True
            print(f"[face_service] CNN 을 못 읽어 EAR 만 씀: {e}")
    return _cnn


def _cnn_closed_prob(image_bgr, eyes_px) -> float | None:
    """얼굴 사진 + 두 눈의 눈 점(픽셀) → 두 눈 평균 감음 확률. 실패하면 None (EAR 로 판정)"""
    model = _get_cnn()
    if model is None:
        return None
    import torch
    from services.eye_preprocess import crop_eye, prep_eye
    x = np.stack([prep_eye(crop_eye(image_bgr, pts), CNN_INPUT_SIZE) for pts in eyes_px])  # (2, size, size)
    with torch.no_grad():
        logits = model(torch.from_numpy(x)[:, None].expand(-1, 3, -1, -1)).squeeze(1)
    return float(torch.sigmoid(logits).mean())


def ensure_model_exists() -> str:
    os.makedirs(os.path.dirname(FACE_LANDMARKER_PATH), exist_ok=True)
    if not os.path.exists(FACE_LANDMARKER_PATH):
        print(f"📥 모델 파일 다운로드 중... ({FACE_LANDMARKER_PATH})")
        urllib.request.urlretrieve(MODEL_URL, FACE_LANDMARKER_PATH)
        print("✅ face_landmarker.task 다운로드 완료!")
    return FACE_LANDMARKER_PATH


def _get_detector():
    global _detector
    if _detector is None:
        model_path = ensure_model_exists()
        base_options = python.BaseOptions(model_asset_path=model_path)
        options = vision.FaceLandmarkerOptions(
            base_options=base_options,
            output_face_blendshapes=False,
            output_facial_transformation_matrixes=False,
            num_faces=1,
        )
        _detector = vision.FaceLandmarker.create_from_options(options)
    return _detector


def _read_image_bgr(image_path: str):
    if not os.path.exists(image_path):
        return None
    data = np.fromfile(image_path, dtype=np.uint8)
    return cv2.imdecode(data, cv2.IMREAD_COLOR)


def calculate_ear(eye_points: list[int], landmarks, width: int, height: int) -> float:
    """눈 랜드마크 6개 좌표로 EAR(눈 종횡비)을 계산합니다. (실제 픽셀 좌표 변환 적용)"""
    pts = [np.array([landmarks[pt].x * width, landmarks[pt].y * height]) for pt in eye_points]
    vertical_1 = np.linalg.norm(pts[1] - pts[5])
    vertical_2 = np.linalg.norm(pts[2] - pts[4])
    horizontal = np.linalg.norm(pts[0] - pts[3])
    return float((vertical_1 + vertical_2) / (2.0 * horizontal)) if horizontal != 0 else 0.0


def _get_user_threshold(user_id=None) -> float:
    if user_id is not None:
        try:
            from services import sleep_state
            if hasattr(sleep_state, "get_ear_threshold"):
                val = sleep_state.get_ear_threshold(user_id)
                if val is not None:
                    return float(val)
        except Exception:
            pass
    return float(EAR_THRESHOLD)


def _mock(image_path: str, threshold: float) -> dict:
    filename = os.path.basename(str(image_path)).lower()
    if "noface" in filename:
        return {
            "face_found": False,
            "ear": None,
            "eye_closed_prob": None,
            "method": "mlkit",
            "ear_threshold": threshold,
            "result": "얼굴 없음",
        }
    elif "closed" in filename:
        return {
            "face_found": True,
            "ear": round(max(0.05, threshold - 0.06), 3),
            "eye_closed_prob": 0.90 if USE_CNN else None,
            "method": "cnn" if USE_CNN else "ear",
            "ear_threshold": threshold,
            "result": "감음",
        }
    else:
        return {
            "face_found": True,
            "ear": round(threshold + 0.06, 3),
            "eye_closed_prob": 0.10 if USE_CNN else None,
            "method": "cnn" if USE_CNN else "ear",
            "ear_threshold": threshold,
            "result": "뜸",
        }


def _real(image_path: str, threshold: float) -> dict:
    image_bgr = _read_image_bgr(image_path)
    if image_bgr is None:
        raise FileNotFoundError(f"이미지를 읽을 수 없습니다: {image_path}")

    h, w, _ = image_bgr.shape
    image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
    mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)

    detector = _get_detector()
    detection_result = detector.detect(mp_image)

    if not detection_result.face_landmarks:
        return {
            "face_found": False,
            "ear": None,
            "eye_closed_prob": None,
            "method": "mlkit",
            "ear_threshold": threshold,
            "result": "얼굴 없음",
        }

    landmarks = detection_result.face_landmarks[0]

    # 수정사항 2: 눈 영역(랜드마크 기반 Bounding Box) 크기가 가로/세로 8px 미만인지 확인
    left_pts = np.array([(landmarks[pt].x * w, landmarks[pt].y * h) for pt in LEFT_EYE])
    right_pts = np.array([(landmarks[pt].x * w, landmarks[pt].y * h) for pt in RIGHT_EYE])
    all_eye_pts = np.vstack([left_pts, right_pts])
    x_min, y_min = np.min(all_eye_pts, axis=0)
    x_max, y_max = np.max(all_eye_pts, axis=0)
    box_w = x_max - x_min
    box_h = y_max - y_min

    use_cnn_local = USE_CNN
    if box_w < 8 or box_h < 8:
        # 눈 영역이 너무 작으면 CNN 없이 EAR만 사용하도록 강제 전환
        use_cnn_local = False

    # 픽셀 변환을 위해 가로(w), 세로(h) 값을 전달
    left_ear = calculate_ear(LEFT_EYE, landmarks, w, h)
    right_ear = calculate_ear(RIGHT_EYE, landmarks, w, h)
    avg_ear = round((left_ear + right_ear) / 2.0, 3)

    closed_prob = None
    if use_cnn_local:
        try:
            closed_prob = _cnn_closed_prob(image_bgr, [left_pts, right_pts])
        except Exception as e:
            print(f"[face_service] CNN 판정 실패 → EAR 사용: {e}")
    method = "cnn" if closed_prob is not None else "ear"

    is_closed = closed_prob >= CNN_CLOSED_PROB if method == "cnn" else avg_ear < threshold
    return {
        "face_found": True,
        "ear": avg_ear,
        "left_ear": round(left_ear, 3),
        "right_ear": round(right_ear, 3),
        "eye_closed_prob": round(closed_prob, 3) if closed_prob is not None else None,
        "method": method,
        "ear_threshold": threshold,
        "result": "감음" if is_closed else "뜸",
    }


def _normalize(raw: dict, threshold: float, reason: str | None = None) -> dict:
    face_found = bool(raw.get("face_found", False))
    ear = raw.get("ear", None)
    eye_closed_prob = raw.get("eye_closed_prob", None)
    method = raw.get("method", "ear" if face_found else "mlkit")

    if not face_found or ear is None:
        result_str = "얼굴 없음"
        is_closed = False
        is_definitely_open = False
    elif method == "cnn" and eye_closed_prob is not None:
        # CNN 채택 시: 감음 확률로 판정, 애매한 구간(0.4~0.6)은 취소하지 않음
        ear = round(float(ear), 3)
        is_closed = eye_closed_prob >= CNN_CLOSED_PROB
        is_definitely_open = eye_closed_prob < (CNN_CLOSED_PROB - CNN_OPEN_MARGIN)
        result_str = "감음" if is_closed else "뜸"
    else:
        method = "ear" if method == "cnn" else method  # CNN 값이 없으면 EAR 로 판정한 것
        ear = round(float(ear), 3)
        is_closed = ear < threshold
        is_definitely_open = ear >= (threshold + CONFIRM_OPEN_MARGIN)
        result_str = "감음" if is_closed else "뜸"

    if reason == "perclos":
        method = "mlkit"
        is_sleep = True
    elif reason == "microsleep":
        if not face_found:
            method = "mlkit"
            is_sleep = True
        elif is_definitely_open:
            is_sleep = False
        else:
            is_sleep = True
    else:
        is_sleep = is_closed if face_found else False

    return {
        "face_found": face_found,
        "ear": ear,
        "left_ear": raw.get("left_ear"),
        "right_ear": raw.get("right_ear"),
        "eye_closed_prob": eye_closed_prob,
        "method": method,
        "ear_threshold": round(threshold, 3),
        "result": result_str,
        "is_closed": is_closed,
        "is_definitely_open": is_definitely_open,
        "is_sleep": is_sleep,
    }


def check_eyes(image_path: str, user_id=None, reason: str | None = None, **kwargs) -> dict:
    threshold = _get_user_threshold(user_id)

    if not USE_REAL_AI:
        raw = _mock(image_path, threshold)
    else:
        try:
            raw = _real(image_path, threshold)
        except Exception as e:
            # 수정사항 1: 예외 발생 시 원인 출력을 위해 print문 추가
            print(f"[face_service] 진짜 판정 실패: {e}")
            if FALLBACK_ON_ERROR:
                # 오류 발생 시 앱(ML Kit)의 "졸음 의심" 판단을 우선시하도록 얼굴 없음과 동일하게 처리
                raw = {
                    "face_found": False,
                    "ear": None,
                    "eye_closed_prob": None,
                    "method": "mlkit",
                    "ear_threshold": threshold,
                    "result": "얼굴 없음"
                }
            else:
                raise

    return _normalize(raw, threshold, reason=reason)


def calibrate(image_paths: list[str], user_id=None, **kwargs) -> float:
    ears = []
    for path in image_paths:
        try:
            raw = _real(path, EAR_THRESHOLD) if USE_REAL_AI else _mock(path, EAR_THRESHOLD)
            if raw.get("face_found") and raw.get("ear") is not None:
                ears.append(float(raw["ear"]))
        except Exception:
            continue

    if len(ears) < CALIB_MIN_FACES:
        return round(float(EAR_THRESHOLD), 3)

    median_ear = statistics.median(ears)
    personal_threshold = median_ear * CALIB_RATIO

    clamped = max(CALIB_MIN, min(CALIB_MAX, personal_threshold))
    return round(float(clamped), 3)


def _label_of(filename: str) -> str:
    name = filename.lower()
    return next((l for l in ("closed", "half", "open") if l in name), "")


def process_all_images(image_dir: str, output_dir: str):
    """폴더 안 사진 전부 → 눈 점 12개를 그린 사진 + result.csv (시연 폰 사진 시험 · KPI ① 서버 EAR 열)

    result.csv 칸: file, label, face_found, left_ear, right_ear, ear, eye_closed_prob, method, eye_width_px, result
      eye_closed_prob = CNN 감음 확률 (config.USE_CNN = True 이고 eye_cnn.pt 가 있을 때만, 아니면 빈칸)
      label = 파일 이름 속 closed / half / open (사람_상태_번호.jpg, 앱 tools/eye_measure_main.dart 와 같은 규칙)
      eye_width_px = 두 눈 평균 눈꼬리 사이 거리 (작으면 EAR 이 흔들림 — 앱 폰 EAR 과 비교할 때 참고)
    """
    import csv
    if not os.path.exists(image_dir):
        print(f"❌ '{image_dir}' 폴더를 찾을 수 없습니다.")
        return

    os.makedirs(output_dir, exist_ok=True)
    valid_exts = (".jpg", ".jpeg", ".png")
    image_files = sorted([f for f in os.listdir(image_dir) if f.lower().endswith(valid_exts)])

    if not image_files:
        print(f"❌ '{image_dir}' 폴더 안에 이미지가 없습니다.")
        return

    detector = _get_detector()
    print(f"📁 총 {len(image_files)}장의 사진을 발견했습니다. 분석을 시작합니다...\n")

    rows = []
    for filename in image_files:
        img_path = os.path.join(image_dir, filename)
        res = check_eyes(img_path, user_id=1)

        if not res["face_found"]:
            print(f"⚠️ [{filename}] 얼굴 없음")
            rows.append({"file": filename, "label": _label_of(filename), "face_found": False, "result": "얼굴 없음"})
            continue

        image_bgr = _read_image_bgr(img_path)
        image_rgb = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=image_rgb)
        det = detector.detect(mp_image)

        eye_width = None
        if det.face_landmarks:
            h, w, _ = image_bgr.shape
            landmarks = det.face_landmarks[0]
            widths = [np.hypot((landmarks[a].x - landmarks[b].x) * w, (landmarks[a].y - landmarks[b].y) * h)
                      for a, b in ((LEFT_EYE[0], LEFT_EYE[3]), (RIGHT_EYE[0], RIGHT_EYE[3]))]
            eye_width = round(float(np.mean(widths)), 1)
            for idx in LEFT_EYE + RIGHT_EYE:
                pt = landmarks[idx]
                x, y = int(pt.x * w), int(pt.y * h)
                cv2.circle(image_bgr, (x, y), 2, (0, 255, 0), -1)

        out_path = os.path.join(output_dir, f"result_{filename}")
        ok, buf = cv2.imencode(".png", image_bgr)
        if ok:
            buf.tofile(out_path)

        print(f"✅ [{filename}] 판정: {res['result']} (is_sleep={res['is_sleep']})")
        print(f"   - 좌안 EAR: {res['left_ear']:.3f} | 우안 EAR: {res['right_ear']:.3f} | 평균: {res['ear']:.3f}"
              f" | 눈 폭 {eye_width}px")
        print(f"   - 저장 위치: {out_path}\n")
        rows.append({"file": filename, "label": _label_of(filename), "face_found": True, "left_ear": res["left_ear"], "right_ear": res["right_ear"],
                     "ear": res["ear"], "eye_closed_prob": res["eye_closed_prob"], "method": res["method"], "eye_width_px": eye_width, "result": res["result"]})

    csv_path = os.path.join(output_dir, "result.csv")
    with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:  # utf-8-sig: 엑셀에서 한글 안 깨짐
        writer = csv.DictWriter(f, fieldnames=["file", "label", "face_found", "left_ear", "right_ear", "ear",
                                               "eye_closed_prob", "method",
                                               "eye_width_px", "result"])
        writer.writeheader()
        writer.writerows(rows)
    print(f"🎉 모든 사진 분석 및 눈 점(12개) 표시 저장이 끝났습니다! 표: {csv_path}")


if __name__ == "__main__":
    # (sleep_detector_api 폴더에서) python services/face_service.py [사진 폴더]
    #   폴더를 안 주면 sleep_detector_api/images → ../images 순서로 찾음. 결과는 result_images/
    if len(sys.argv) > 1:
        process_all_images(sys.argv[1], os.path.join(BASE_DIR, "result_images"))
        sys.exit()
    candidates = [
        os.path.join(BASE_DIR, "images"),
        os.path.join(os.path.dirname(BASE_DIR), "images"),
    ]
    target_image_dir = next((p for p in candidates if os.path.exists(p)), candidates[0])
    target_output_dir = os.path.join(BASE_DIR, "result_images")

    process_all_images(target_image_dir, target_output_dir)