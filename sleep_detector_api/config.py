# ═══════════════════════════════════════════════════════════════
# config.py — 서버 기준 숫자 · 스위치를 한곳에 모은 파일
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: (신규) 수업 각 서비스 맨 위 상수들을 모은 것
#
# [쓰는 법]
#   from config import EAR_THRESHOLD, WINDOW_MIN
#   - 다른 파일은 숫자를 직접 쓰지 않고 여기 값만 가져다 쓴다 (기준 조정은 이 파일만 고침)
#
# [주의]
#   - 눈 판정 숫자(감김 확률 0.3 · 1.5초 · PERCLOS 15% · 30초 · 모름 3초)는 앱 lib/config.dart 에 있음 — 판정을 앱이 하기 때문
#   - 숫자는 모두 출발점. 팀 사진 · 시연 폰으로 측정한 뒤 바꾼다 (KPI ①⑤)
#
# 자세한 내용: 「파일 구조」 문서 1-2 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

import os
from dotenv import load_dotenv

load_dotenv()

BASE_DIR = os.path.dirname(os.path.abspath(__file__))


def _env_bool(name: str, default: bool) -> bool:
    return os.getenv(name, str(default)).strip().lower() in ("1", "true", "yes", "on")


# ── 시연 ─────────────────────────────────────────────
# True 면 시간 기준이 짧아짐 (10분→3분, 15분→1분, 2시간→2분 · 11/10 단계 창 1분 → 3분). .env 에 DEMO_MODE=true 로도 켤 수 있음
DEMO_MODE = _env_bool("DEMO_MODE", False)

# ── AI 스위치 (수업 방식: 가짜 ↔ 진짜, 실패하면 가짜로) ──
USE_REAL_AI = True
FALLBACK_ON_ERROR = True

# ── 서버 확인 판정 (face_service) ────────────────────
EAR_THRESHOLD = 0.23          # 기본 기준 (개인 기준이 없을 때) — 10/28 CNN 채택 회의 0.20 → 0.23 (KPI ①)
CONFIRM_OPEN_MARGIN = 0.03    # EAR 이 기준 + 이 값 이상이면 '확실히 뜸' → 앱 의심 취소

# CNN — 10/28 CNN 채택 회의 (KPI ①): 채택, AI-Hub 미세조정 모델, 기준 0.4
#   11/03 모델 교체: AI-Hub 548 컬러 추가 학습 eye_cnn_548.pt (폰 컬러 카메라용, 기준 0.4 그대로, eye_cnn.ipynb 7-6)
#     Validation 151명 83.1% → 99.4%, 팀 사진 그대로 · 반쯤 감음 50 → 78/109. 적외선 카메라면 eye_cnn_aihub.pt
#   취소는 CNN · EAR 둘 다 '확실히 뜸' 일 때만 (face_service._normalize)
#   torch(tools/requirements-cnn.txt) · 모델 파일이 없는 PC 는 자동으로 EAR 만 씀 (A · B · 팀장 PC 에만 설치)
USE_CNN = True
CNN_CLOSED_PROB = 0.4         # 감음 확률이 이 값 이상이면 감음 (CNN_OPEN_MARGIN 0.1 → 0.3 미만이면 '확실히 뜸')
CNN_INPUT_SIZE = 64           # 눈 잘라 흑백 64×64 (학습 노트북과 같은 값)
CNN_MODEL_PATH = os.path.join(BASE_DIR, "ml_models", "eye_cnn_548.pt")   # 구글 드라이브에서 받아 ml_models/ 에 (GitHub X)

# ── 개인 기준 EAR (출발 때 정면 사진 5장) ─────────────
CALIB_FRAMES = 5              # 받는 사진 수
CALIB_MIN_FACES = 3           # 얼굴이 이 장 수 이상 잡혀야 인정
CALIB_RATIO = 0.7             # 기준 = 뜬 눈 EAR 중간값 × 0.7
CALIB_MIN = 0.15              # 기준 하한
CALIB_MAX = 0.25              # 기준 상한 (실패하면 EAR_THRESHOLD)

# ── 경고 단계 (sleep_state · agent_service) ───────────
WINDOW_MIN = 3 if DEMO_MODE else 10      # 졸음 횟수를 세는 창 · 1단계 자동 해제 시간
AGENT_MAX_STEP_UP = 1         # 천장 규칙: Agent 는 규칙 단계보다 최대 +1
STAGE_MAX = 3
STAGE_LABELS = {0: "정상", 1: "주의", 2: "휴식 권고", 3: "긴급"}
STAGE3_REPEAT_SEC = 30        # 3단계 경고 반복 간격 (앱)

# ── 운전 · 휴식 (drive_timer, /drive/*) ───────────────
DRIVE_LIMIT_MIN = 2 if DEMO_MODE else 120   # 연속 운전 휴게 알림
REST_MIN = 1 if DEMO_MODE else 15           # 휴식 인정 시간
REST_GRACE_MIN = 1 if DEMO_MODE else 15     # 휴게 알림 후 이 시간 안에 안 쉬면 rest_overdue
PING_SEC = 30                 # 앱 /drive/ping 간격 (앱 config.dart 와 같은 값)

# ── 로그인 (auth/jwt.py) ──────────────────────────────
TOKEN_EXPIRE_MIN = 12 * 60    # 수업은 60분 → 운행(2시간 이상) 중에 토큰이 끝나면 /detect 가 401 이라 12시간
TOKEN_REFRESH_MIN = 6 * 60    # 운행 중 ping 때 남은 시간이 이 값보다 적으면 새 토큰을 내려 줌 (운행 중에 로그인이 끊기지 않게)

# ── 기사 음성 보고 (agent_service) ────────────────────
DRIVER_VOICE_MAX_CHARS = 90

# ── 음성 퀴즈 (voice_quiz_service, /quiz/answer) ──────
QUIZ_MODE = "voice"           # 10/29 STT 시험으로 부품 A 확정 (STT 안 되면 "screen" = 부품 B)
VOICE_QUIZ_GAP_SEC = 120      # 퀴즈 사이 최소 간격
VOICE_QUIZ_MAX_TRIES = 2      # 이만큼 실패하면 단계 +1, reason = no_response
LISTEN_SEC = 10               # 앱이 듣는 시간 — 10/29 STT 시험 7 → 10 (말을 시작하는 데 ~3초, 계산하느라 6~7초에 답하기도 함)
REPEAT_MIN_SCORE = 0.7        # 따라 말하기 유사도 통과 기준 — 11/02 KPI ⑤ 0.8 → 0.7
                              #   (주행 소음: 0.8 이면 6/10 · 0.7 이면 9/10 — 낱말 하나를 비슷한 발음으로 잘못 듣는 경우,
                              #    조용한 곳은 둘 다 10/10. 앱 VoiceService.doneScore 도 같은 값)
QUIZ_RETRY_WAIT_MIN = 5       # (부품 B) 복귀 퀴즈 실패 후 다시 시도까지

# ── Gemini (LLM · RAG · Agent) ← .env ─────────────────
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL") or "https://generativelanguage.googleapis.com/v1beta/openai/"
GEMINI_MODEL = os.getenv("GEMINI_MODEL") or "gemini-3.5-flash-lite"
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL") or "gemini-embedding-2"  # 11/04 001 → 2 (벡터 공간이 달라 색인 다시 만듦)

# ── 경로 ──────────────────────────────────────────────
FACE_LANDMARKER_PATH = os.path.join(BASE_DIR, "ml_models", "face_landmarker.task")
KNOWLEDGE_DIR = os.path.join(BASE_DIR, "knowledge")
VOICE_QUIZ_DIR = os.path.join(KNOWLEDGE_DIR, "voice_quiz")
UPLOAD_TMP_DIR = os.path.join(BASE_DIR, "uploads", "tmp")
UPLOAD_EVENT_DIR = os.path.join(BASE_DIR, "uploads", "events")
