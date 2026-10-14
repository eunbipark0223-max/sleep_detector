# ═══════════════════════════════════════════════════════════════
# config.py — 서버 기준 숫자 · 스위치를 한곳에 모은 파일
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: (신규) 수업 각 서비스 맨 위 상수들을 모은 것
#
# [이 파일이 하는 일]
#   - 다른 파일은 숫자를 직접 쓰지 않고 여기 값만 가져다 쓴다 (기준 조정은 이 파일만 고침)
#   - 시연    DEMO_MODE = False   → True 면 시간 기준이 짧아짐 (10분→1분, 15분→1분, 2시간→2분)
#   - AI      USE_REAL_AI = True  /  FALLBACK_ON_ERROR = True  (가짜↔진짜 스위치, 실패하면 가짜로)
#   - 확인    EAR_THRESHOLD = 0.20  /  CONFIRM_OPEN_MARGIN = 0.03 (EAR 이 기준+이 값 이상이면 '확실히 뜸' → 취소)
#   - CNN     USE_CNN = False  /  CNN_CLOSED_PROB = 0.5  /  CNN_INPUT_SIZE = 64  /  CNN_MODEL_PATH = 'ml_models/eye_cnn.pt'
#   - 개인    CALIB_FRAMES = 5  /  CALIB_MIN_FACES = 3  /  CALIB_RATIO = 0.7  /  CALIB_MIN = 0.15  /  CALIB_MAX = 0.25
#   - 단계    WINDOW_MIN = 10  /  AGENT_MAX_STEP_UP = 1  /  STAGE_LABELS = {0:정상, 1:주의, 2:휴식 권고, 3:긴급}  /  STAGE3_REPEAT_SEC = 30
#   - 운전    DRIVE_LIMIT_MIN = 120  /  REST_MIN = 15  /  REST_GRACE_MIN = 15  /  PING_SEC = 30 (앱 config.dart 와 같은 값)
#   - 음성    DRIVER_VOICE_MAX_CHARS = 90
#   - 퀴즈    QUIZ_MODE = 'voice' (STT 안 되면 'screen')  /  VOICE_QUIZ_GAP_SEC = 120  /  VOICE_QUIZ_MAX_TRIES = 2
#   -         LISTEN_SEC = 7  /  REPEAT_MIN_SCORE = 0.8  /  QUIZ_RETRY_WAIT_MIN = 5 (부품 B)
#   - Gemini  GEMINI_API_KEY · GEMINI_BASE_URL · GEMINI_MODEL · GEMINI_EMBEDDING_MODEL  ← .env 에서 읽음
#   - 경로    FACE_LANDMARKER_PATH · KNOWLEDGE_DIR · VOICE_QUIZ_DIR · UPLOAD_TMP_DIR · UPLOAD_EVENT_DIR
#
# [주의]
#   - 눈 판정 숫자(감김 확률 0.3 · 1.5초 · PERCLOS 15% · 30초)는 앱 lib/config.dart 에 있음 — 판정을 앱이 하기 때문
#   - 숫자는 모두 출발점. 팀 사진 · 시연 폰으로 측정한 뒤 바꾼다 (KPI ①⑤)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
