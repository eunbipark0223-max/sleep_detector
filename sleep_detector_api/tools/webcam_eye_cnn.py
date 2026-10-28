# ═══════════════════════════════════════════════════════════════
# tools/webcam_eye_cnn.py — 웹캠 실시간 시연 · 확인: CNN 두 모델 (MRL만 vs 미세조정) + EAR
# ═══════════════════════════════════════════════════════════════
# 담당: B (CNN)   |   서버 코드가 아니라 PC 에서 돌리는 시험 · 발표 시연 도구
#
# [하는 일]
#   - 웹캠 프레임(BGR) → MediaPipe 눈 점(픽셀) → 서버 crop_eye → prep_eye → CNN → 두 눈 평균 감음 확률 (서버 face_service 와 같은 흐름)
#   - crop_eye 가 None (눈이 너무 작거나 사진 밖) 이면 그 프레임은 CNN 없음 (서버도 EAR 로 넘어감)
#   - 비교용으로 서버 EAR (config.EAR_THRESHOLD) 도 같이 보여 줌
#   - 기준값 0.4 · 0.5 두 가지로 판정 표시 (AI-Hub test 에서 0.4 가 균형 정확도 최고)
#   - 모델이 실제로 보는 64×64 눈 두 장을 왼쪽 위에 보여 줌 (발표: "CNN 이 무엇을 보는지")
#   - 서버 확인 결과 (앱이 미세수면 의심으로 보냈다면 KEEP warning / CANCEL) — face_service._normalize 를 그대로 불러 씀
#     (10/28 채택: 미세조정 · 기준 config.CNN_CLOSED_PROB · 취소는 CNN · EAR 둘 다 '확실히 뜸' 일 때만), q 로 끝내면 라벨별 취소 비율
#
# [키]
#   o 누르고 있기 = 지금 눈 뜸 (정답 기록) / h = 반쯤 감음 / c = 눈 감음 (눈 감은 채로 키만 누르고 있으면 됨)
#   q = 끝내기 → 모델 · 기준값별 정확도 · 감음 재현율 · 뜸 재현율 출력, 기록 CSV 저장
#
# [실행] (sleep_detector_api 폴더, 서버 venv — torch CPU 판 필요)
#   pip install -r tools/requirements-cnn.txt   (처음 한 번 · A · B · 팀장 PC 만)
#   venv\Scripts\python tools/webcam_eye_cnn.py --person p1 --model_dir D:\aihub173\models
#   (웹캠이 안 열리면 --cam 1, 기본 모델 위치 ml_models\eye_cnn.pt · eye_cnn_aihub.pt)
#
# [주의]
#   - KPI ① 근거로 쓰지 않는다 (웹캠 ≠ 시연 폰 카메라, 프레임이 거의 같아 정확도가 부풀려짐) → 빠른 확인 · 시연용
#   - 사진은 저장하지 않고 숫자만 CSV 로 (기본 저장 위치는 저장소 밖: 사용자 폴더\sleep_detector_webcam)
#   - 모델(.pt) · face_landmarker.task · 기록 CSV 는 GitHub 에 올리지 않는다
#   - 화면 녹화 시 얼굴이 나옴 → 찍히는 팀원 동의 받기
#
# 자세한 내용: notebooks/eye_cnn.ipynb · services/face_service.py · services/eye_preprocess.py
# ═══════════════════════════════════════════════════════════════
import argparse, csv, os, sys, time
from pathlib import Path

import cv2
import numpy as np
import torch
import torchvision
import mediapipe as mp
from PIL import Image, ImageDraw, ImageFont  # 화면 한글 (cv2.putText 는 한글이 깨짐) — torchvision 이 같이 깔아 줌

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # sleep_detector_api
sys.path.insert(0, BASE)
from config import CNN_CLOSED_PROB, CNN_INPUT_SIZE as SIZE, EAR_THRESHOLD, FACE_LANDMARKER_PATH  # noqa: E402
from services.eye_preprocess import crop_eye, prep_eye  # noqa: E402  서버와 같은 함수
from services.face_service import _normalize as server_confirm  # noqa: E402  서버 확인 규칙 그대로 (베끼지 않음)

MODEL_DIR = Path(BASE) / "ml_models"
OUT_DIR = Path.home() / "sleep_detector_webcam"  # 기록 CSV (숫자만) — 저장소 밖
THRESHOLDS = (0.4, 0.5)
# face_service.py LEFT_EYE / RIGHT_EYE 와 같은 번호 (p1 · p4 = 눈꼬리)
EYES = {"L": [33, 160, 158, 133, 153, 144], "R": [362, 385, 387, 263, 373, 380]}
HOLD_SEC = 0.6  # 키를 누르고 있는 동안 (윈도우 키 반복 간격보다 길게)
WARMUP_SEC = 1.0  # 켠 직후 웹캠이 밝기를 맞추는 동안은 기록 안 함 (10.27 확인: 처음 ~0.9초 확률이 0.4~0.66 으로 흔들림)
KEYS = {ord("o"): "open", ord("h"): "half", ord("c"): "closed"}
LABEL_KO = {"open": "뜸", "half": "반쯤 감음", "closed": "감음"}
FONT_PATH = r"C:\Windows\Fonts\malgun.ttf"  # 맑은 고딕 (윈도우 기본)
RED, ORANGE, GREEN, CYAN, YELLOW = (0, 0, 255), (0, 165, 255), (0, 200, 0), (255, 255, 0), (0, 255, 255)  # BGR


def draw_texts(view, texts, font):
    """[(글자, (x, 위쪽 y), BGR색)] 을 한 번에 그림 (PIL 로 바꿨다 돌아옴 — 프레임마다 한 번)"""
    img = Image.fromarray(cv2.cvtColor(view, cv2.COLOR_BGR2RGB))
    d = ImageDraw.Draw(img)
    for text, xy, bgr in texts:
        d.text(xy, text, font=font, fill=bgr[::-1], stroke_width=2, stroke_fill=(0, 0, 0))
    return cv2.cvtColor(np.asarray(img), cv2.COLOR_RGB2BGR)


def load_cnn(path):
    ck = torch.load(path, map_location="cpu", weights_only=True)  # 서버와 같은 방식
    m = torchvision.models.resnet18(weights=None)
    m.fc = torch.nn.Linear(m.fc.in_features, 1)
    m.load_state_dict(ck["state_dict"])
    return m.eval()


def load_landmarker(path):
    opts = mp.tasks.vision.FaceLandmarkerOptions(
        base_options=mp.tasks.BaseOptions(model_asset_buffer=Path(path).read_bytes()),  # 한글 경로 피하려고 바이트로
        running_mode=mp.tasks.vision.RunningMode.VIDEO, num_faces=1)
    return mp.tasks.vision.FaceLandmarker.create_from_options(opts)


def ear(pts):
    p1, p2, p3, p4, p5, p6 = pts
    return (np.linalg.norm(p2 - p6) + np.linalg.norm(p3 - p5)) / (2 * np.linalg.norm(p1 - p4) + 1e-6)


def summary(rows):
    if not rows:
        print("정답 키(o / h / c)로 기록한 프레임이 없어요.")
        return
    lab = np.array([r["label"] for r in rows])
    print(f"\n기록 {len(rows)}프레임 (뜸 {(lab == 'open').sum()} / 반쯤 {(lab == 'half').sum()} / 감음 {(lab == 'closed').sum()})")
    print(f"  CNN 없음 (crop_eye None) {sum(r['p_mrl'] == '' for r in rows)}프레임")
    keep = lab != "half"  # 채점 A: 완전히 감음만 (KPI ① 과 같음)
    y = lab[keep] == "closed"
    sub = [r for r, k in zip(rows, keep) if k]
    cols = [(f"MRL만 ≥{t}", "p_mrl", t) for t in THRESHOLDS] + [(f"미세조정 ≥{t}", "p_aihub", t) for t in THRESHOLDS]
    for name, col, t in cols:
        p = np.array([r[col] if r[col] != "" else np.nan for r in sub], float)
        pred = np.nan_to_num(p, nan=0.0) >= t  # CNN 없음 = 감음으로 안 잡음
        rc = pred[y].mean() if y.any() else float("nan")
        ro = (~pred[~y]).mean() if (~y).any() else float("nan")
        print(f"  {name:12s} 정확도 {(pred == y).mean():.1%} · 감음 재현율 {rc:.1%} · 뜸 재현율 {ro:.1%} · 균형 {(rc + ro) / 2:.1%}")
    e = np.array([r["ear"] for r in sub], float)
    pred = e < EAR_THRESHOLD
    rc, ro = pred[y].mean() if y.any() else float("nan"), (~pred[~y]).mean() if (~y).any() else float("nan")
    print(f"  {'EAR <' + str(EAR_THRESHOLD):12s} 정확도 {(pred == y).mean():.1%} · 감음 재현율 {rc:.1%} · 뜸 재현율 {ro:.1%} · 균형 {(rc + ro) / 2:.1%}")
    half = [r for r in rows if r["label"] == "half"]
    if half:
        for col in ("p_mrl", "p_aihub"):
            v = np.array([r[col] for r in half if r[col] != ""], float)
            if len(v):
                print(f"  반쯤 감음 {col} 중간값 {np.median(v):.2f}")
    print(f"  서버 확인 (미세조정 ≥{CNN_CLOSED_PROB} + EAR {EAR_THRESHOLD}, 둘 다 '확실히 뜸' 이면 취소) — 취소 비율:")
    for name in ("closed", "half", "open"):
        g = [r["server_cancel"] for r in rows if r["label"] == name]
        if g:
            print(f"    {name:6s} {sum(g)}/{len(g)} ({np.mean(g):.1%})  {'← 좋음 (걸러냄)' if name == 'open' else '← 나쁨 (졸음 취소)'}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--person", default="p0", help="기록 CSV 이름 · 칸에 넣을 사람 (촬영 수칙 p1 · p2 …)")
    ap.add_argument("--model_dir", default=str(MODEL_DIR), help="eye_cnn.pt · eye_cnn_aihub.pt 가 있는 폴더")
    ap.add_argument("--model_mrl", help="MRL만 모델 (기본: model_dir/eye_cnn.pt)")
    ap.add_argument("--model_aihub", help="미세조정 모델 (기본: model_dir/eye_cnn_aihub.pt)")
    ap.add_argument("--landmarker", default=FACE_LANDMARKER_PATH)
    ap.add_argument("--out_dir", default=str(OUT_DIR), help="기록 CSV 저장 폴더 (저장소 밖으로)")
    ap.add_argument("--cam", type=int, default=0)
    ap.add_argument("--font", default=FONT_PATH, help="화면 한글 글꼴 (.ttf)")
    args = ap.parse_args()
    paths = {"p_mrl": args.model_mrl or os.path.join(args.model_dir, "eye_cnn.pt"),
             "p_aihub": args.model_aihub or os.path.join(args.model_dir, "eye_cnn_aihub.pt")}
    for path in [*paths.values(), args.landmarker, args.font]:
        if not os.path.exists(path):
            sys.exit(f"파일이 없어요: {path}  (--model_dir · --landmarker · --font 로 위치를 알려 주세요)")
    font = ImageFont.truetype(args.font, 22)

    models = {k: load_cnn(v) for k, v in paths.items()}
    lm = load_landmarker(args.landmarker)
    cap = cv2.VideoCapture(args.cam, cv2.CAP_DSHOW)
    if not cap.isOpened():
        sys.exit(f"웹캠 {args.cam} 번을 열 수 없어요 (--cam 1 로도 해 보세요)")

    rows, label, label_until, t0 = [], None, 0.0, time.time()
    print("o(뜸) / h(반쯤) / c(감음) 를 누르고 있으면 정답 기록, q 로 끝내기")
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        h, w = frame.shape[:2]
        res = lm.detect_for_video(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)),
                                  int((time.time() - t0) * 1000))
        view = cv2.flip(frame, 1)  # 거울처럼 보이게 (계산은 원본으로)
        texts = []  # (글자, (x, 위쪽 y), BGR색) — 프레임 끝에 한 번에 한글로 그림
        now = time.time()
        if now > label_until:
            label = None

        if res.face_landmarks:
            lms = res.face_landmarks[0]
            pts = {s: np.array([[lms[i].x * w, lms[i].y * h] for i in idx], np.float32) for s, idx in EYES.items()}
            crops = [crop_eye(frame, pts[s]) for s in EYES]  # 서버 crop_eye (BGR 프레임 그대로)
            e = float(np.mean([ear(pts[s]) for s in EYES]))
            probs = {}
            if all(c is not None for c in crops):
                x = np.stack([prep_eye(c, SIZE) for c in crops])  # (2, 64, 64)
                xt = torch.from_numpy(x)[:, None].expand(-1, 3, -1, -1)
                with torch.no_grad():
                    for k, m in models.items():
                        probs[k] = float(torch.sigmoid(m(xt).squeeze(1)).mean())  # 서버처럼 두 눈 평균
                for k, img in enumerate(x):  # 모델이 보는 64×64 두 장을 왼쪽 위에 크게
                    ins = np.clip((img - img.min()) / (np.ptp(img) + 1e-6) * 255, 0, 255).astype(np.uint8)
                    view[10:138, 10 + k * 138:138 + k * 138] = cv2.cvtColor(
                        cv2.resize(ins, (128, 128), interpolation=cv2.INTER_NEAREST), cv2.COLOR_GRAY2BGR)
                for line, (k, name) in enumerate((("p_mrl", "MRL만"), ("p_aihub", "미세조정"))):
                    p = probs[k]
                    marks = " · ".join(f"{t}: {'감김' if p >= t else '뜸'}" for t in THRESHOLDS)
                    color = RED if p >= 0.5 else (ORANGE if p >= 0.4 else GREEN)
                    texts.append((f"{name} 감김 확률 {p:.2f}  [{marks}]", (10, 148 + line * 32), color))
            else:
                texts.append(("CNN 없음: 눈이 너무 작거나 화면 밖", (10, 148), RED))
            texts.append((f"EAR {e:.3f} → {'감김' if e < EAR_THRESHOLD else '뜸'} (기준 {EAR_THRESHOLD})", (10, 212), CYAN))
            # 앱이 미세수면 의심으로 이 프레임을 보냈다면 서버는? (서버 모델 = 미세조정, CNN 값이 없으면 EAR 로)
            #   취소 = CNN · EAR 둘 다 '확실히 뜸' (10/28 CNN 채택 회의) / 그 밖은 경고 유지
            conf = server_confirm({"face_found": True, "ear": e, "eye_closed_prob": probs.get("p_aihub"),
                                   "method": "cnn" if probs else "ear"}, EAR_THRESHOLD, reason="microsleep")
            keep = conf["is_sleep"]
            texts.append((f"서버 확인 ({'CNN+EAR' if conf['method'] == 'cnn' else 'EAR'}): "
                          f"{'경고 유지 (졸음 확정)' if keep else '경고 취소 (확실히 뜸)'}", (10, 244), RED if keep else GREEN))
            if label and now - t0 >= WARMUP_SEC:
                rows.append(dict(person=args.person, t=round(now - t0, 2), label=label,
                                 p_mrl=round(probs["p_mrl"], 4) if probs else "",
                                 p_aihub=round(probs["p_aihub"], 4) if probs else "", ear=round(e, 4),
                                 server_cancel=int(not keep)))
        else:
            texts.append(("얼굴 없음 (서버는 앱 판단대로 경고 유지)", (10, 20), RED))

        if now - t0 < WARMUP_SEC:
            texts.append(("카메라 준비 중…", (10, h - 40), YELLOW))
        elif label:
            texts.append((f"기록 중 {args.person} · 정답 = {LABEL_KO[label]}  ({len(rows)}프레임)", (10, h - 40), YELLOW))
        else:
            texts.append(("o 뜸 · h 반쯤 감음 · c 감음 (누르고 있기) · q 끝내기", (10, h - 40), YELLOW))
        view = draw_texts(view, texts, font)
        cv2.imshow("eye_cnn webcam: MRL vs fine-tuned (q = quit)", view)
        key = cv2.waitKey(1) & 0xFF
        if key == ord("q"):
            break
        if key in KEYS:
            label, label_until = KEYS[key], now + HOLD_SEC

    cap.release()
    cv2.destroyAllWindows()
    summary(rows)
    if rows:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)
        out = out_dir / f"webcam_{args.person}_{time.strftime('%m%d_%H%M')}.csv"
        with open(out, "w", newline="", encoding="utf-8-sig") as f:
            wr = csv.DictWriter(f, fieldnames=list(rows[0]))
            wr.writeheader(); wr.writerows(rows)
        print("기록 저장:", out)


if __name__ == "__main__":
    main()
