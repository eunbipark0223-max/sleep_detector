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
# True 면 시간 기준이 짧아짐 (10분→1분, 15분→1분, 2시간→2분). .env 에 DEMO_MODE=true 로도 켤 수 있음
DEMO_MODE = _env_bool("DEMO_MODE", False)

# ── AI 스위치 (수업 방식: 가짜 ↔ 진짜, 실패하면 가짜로) ──
USE_REAL_AI = True
FALLBACK_ON_ERROR = True

# ── 서버 확인 판정 (face_service) ────────────────────
EAR_THRESHOLD = 0.20          # 기본 기준 (개인 기준이 없을 때)
CONFIRM_OPEN_MARGIN = 0.03    # EAR 이 기준 + 이 값 이상이면 '확실히 뜸' → 앱 의심 취소

USE_CNN = False               # 3주차 수요일 채택 결정 (KPI ①)
CNN_CLOSED_PROB = 0.5         # 감음 확률이 이 값 이상이면 감음
CNN_INPUT_SIZE = 64           # 눈 잘라 흑백 64×64 (학습 노트북과 같은 값)
CNN_MODEL_PATH = os.path.join(BASE_DIR, "ml_models", "eye_cnn.pt")

# ── 개인 기준 EAR (출발 때 정면 사진 5장) ─────────────
CALIB_FRAMES = 5              # 받는 사진 수
CALIB_MIN_FACES = 3           # 얼굴이 이 장 수 이상 잡혀야 인정
CALIB_RATIO = 0.7             # 기준 = 뜬 눈 EAR 중간값 × 0.7
CALIB_MIN = 0.15              # 기준 하한
CALIB_MAX = 0.25              # 기준 상한 (실패하면 EAR_THRESHOLD)

# ── 경고 단계 (sleep_state · agent_service) ───────────
WINDOW_MIN = 1 if DEMO_MODE else 10      # 졸음 횟수를 세는 창 · 1단계 자동 해제 시간
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

# ── 기사 음성 보고 (agent_service) ────────────────────
DRIVER_VOICE_MAX_CHARS = 90

# ── 음성 퀴즈 (voice_quiz_service, /quiz/answer) ──────
QUIZ_MODE = "voice"           # STT 안 되면 "screen" (부품 B)
VOICE_QUIZ_GAP_SEC = 120      # 퀴즈 사이 최소 간격
VOICE_QUIZ_MAX_TRIES = 2      # 이만큼 실패하면 단계 +1, reason = no_response
LISTEN_SEC = 7                # 앱이 듣는 시간
REPEAT_MIN_SCORE = 0.8        # 따라 말하기 유사도 통과 기준 (difflib)
QUIZ_RETRY_WAIT_MIN = 5       # (부품 B) 복귀 퀴즈 실패 후 다시 시도까지

# ── Gemini (LLM · RAG · Agent) ← .env ─────────────────
GEMINI_API_KEY = os.getenv("GEMINI_API_KEY", "")
GEMINI_BASE_URL = os.getenv("GEMINI_BASE_URL") or "https://generativelanguage.googleapis.com/v1beta/openai/"
GEMINI_MODEL = os.getenv("GEMINI_MODEL") or "gemini-3.5-flash-lite"
GEMINI_EMBEDDING_MODEL = os.getenv("GEMINI_EMBEDDING_MODEL") or "gemini-embedding-001"

# ── 경로 ──────────────────────────────────────────────
FACE_LANDMARKER_PATH = os.path.join(BASE_DIR, "ml_models", "face_landmarker.task")
KNOWLEDGE_DIR = os.path.join(BASE_DIR, "knowledge")
VOICE_QUIZ_DIR = os.path.join(KNOWLEDGE_DIR, "voice_quiz")
UPLOAD_TMP_DIR = os.path.join(BASE_DIR, "uploads", "tmp")
UPLOAD_EVENT_DIR = os.path.join(BASE_DIR, "uploads", "events")
