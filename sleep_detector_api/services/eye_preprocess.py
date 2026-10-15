# ═══════════════════════════════════════════════════════════════
# services/eye_preprocess.py — 눈 사진 전처리 (CNN 학습 노트북 · 서버 공통)
# ═══════════════════════════════════════════════════════════════
# 담당: prep_eye = B (CNN 학습)  |  crop_eye = A (눈 점 · face_service.py)   |   우선: P2 (CNN)
# 수업 원본: (없음, 🔴 신규 — 팀장 제안 10.14)
#
# [이 파일이 하는 일]
#   [학습]  MRL 눈 사진 ─────────────────→ prep_eye → CNN      (노트북 eye_cnn.ipynb)
#   [서버]  얼굴 사진 → crop_eye(눈 점) ─→ prep_eye → CNN      (face_service.py)
#   - 학습과 서버가 이 파일 하나를 같이 써서 전처리가 어긋나지 않게 한다
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - crop_eye(image, eye_points) → 눈 부분 사진 (서버만)
#   - prep_eye(eye_img, size=64)  → float32 (size, size) 배열 (서버 · 노트북 공통)
#
# [이 파일의 규칙]
#   1. cv2 · numpy 만 쓴다 — FastAPI · MediaPipe · config.py 를 불러오지 않는다 (Colab 에 이 파일만 올려도 돌게)
#   2. 크기는 인자로 받는다 — 서버는 config.CNN_INPUT_SIZE, 노트북은 64 (두 값은 항상 같아야 함)
#   3. 정규화는 이 파일에서만 한다 — 노트북에서 따로 /255 하지 않는다
#   4. 증강(밝기 · 회전 등)은 넣지 않는다 — 학습할 때만 하는 것이라 노트북에 둔다
#   - 파일을 고치면 Colab 에 다시 올린다 (왼쪽 파일 탭 → 업로드 → from eye_preprocess import prep_eye)
#
# 자세한 내용: 노트북 eye_cnn.ipynb 1-9 · 1-10b · 1-13 (MRL 자르기 범위 측정)
# ═══════════════════════════════════════════════════════════════

import cv2
import numpy as np

# MRL 자르기 범위 (eye_cnn.ipynb 1-10b, 10.14 측정 — 뜬 눈 평균 사진)
CROP_SCALE = 1.5  # 정사각형 한 변 = 눈꼬리~눈꼬리 폭 W × 1.5 (평균 사진의 눈 폭이 66%)
CROP_SHIFT_UP = 0.03  # 자르기 중심을 눈 중심보다 한 변의 3% 위로 (MRL 은 눈이 위에서 53% 에 있음)

# 정규화: 사진마다 평균 0 · 표준편차 1
#   MRL 은 적외선 흑백, 우리 폰은 컬러 → 전체 밝기 차이가 커서 사진마다 맞추는 쪽이 안전 (노트북 1-13)
#   참고: MRL 64×64 전체 평균 0.3426 · 표준편차 0.1024 (데이터 전체 값으로 바꾸려면 여기만 고친다)
MIN_STD = 1e-3  # 거의 단색인 사진에서 0 으로 나누지 않게


def crop_eye(image, eye_points):
    """얼굴 사진에서 눈 부분을 MRL 과 같은 모양(정사각형)으로 자른다.  ← A 담당, 서버만 씀

    image      : cv2 로 읽은 얼굴 사진 (BGR, H×W×3)
    eye_points : 한 눈의 MediaPipe 눈 점 픽셀 좌표 [(x, y), ...] — EAR 과 같은 순서 p1~p6
                 (오른눈 33 · 160 · 158 · 133 · 153 · 144 / 왼눈 362 · 385 · 387 · 263 · 373 · 380),
                 p1 · p4 = 눈꼬리
    반환       : 눈 부분 사진 (image 와 같은 채널, 정사각형). 사진 밖으로 나가는 부분은 가장자리 색으로 채운다

    자르는 범위 (MRL 측정값):
        W = |p1 − p4| (눈꼬리 사이 거리),  눈 중심 = (p1 + p4) / 2
        한 변 S = W × CROP_SCALE,  자르기 중심 = 눈 중심에서 위로 S × CROP_SHIFT_UP
    """
    h, w, _ = image.shape

    # 1. 픽셀 좌표 리스트 추출 (eye_points는 이전 face_service.py에서 이미 x*w, y*h 계산을 거친 픽셀 좌표가 들어옵니다)
    px_points = np.array([[int(pt[0]), int(pt[1])] for pt in eye_points])

    # 2. 눈 양 끝점(p1, p4) 추출을 통한 폭과 중심점 계산
    p1, p4 = px_points[0], px_points[3]
    eye_width = np.linalg.norm(p1 - p4)
    center_x = int((p1[0] + p4[0]) / 2)
    center_y = int((p1[1] + p4[1]) / 2)

    # 3. 정사각형 한 변의 길이(S) 및 중심 이동
    box_size = int(eye_width * CROP_SCALE)
    center_y = int(center_y - (box_size * CROP_SHIFT_UP))

    # 4. 자를 영역 좌표 및 가장자리 패딩(범위 초과 시) 처리
    half_size = box_size // 2
    x1 = center_x - half_size
    y1 = center_y - half_size
    x2 = x1 + box_size
    y2 = y1 + box_size

    # 사진 바깥으로 넘어가는 경우 가장자리 픽셀로 채우기 위해 여백(padding) 계산
    pad_y1 = max(0, -y1)
    pad_y2 = max(0, y2 - h)
    pad_x1 = max(0, -x1)
    pad_x2 = max(0, x2 - w)

    # 넘어가지 않는 유효 영역만 잘라내기
    valid_y1, valid_y2 = max(0, y1), min(h, y2)
    valid_x1, valid_x2 = max(0, x1), min(w, x2)
    eye_crop = image[valid_y1:valid_y2, valid_x1:valid_x2]

    # 사진 밖으로 나갔다면 np.pad를 이용해 가장자리 픽셀(edge) 값으로 연장 채우기
    if pad_y1 > 0 or pad_y2 > 0 or pad_x1 > 0 or pad_x2 > 0:
        eye_crop = np.pad(eye_crop, ((pad_y1, pad_y2), (pad_x1, pad_x2), (0, 0)), mode='edge')

    return eye_crop


def prep_eye(eye_img, size=64):
    """눈 사진 → CNN 입력. 흑백 → size×size → 사진마다 정규화.

    eye_img : 눈 부분 사진 numpy 배열 — 흑백(H×W), BGR(H×W×3), BGRA(H×W×4) 모두 가능, uint8 (0~255)
              · 노트북: cv2.imread(MRL 경로, cv2.IMREAD_UNCHANGED)
              · 서버:   crop_eye(...) 의 결과
    size    : 서버는 config.CNN_INPUT_SIZE, 노트북은 64
    반환    : float32 (size, size) 배열, 평균 0 · 표준편차 1 (CNN 에 넣을 때 채널 축은 각자 추가)
    """
    img = np.asarray(eye_img)
    if img.ndim == 3 and img.shape[2] == 4:
        img = cv2.cvtColor(img, cv2.COLOR_BGRA2GRAY)
    elif img.ndim == 3 and img.shape[2] == 3:
        img = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
    elif img.ndim == 3 and img.shape[2] == 1:
        img = img[:, :, 0]
    if img.ndim != 2 or img.size == 0:
        raise ValueError(f"눈 사진 모양이 이상합니다: {np.asarray(eye_img).shape}")
    if img.dtype != np.uint8:  # 학습 · 서버 모두 0~255 정수로 맞춘 뒤 줄인다
        img = np.clip(img, 0, 255).astype(np.uint8)

    # 줄일 때는 INTER_AREA(계단 무늬 없음), 키울 때는 INTER_LINEAR — MRL 은 52~299px 라 둘 다 생김
    interp = cv2.INTER_AREA if min(img.shape) >= size else cv2.INTER_LINEAR
    img = cv2.resize(img, (size, size), interpolation=interp).astype(np.float32) / 255.0

    return ((img - img.mean()) / max(float(img.std()), MIN_STD)).astype(np.float32)