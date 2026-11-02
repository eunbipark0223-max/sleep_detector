# ═══════════════════════════════════════════════════════════════
# mock_server.py — 임시 서버 (C 앱 연결용 · AI · DB · 진짜 로그인 없음)
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0 (진짜 서버가 되기 전까지 임시)
# 수업 원본: (없음, 🔴 신규 — 진짜 서버 main.py + routers/ 가 완성되면 이 파일은 버린다)
#
# [이 파일이 하는 일]
#   - 진짜 서버와 같은 주소 · 같은 JSON 칸 이름으로 대답해서 C(앱) 가 서버 없이도 화면을 만들 수 있게 한다
#   - 구현한 API (기획안 9장 · 각 router 파일 맨 위 주석 그대로)
#       POST /users/signup · /users/login · /users/google  ·  GET · PATCH /users/me (PATCH = 전화번호 · 차량번호)
#       POST /detect                       졸음 의심 사진 1장 + reason · closed_sec · perclos · eye_open_prob · latitude · longitude (Form)
#       POST /drive/start · /drive/calibrate · /drive/ping · /drive/rest · /drive/resume
#       POST /quiz/answer                  VoiceQuizAnswer (quiz_id · answer_text · answer_sec)
#       GET  /events/my · PATCH /events/{id}/status
#       GET  /admin/events · /admin/users · /admin/stats/stage · /admin/stats/hourly
#       GET  /chat/hello · POST /chat
#   - 진짜처럼 도는 부분 (코드가 판정하는 것만): 10분 안 졸음 횟수 → 규칙 단계 · set_stage(올리기만) ·
#     1단계 자동 해제 · 2단계는 휴식 후 [운행 재개] · 3단계는 관리자 조치완료 · 음성 퀴즈 출제 · 채점 · 2번 실패 → 단계 +1
#   - 가짜인 부분: 눈 판정(face_service) · LLM · RAG · Agent 는 단계별 고정 문장 · JWT 는 검사 안 함 · DB 대신 서버 메모리
#
# [화면 상태를 골라 보기 — 개발용 /dev/*]
#   POST /dev/scenario  {"scenario": "auto"}      기본. 진짜 규칙대로 (졸음 1번=1단계, 2번=2단계, 3번=3단계)
#                       {"scenario": "normal"}    /detect 는 항상 is_sleep false, 단계 0 (초록 화면)
#                       {"scenario": "stage1"|"stage2"|"stage3"}   /detect · /drive/ping 이 그 단계로 고정
#                       {"scenario": "rest_due"}  다음 /drive/ping 에서 rest_due = true (연속 운전 2시간 알림) 한 번
#   GET  /dev/state     지금 단계 · 졸음 횟수 · 퀴즈 · 시나리오 보기
#   POST /dev/reset     서버 메모리 초기화 (경고 목록은 샘플 4개로 되돌림)
#
# [실행]   venv\Scripts\activate  →  cd sleep_detector_api  →  python mock_server.py
#          http://127.0.0.1:8000/docs   (에뮬레이터 앱은 http://10.0.2.2:8000 · 실기기는 PC 의 IP:8000)
#          필요한 패키지: fastapi · uvicorn · python-multipart (requirements.txt 에 이미 있음)
#
# [주의]
#   - JSON 칸 이름은 팀 약속이라 바꾸지 않는다 (sleep_response.dart · drive_status.dart · sleep_event.dart 와 같아야 함)
#   - 기획안에 칸 이름이 없는 곳(로그인 응답 · /events/my 한 줄 · /admin/*)은 D 가 정했음 → 맨 아래 [임시로 정한 것] 표를 C 와 확인
#   - 시간 기준은 시험하기 좋게 줄여 둠: 휴식 15분 → 10초 (MOCK_REST_SEC), 1단계 자동 해제 10분 → 60초 (MOCK_WINDOW_SEC),
#     음성 퀴즈 간격 2분 → 20초 (MOCK_QUIZ_GAP_SEC). 진짜 값은 config.py (REST_MIN · WINDOW_MIN · VOICE_QUIZ_GAP_SEC)
#   - 서버를 다시 켜면 메모리가 비워진다 (진짜 서버의 sleep_state 와 같음)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import difflib
import os
import random
import re
import time
import uuid
from datetime import datetime, timedelta
from typing import Literal, Optional

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, Request, Response, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel

from schema.request import ProfileUpdate   # 전화번호 · 차량번호 형식 검사는 진짜 서버와 같은 것을 쓴다

# ── 기준 숫자 (진짜 서버는 config.py 에서 가져옴) ──────────────────
WINDOW_SEC = int(os.getenv("MOCK_WINDOW_SEC", "60"))          # 1단계 자동 해제 · 졸음 횟수를 세는 구간 (진짜 600)
REST_SEC = int(os.getenv("MOCK_REST_SEC", "10"))              # 휴식 시간 (진짜 900)
QUIZ_GAP_SEC = int(os.getenv("MOCK_QUIZ_GAP_SEC", "20"))      # 음성 퀴즈 최소 간격 (진짜 120)
DRIVE_LIMIT_MIN = 120                                         # 연속 운전 휴게 알림
CALIB_FRAMES = 5                                              # 개인 기준 측정 사진 수
LISTEN_SEC = 10                                               # 음성 퀴즈 듣는 시간 (10/29 STT 시험으로 7 → 10)
REPEAT_MIN_SCORE = 0.8                                        # 따라 말하기 통과 유사도
VOICE_QUIZ_MAX_TRIES = 2
MAX_PHOTO_BYTES = 10 * 1024 * 1024
DEFAULT_EAR_THRESHOLD = 0.23                                  # 개인 기준이 없을 때 서버 EAR 기준 (진짜 서버 config.EAR_THRESHOLD 와 같게)

STAGE_LABELS = {0: "정상", 1: "주의", 2: "휴식 권고", 3: "긴급"}
EVENT_STATUSES = ["미확인", "확인", "조치완료", "휴식완료"]
REASONS = ["microsleep", "perclos", "rest_overdue", "no_response"]

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
EVENT_DIR = os.path.join(BASE_DIR, "uploads", "events")
STATIC_DIR = os.path.join(BASE_DIR, "static")
REPEAT_FILE = os.path.join(BASE_DIR, "knowledge", "voice_quiz", "repeat_sentences.txt")

app = FastAPI(title="sleep_detector mock server (D)", description="C 앱 연결용 임시 서버 — 진짜 서버가 아님")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


# ═══════════════════════════════════════════════════════════════
# 서버 메모리 (진짜 서버: MySQL users · sleep_events + sleep_state)
# ═══════════════════════════════════════════════════════════════
USERS: dict = {}          # user_id → {id, email, name, role}
PHOTOS: dict = {}         # user_id → {"name", "bytes"}  프로필 사진 (메모리에만 보관)
EVENTS: list = []         # 경고 목록 (sleep_events 한 줄 = dict 하나)
STATES: dict = {}         # user_id → 기사별 졸음 상태 (sleep_state)
QUIZZES: dict = {}        # quiz_id → {user_id, type, answer, asked, event_id}
SCENARIO = {"name": "auto"}
_next = {"user": 1, "event": 1}


def _now_text(dt: Optional[datetime] = None) -> str:
    return (dt or datetime.now()).isoformat(timespec="seconds")


def _new_state() -> dict:
    return {
        "stage": 0, "sleeps": [], "last_closed_sec": 0.0,
        "drive_start": None, "drive_offset_min": 0, "rest_due_sent": False,
        "rest_started": None, "rest_event_id": None,
        "last_quiz_at": 0.0, "quiz_fail": 0, "last_ping": None,
        "calib": 0, "ear_threshold": DEFAULT_EAR_THRESHOLD,
    }


def state_of(user_id: int) -> dict:
    return STATES.setdefault(user_id, _new_state())


def add_user(email: str, name: str, role: str = "user", phone: Optional[str] = None, vehicle_no: Optional[str] = None) -> dict:
    for u in USERS.values():
        if u["email"] == email:
            return u
    user = {"id": _next["user"], "email": email, "name": name, "role": role, "phone": phone, "vehicle_no": vehicle_no,
            "created_at": datetime.now().isoformat(timespec="seconds")}  # 내 정보 '가입일' (진짜 서버 /users/me 와 같은 칸)
    USERS[user["id"]] = user
    _next["user"] += 1
    return user


# ═══════════════════════════════════════════════════════════════
# 로그인 대신 — Bearer 토큰이 있기만 하면 통과 (진짜 서버는 JWT 검사)
# ═══════════════════════════════════════════════════════════════
def current_user(authorization: Optional[str] = Header(None)) -> dict:
    if not authorization or not authorization.lower().startswith("bearer ") or not authorization[7:].strip():
        raise HTTPException(status_code=401, detail="로그인이 필요합니다")
    token = authorization[7:].strip()
    m = re.fullmatch(r"mock-token-(\d+)", token)
    if m and int(m.group(1)) in USERS:
        return USERS[int(m.group(1))]
    return USERS[1]  # 구글 로그인 토큰 등 다른 토큰도 시험용 기사(1번)로 통과


def require_admin(user: dict = Depends(current_user)) -> dict:
    if user["role"] != "admin":
        raise HTTPException(status_code=403, detail="관리자만 사용할 수 있습니다")
    return user


# ═══════════════════════════════════════════════════════════════
# sleep_state 흉내 — 졸음 횟수 → 규칙 단계, set_stage(올리기만), 1단계 자동 해제
# ═══════════════════════════════════════════════════════════════
def recent_sleeps(st: dict) -> list:
    cutoff = time.time() - WINDOW_SEC
    st["sleeps"] = [t for t in st["sleeps"] if t >= cutoff]
    return st["sleeps"]


def rule_stage(count: int) -> int:
    return min(count, 3)  # 1번=1 · 2번=2 · 3번 이상=3


def set_stage(st: dict, new_stage: int) -> int:
    st["stage"] = max(st["stage"], min(new_stage, 3))  # 올리기만 (퀴즈로 올라간 단계 유지)
    return st["stage"]


def refresh_stage(st: dict) -> int:
    """1단계에서 구간 동안 졸음이 없으면 0단계로 (2단계 이상은 자동으로 안 내려감)."""
    if SCENARIO["name"] == "normal":
        st["stage"] = 0
    elif st["stage"] == 1 and not recent_sleeps(st):
        st["stage"] = 0
    return st["stage"]


def reset_state(st: dict) -> None:
    """관리자 조치완료 · 운행 시작 — 졸음 기록과 단계를 0 으로."""
    st.update({"stage": 0, "sleeps": [], "last_closed_sec": 0.0, "quiz_fail": 0, "rest_started": None, "rest_event_id": None})


def drive_min_of(st: dict) -> int:
    start = st["drive_start"] or time.time()
    return int((time.time() - start) / 60) + st["drive_offset_min"]


def forced_stage() -> Optional[int]:
    m = re.fullmatch(r"stage([123])", SCENARIO["name"])
    return int(m.group(1)) if m else None


# ═══════════════════════════════════════════════════════════════
# 가짜 AI — LLM 요약 · RAG 규정 · Agent 안내문 · 기사 음성 보고 (진짜는 services/*)
# ═══════════════════════════════════════════════════════════════
MOCK_REGULATIONS = [
    {"title": "연속 운전 후 휴게시간 (모의)", "source": "mock_server 고정 문장",
     "content": "모의 데이터입니다. 실제 규정 원문은 RAG 가 연결되면 이 자리에 표시됩니다."},
    {"title": "졸음운전 예방 안내 (모의)", "source": "mock_server 고정 문장",
     "content": "모의 데이터입니다. 졸음이 오면 가까운 졸음쉼터나 휴게소에서 쉬어 가세요."},
]
GUIDANCE = {
    1: "창문을 열고 환기하며 주의해서 운전해 주세요.",
    2: "가까운 졸음쉼터에서 15분 이상 쉬어 주세요.",
    3: "관리자에게 알렸습니다. 안전한 곳에 바로 정차해 주세요.",
}
STAGE_REASON = {
    1: "10분 안 첫 졸음 감지",
    2: "반복된 졸음으로 휴식 필요",
    3: "졸음이 계속되어 긴급 조치 필요",
}
RECOMMENDED = {
    1: "기록 확인",
    2: "기사에게 연락해 휴식 여부 확인",
    3: "즉시 기사에게 연락하고 정차 여부 확인",
}


def _drive_text(minutes: int) -> str:
    return f"{minutes // 60}시간 {minutes % 60}분" if minutes >= 60 else f"{minutes}분"


def make_ai_text(stage: int, reason: str, count: int, closed_sec: float, perclos: float, drive_min: int, lat, lng) -> dict:
    closed = int(round(closed_sec))
    closed_voice = f" 약 {closed}초 동안 눈을 감았습니다." if closed >= 1 else ""
    if reason == "perclos":
        summary = f"눈 감김 비율(PERCLOS)이 {int(round(perclos * 100))}%로 피로가 누적된 상태입니다. 10분 안에 {count}번째 졸음입니다."
    else:
        summary = f"눈을 약 {closed}초간 감고 있었습니다. 10분 안에 {count}번째 졸음입니다." if closed >= 1 else f"눈을 감은 졸음이 감지됐습니다. 10분 안에 {count}번째 졸음입니다."
    if stage == 1:
        voice = f"졸음이 감지됐습니다.{closed_voice} {GUIDANCE[1]}"
    elif stage == 2:
        voice = f"최근 10분 동안 {count}번 졸았습니다. 운행 {_drive_text(drive_min)}째입니다. {GUIDANCE[2]}"
    else:
        voice = f"최근 10분 동안 {count}번 졸았습니다. 관리자에게 알렸습니다. 안전한 곳에 바로 정차해 주세요."
    return {
        "summary": summary, "guidance": GUIDANCE[stage], "driver_voice": voice,
        "report": {
            "situation": summary, "stage_reason": STAGE_REASON[stage],
            "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[stage],
            "location": f"{lat}, {lng}" if lat is not None and lng is not None else "",
            # 진짜 서버(detect.py)와 같은 칸 — 모의 서버의 AI 는 전부 가짜라서 모두 False
            "is_real": {"llm": False, "rag": False, "agent": False, "driver_voice": False},
        },
    }


def get_road_address(lat, lng) -> str:
    """진짜 admin.py 는 카카오 주소 변환. 모의는 고정 주소."""
    if lat is None or lng is None:
        return ""
    return "경기도 성남시 분당구 판교로 (모의 주소)"


# ═══════════════════════════════════════════════════════════════
# voice_quiz_service 흉내 — make_quiz · check_answer (이름 약속)
# ═══════════════════════════════════════════════════════════════
_FALLBACK_SENTENCES = [
    "졸리면 쉬어 가겠습니다", "안전 운전이 최우선입니다", "앞차와 거리를 지키겠습니다", "졸음쉼터에서 쉬어 갑니다",
    "창문을 열고 환기합니다", "차선을 지키며 달립니다", "휴식도 운전의 일부입니다", "급하지 않게 천천히 갑니다",
    "안전벨트를 확인했습니다", "무리하지 않고 쉬겠습니다",
]
_DIGIT_WORD = ["", "일", "이", "삼", "사", "오", "육", "칠", "팔", "구"]
_KO_DIGIT = {"영": 0, "공": 0, "일": 1, "이": 2, "삼": 3, "사": 4, "오": 5, "육": 6, "륙": 6, "칠": 7, "팔": 8, "구": 9}


def _repeat_sentences() -> list:
    try:
        with open(REPEAT_FILE, encoding="utf-8") as f:
            lines = [ln.strip() for ln in f if ln.strip() and not ln.strip().startswith("#")]
        if lines:
            return lines
    except OSError:
        pass
    return _FALLBACK_SENTENCES


def _ko_number(n: int) -> str:
    """10~99 를 한글 숫자로 (23 → 이십삼, 13 → 십삼)."""
    tens, ones = divmod(n, 10)
    return ("" if tens == 1 else _DIGIT_WORD[tens]) + "십" + _DIGIT_WORD[ones]


def _normalize_text(text: str) -> str:
    return re.sub(r"[\s\.,!?~'\"“”‘’·…\-]", "", text or "")


def parse_number(text: str) -> Optional[int]:
    """인식 결과에서 정수 꺼내기 — '68' · '육십팔' · '육십팔이요' 모두 68."""
    arabic = re.findall(r"\d+", text or "")
    if arabic:
        return int(arabic[-1])
    runs = re.findall(r"[영공일이삼사오육륙칠팔구십백]+", text or "")
    for run in reversed(runs):
        total, cur, prev_digit, seen = 0, 0, False, False
        for ch in run:
            if ch in _KO_DIGIT:
                if prev_digit:
                    break  # '팔이요' 의 '이' 처럼 숫자가 붙어 나오면 거기서 끝
                cur, prev_digit, seen = _KO_DIGIT[ch], True, True
            else:  # 십 · 백
                total += (cur or 1) * (10 if ch == "십" else 100)
                cur, prev_digit, seen = 0, False, True
        if seen:
            return total + cur
    return None


def make_quiz(user_id: int, qtype: Optional[str] = None, event_id: Optional[int] = None) -> dict:
    """문제 dict 를 돌려준다 (정답은 서버 QUIZZES 에만 보관, 응답에는 없음). qtype 을 주면 같은 유형 새 문제."""
    qtype = qtype or random.choice(["repeat", "add"])
    if qtype == "repeat":
        sentence = random.choice(_repeat_sentences())
        speak, display, asked, answer = f"따라 말하세요. {sentence}", sentence, sentence, sentence
    else:
        while True:  # 받아올림 없는 2자리 + 2자리
            a, b = random.randint(10, 89), random.randint(10, 89)
            if a % 10 + b % 10 <= 9 and a // 10 + b // 10 <= 9:
                break
        speak = f"잠을 깨워 볼게요. {_ko_number(a)} 더하기 {_ko_number(b)}는?"
        display, asked, answer = f"{a} + {b} = ?", f"{a}+{b}", a + b
    quiz_id = "q_" + uuid.uuid4().hex[:4]
    QUIZZES[quiz_id] = {"user_id": user_id, "type": qtype, "answer": answer, "asked": asked, "event_id": event_id}
    return {"quiz_id": quiz_id, "type": qtype, "speak": speak, "display": display, "listen_sec": LISTEN_SEC}


def check_answer(quiz_id: str, answer_text: str) -> bool:
    quiz = QUIZZES[quiz_id]
    if quiz["type"] == "repeat":
        said, want = _normalize_text(answer_text), _normalize_text(quiz["answer"])
        return bool(said) and difflib.SequenceMatcher(None, said, want).ratio() >= REPEAT_MIN_SCORE
    return parse_number(answer_text) == quiz["answer"]


# ═══════════════════════════════════════════════════════════════
# 경고(sleep_events) 만들기 · 내보내기
# ═══════════════════════════════════════════════════════════════
def add_event(user_id: int, stage: int, reason: str, report: dict, *, summary="", guidance="", ear=None,
              eye_closed_prob=None, method="ear", perclos=None, photo_path=None, lat=None, lng=None,
              status="미확인", created_at=None) -> dict:
    report.setdefault("eye", None)
    report.setdefault("driving_quiz", [])
    report.setdefault("rest", None)
    event = {
        "id": _next["event"], "user_id": user_id, "stage": stage, "status": status, "reason": reason,
        "ear": ear, "eye_closed_prob": eye_closed_prob, "method": method, "perclos": perclos,
        "summary": summary, "guidance": guidance, "report": report, "photo_path": photo_path,
        "latitude": lat, "longitude": lng, "created_at": created_at or _now_text(),
    }
    _next["event"] += 1
    EVENTS.append(event)
    return event


def event_out(e: dict, admin: bool = False) -> dict:
    out = dict(e)
    out.pop("photo_path")
    out["photo_url"] = "/" + e["photo_path"] if e["photo_path"] else None
    out["stage_label"] = STAGE_LABELS[e["stage"]]
    if admin:
        user = USERS.get(e["user_id"], {})
        out["user_name"] = user.get("name", "")
        out["user_email"] = user.get("email", "")
        out["user_phone"] = user.get("phone") or ""
        out["user_vehicle_no"] = user.get("vehicle_no") or ""
        out["address"] = get_road_address(e["latitude"], e["longitude"])
        out["urgent"] = e["stage"] == 3 or e["reason"] == "no_response"  # 빨간 줄
    return out


def seed() -> None:
    now = datetime.now()
    quiz_ok = [{"type": "add", "asked": "23+45", "heard": "육십팔", "passed": True, "answer_sec": 2.1}]
    quiz_fail = [{"type": "repeat", "asked": "졸리면 쉬어 가겠습니다", "heard": "", "passed": False, "answer_sec": None},
                 {"type": "add", "asked": "31+52", "heard": "", "passed": False, "answer_sec": None}]
    add_event(1, 1, "microsleep", {"situation": "10분 안 첫 졸음, 눈 감김 약 2초", "stage_reason": STAGE_REASON[1],
              "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[1], "location": "37.4021, 127.1088",
              "eye": {"closed_sec": 2.1, "perclos": 0.12, "eye_open_prob": 0.18}, "driving_quiz": quiz_ok,
              "is_real": {"llm": True, "rag": True, "agent": True, "driver_voice": True}},  # 시험용: 전부 진짜인 경고
              summary="눈을 약 2초간 감고 있었습니다. 10분 안에 1번째 졸음입니다.", guidance=GUIDANCE[1], ear=0.17, method="ear",
              perclos=0.12, eye_closed_prob=0.82, lat=37.4021, lng=127.1088, status="확인", created_at=_now_text(now - timedelta(hours=3)))
    add_event(1, 2, "perclos", {"situation": "10분 안 두 번째 졸음, PERCLOS 33%", "stage_reason": STAGE_REASON[2],
              "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[2], "location": "37.4105, 127.1190",
              "eye": {"closed_sec": 0.8, "perclos": 0.33, "eye_open_prob": 0.4}, "driving_quiz": quiz_ok,
              "rest": {"started": "03:20", "resumed": "03:38", "minutes": 18},
              "is_real": {"llm": True, "rag": False, "agent": True, "driver_voice": True}},  # 시험용: 규정 검색만 가짜로 대체된 경고
              summary="눈 감김 비율(PERCLOS)이 33%로 피로가 누적된 상태입니다. 10분 안에 2번째 졸음입니다.", guidance=GUIDANCE[2],
              ear=0.19, method="ear", perclos=0.33, eye_closed_prob=0.6, lat=37.4105, lng=127.1190, status="휴식완료",
              created_at=_now_text(now - timedelta(hours=2)))
    add_event(3, 3, "no_response", {"situation": "운전 중 음성 퀴즈에 2번 답하지 못함", "stage_reason": STAGE_REASON[3],
              "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[3], "location": "37.3950, 127.1100",
              "driving_quiz": quiz_fail}, summary="운전 중 음성 퀴즈에 2번 답하지 못했습니다.", guidance=GUIDANCE[3],
              lat=37.3950, lng=127.1100, created_at=_now_text(now - timedelta(minutes=20)))
    add_event(1, 1, "rest_overdue", {"situation": "연속 운전 2시간 안내 뒤 15분 안에 쉬지 않음", "stage_reason": "휴게 미준수 (단계는 올리지 않고 최소 1단계로 기록)",
              "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": "기사에게 휴식 안내", "location": "37.4300, 127.1300"},
              summary="휴게 시간을 지키지 않았습니다.", guidance="가까운 졸음쉼터에서 쉬어 주세요.",
              lat=37.4300, lng=127.1300, created_at=_now_text(now - timedelta(minutes=50)))


def reset_all() -> None:
    USERS.clear(); EVENTS.clear(); STATES.clear(); QUIZZES.clear(); PHOTOS.clear()
    _next.update({"user": 1, "event": 1})
    SCENARIO["name"] = "auto"
    add_user("driver@test.com", "김기사", phone="010-2345-6789", vehicle_no="경기 34나 7890")
    add_user("admin@test.com", "관리자", "admin")
    add_user("driver2@test.com", "이기사")          # 일부러 전화번호 · 차량번호 없이 — 관리자 웹의 '미등록' 표시 시험용
    seed()


reset_all()
os.makedirs(EVENT_DIR, exist_ok=True)
app.mount("/uploads/events", StaticFiles(directory=EVENT_DIR), name="events")
if os.path.isdir(STATIC_DIR):
    app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")


# ═══════════════════════════════════════════════════════════════
# 숫자 · 글자 정리 (수업에서 배운 '5' 문자열 사고 방지 — Form 은 전부 글자로 받아서 직접 바꿈)
# ═══════════════════════════════════════════════════════════════
def to_float(value, default=None):
    try:
        return float(value) if value not in (None, "") else default
    except (TypeError, ValueError):
        return default


async def read_body(request: Request) -> dict:
    ctype = request.headers.get("content-type", "")
    try:
        if "json" in ctype:
            data = await request.json()
        elif "form" in ctype:
            data = dict(await request.form())
        else:
            data = {}
    except Exception:
        data = {}
    return data if isinstance(data, dict) else {}


# ═══════════════════════════════════════════════════════════════
# Pydantic (진짜 서버에서는 schema/request.py)
# ═══════════════════════════════════════════════════════════════
class DrivePing(BaseModel):
    perclos: Optional[float] = None


class VoiceQuizAnswer(BaseModel):
    quiz_id: str
    answer_text: str = ""
    answer_sec: Optional[float] = None


class StatusUpdate(BaseModel):
    status: Literal["미확인", "확인", "조치완료", "휴식완료"]


class ChatRequest(BaseModel):
    message: str


# ═══════════════════════════════════════════════════════════════
# users — 회원가입 · 로그인 (비밀번호 검사 없음)
# ═══════════════════════════════════════════════════════════════
def login_response(user: dict) -> dict:
    return {"success": True, "access_token": f"mock-token-{user['id']}", "token_type": "bearer", "user": user}


@app.post("/users/signup")
async def signup(request: Request):
    body = await read_body(request)
    email = str(body.get("email") or body.get("username") or "").strip()
    if not email:
        raise HTTPException(status_code=422, detail="email 이 필요합니다")
    if any(u["email"] == email for u in USERS.values()):
        raise HTTPException(status_code=400, detail="이미 가입된 이메일입니다")
    user = add_user(email, str(body.get("name") or email.split("@")[0]))
    return {"success": True, "message": "가입되었습니다", "user": user}


@app.post("/users/login")
async def login(request: Request):
    body = await read_body(request)
    email = str(body.get("email") or body.get("username") or "").strip()  # OAuth2 폼이면 username
    if not email:
        raise HTTPException(status_code=422, detail="email 이 필요합니다")
    return login_response(add_user(email, email.split("@")[0], "admin" if email.startswith("admin") else "user"))


@app.post("/users/google")
async def login_google(request: Request):
    await read_body(request)
    return login_response(USERS[1])


@app.get("/users/me")
def me(user: dict = Depends(current_user)):
    photo = PHOTOS.get(user["id"])
    return {**user, "provider": "email", "photo_url": photo["name"] if photo else None}


# 내 전화번호 · 차량번호 — 진짜 서버(routers/user.py)와 같은 규칙 (schema.request 의 검사를 그대로 씀): 빠진 칸은 그대로, ''면 지움
@app.patch("/users/me")
def update_me(body: ProfileUpdate, user: dict = Depends(current_user)):
    if "phone" in body.model_fields_set and body.phone is not None:
        user["phone"] = body.phone or None
    if "vehicle_no" in body.model_fields_set and body.vehicle_no is not None:
        user["vehicle_no"] = body.vehicle_no or None
    return me(user)


# 프로필 사진 — 진짜 서버(routers/user.py)와 같은 규칙: 확장자 · 5MB · 사진 받기는 로그인 토큰이 있어야 함 (메모리에만 보관)
PROFILE_ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
PROFILE_MAX_BYTES = 5 * 1024 * 1024
_MEDIA ={".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".heic": "image/heic"}


@app.post("/users/me/photo")
async def upload_my_photo(file: UploadFile = File(...), user: dict = Depends(current_user)):
    ext = os.path.splitext(file.filename or "photo.jpg")[1].lower() or ".jpg"
    if ext not in PROFILE_ALLOWED_EXTS:
        raise HTTPException(status_code=400, detail=f"이미지 파일만 올릴 수 있습니다 ({', '.join(sorted(PROFILE_ALLOWED_EXTS))})")
    content = await file.read()
    if not content:
        raise HTTPException(status_code=400, detail="빈 파일입니다")
    if len(content) > PROFILE_MAX_BYTES:
        raise HTTPException(status_code=413, detail=f"사진이 너무 큽니다 (최대 {PROFILE_MAX_BYTES // (1024 * 1024)}MB)")
    name = f"u{user['id']}_{uuid.uuid4().hex[:12]}{ext}"
    PHOTOS[user["id"]] = {"name": name, "bytes": content}
    return {"success": True, "photo_url": name}


@app.get("/users/me/photo")
def get_my_photo(user: dict = Depends(current_user)):
    photo = PHOTOS.get(user["id"])
    if not photo:
        raise HTTPException(status_code=404, detail="프로필 사진이 없습니다")
    return Response(content=photo["bytes"], media_type=_MEDIA.get(os.path.splitext(photo["name"])[1], "application/octet-stream"))


@app.delete("/users/me/photo")
def delete_my_photo(user: dict = Depends(current_user)):
    PHOTOS.pop(user["id"], None)
    return {"success": True}


# ═══════════════════════════════════════════════════════════════
# drive — 운행 시작 · 개인 기준 · ping · 휴식 · 운행 재개
# ═══════════════════════════════════════════════════════════════
@app.post("/drive/start")
def drive_start(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    reset_state(st)
    st.update({"drive_start": time.time(), "drive_offset_min": 0, "rest_due_sent": False, "last_quiz_at": 0.0, "last_ping": time.time()})
    return {"success": True, "message": "운행을 시작합니다", "stage": 0, "status": STAGE_LABELS[0]}


@app.post("/drive/calibrate")
async def drive_calibrate(file: UploadFile = File(...), user: dict = Depends(current_user)):
    await file.read()  # 사진은 저장하지 않음
    st = state_of(user["id"])
    st["calib"] += 1
    done = st["calib"] >= CALIB_FRAMES
    if done:
        st["calib"] = 0
        st["ear_threshold"] = 0.21
    return {"success": True, "face_found": True, "count": CALIB_FRAMES if done else st["calib"], "needed": CALIB_FRAMES,
            "done": done, "ear_threshold": st["ear_threshold"] if done else None}


@app.post("/drive/ping")
def drive_ping(body: Optional[DrivePing] = None, user: dict = Depends(current_user)):
    st = state_of(user["id"])
    if st["drive_start"] is None:  # /drive/start 없이 와도 시작한 것으로 본다
        st["drive_start"] = time.time()
    st["last_ping"] = time.time()
    fs = forced_stage()
    if fs:
        st["stage"], st["sleeps"] = fs, [time.time()] * fs
    stage = refresh_stage(st)
    minutes = drive_min_of(st)
    rest_due, rest_message = False, ""
    if minutes >= DRIVE_LIMIT_MIN and not st["rest_due_sent"]:  # 한 번만
        st["rest_due_sent"] = True
        rest_due = True
        rest_message = f"연속 {DRIVE_LIMIT_MIN // 60}시간 운전했습니다. 규정상 15분 이상 휴식이 필요합니다. 가까운 졸음쉼터를 확인하세요."
    return {"stage": stage, "status": STAGE_LABELS[stage], "drive_min": minutes, "rest_due": rest_due, "rest_message": rest_message}


@app.post("/drive/rest")
def drive_rest(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    st["rest_started"] = time.time()
    open_events = [e for e in EVENTS if e["user_id"] == user["id"] and e["stage"] == 2 and e["status"] in ("미확인", "확인")]
    st["rest_event_id"] = open_events[-1]["id"] if open_events else None
    return {"success": True, "message": "15분 쉬고 출발하세요", "rest_sec": REST_SEC, "started": _now_text()}


@app.post("/drive/resume")
def drive_resume(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    if st["rest_started"] is None:
        raise HTTPException(status_code=400, detail="정차 기록이 없습니다. [정차했어요] 를 먼저 눌러 주세요")
    elapsed = time.time() - st["rest_started"]
    if elapsed < REST_SEC:
        raise HTTPException(status_code=409, detail=f"아직 휴식 시간이 지나지 않았습니다 ({int(REST_SEC - elapsed) + 1}초 남음)")
    if st["stage"] == 2:  # 2단계만 1단계로. 3단계는 관리자만 해제, 1단계는 그대로
        st["stage"] = 1
        st["sleeps"] = [time.time()]
    event = next((e for e in EVENTS if e["id"] == st["rest_event_id"]), None)
    if event:
        started = datetime.fromtimestamp(st["rest_started"])
        event["status"] = "휴식완료"
        event["report"]["rest"] = {"started": started.strftime("%H:%M"), "resumed": datetime.now().strftime("%H:%M"), "minutes": int(elapsed // 60)}
    st["rest_started"], st["rest_event_id"], st["drive_start"], st["drive_offset_min"], st["rest_due_sent"] = None, None, time.time(), 0, False
    stage = st["stage"]
    msg = {0: "운행을 재개합니다", 1: "주의 단계로 다시 출발합니다", 3: "긴급 단계는 관리자가 조치완료를 누르기 전까지 해제되지 않습니다"}[stage]
    return {"success": True, "stage": stage, "status": STAGE_LABELS[stage], "message": msg}


# ═══════════════════════════════════════════════════════════════
# detect — 졸음 의심 사진 확인 (face_service · LLM · RAG · Agent 는 가짜)
# ═══════════════════════════════════════════════════════════════
@app.post("/detect")
async def detect(
    file: Optional[UploadFile] = File(None),  # 없으면 = 고개를 떨궈 얼굴을 놓친 채 감김 (진짜 서버와 같음, 10/28)
    reason: str = Form(""),
    closed_sec: str = Form(""),
    perclos: str = Form(""),
    eye_open_prob: str = Form(""),
    latitude: str = Form(""),
    longitude: str = Form(""),
    user: dict = Depends(current_user),
):
    if file is None and not reason:
        raise HTTPException(status_code=400, detail="사진이 필요합니다 (사진 없이는 운행 중 졸음 의심만 보낼 수 있음)")
    photo = await file.read() if file is not None else None
    if photo is not None and len(photo) > MAX_PHOTO_BYTES:
        raise HTTPException(status_code=413, detail="사진은 10MB 이하여야 합니다")
    if photo is not None and not photo:
        raise HTTPException(status_code=400, detail="사진이 비어 있습니다")
    st = state_of(user["id"])
    reason = reason if reason in ("microsleep", "perclos") else "microsleep"  # 비어 있으면 '사진 1장 테스트'
    closed = to_float(closed_sec, 0.0)
    perclos_v = to_float(perclos)
    open_prob = to_float(eye_open_prob)
    lat, lng = to_float(latitude), to_float(longitude)
    ear = 0.16 if photo is not None else None  # 서버 EAR 확인 (가짜 고정값) — 사진이 없으면 확인 없이 앱 판단대로
    base = {"success": True, "ear": ear, "eye_open_prob": open_prob, "method": "ear" if photo is not None else "mlkit", "perclos": perclos_v,
            "ear_threshold": st["ear_threshold"]}

    if SCENARIO["name"] == "normal":  # 확인 판정이 '취소' — 사진은 바로 버림
        stage = refresh_stage(st)
        return {**base, "is_sleep": False, "reason": "", "stage": stage, "status": STAGE_LABELS[stage], "summary": "", "guidance": "",
                "driver_voice": "", "sleep_count_10min": len(recent_sleeps(st)), "voice_quiz": None, "regulations": [], "event_id": None}

    # ③ 졸음 1회 기록 → 규칙 단계 (시나리오 stageN 이면 그 단계로 고정)
    fs = forced_stage()
    if fs:
        st["sleeps"], st["stage"] = [time.time()] * fs, fs
        count, stage = fs, fs
    else:
        refresh_stage(st)
        recent_sleeps(st).append(time.time())
        count = len(st["sleeps"])
        stage = set_stage(st, rule_stage(count))
    st["last_closed_sec"] = closed

    # ④⑤⑥ 가짜 요약 · 규정 · Agent
    ai = make_ai_text(stage, reason, count, closed, perclos_v or 0.0, drive_min_of(st), lat, lng)
    ai["report"]["eye"] = {"closed_sec": closed, "perclos": perclos_v, "eye_open_prob": open_prob, "ear": ear, "photo": photo is not None}

    # ⑦ 저장 (사진 uploads/events/ + 경고 1줄, 사진 없이 온 경고는 photo_path 없음)
    photo_path = None
    if photo is not None:
        photo_name = f"{uuid.uuid4().hex}.jpg"
        with open(os.path.join(EVENT_DIR, photo_name), "wb") as f:
            f.write(photo)
        photo_path = f"uploads/events/{photo_name}"
    event = add_event(user["id"], stage, reason, ai["report"], summary=ai["summary"], guidance=ai["guidance"], ear=ear,
                      eye_closed_prob=None if open_prob is None else round(1 - open_prob, 3), method=base["method"], perclos=perclos_v,
                      photo_path=photo_path, lat=lat, lng=lng)

    # ⑧ 음성 퀴즈 1문제 (최소 간격 안이면 null)
    voice_quiz = None
    if time.time() - st["last_quiz_at"] >= QUIZ_GAP_SEC:
        voice_quiz = make_quiz(user["id"], event_id=event["id"])
        st["last_quiz_at"] = time.time()
        st["quiz_fail"] = 0

    return {**base, "is_sleep": True, "reason": reason, "stage": stage, "status": STAGE_LABELS[stage], "summary": ai["summary"],
            "guidance": ai["guidance"], "driver_voice": ai["driver_voice"], "sleep_count_10min": count, "voice_quiz": voice_quiz,
            "regulations": MOCK_REGULATIONS, "event_id": event["id"]}


# ═══════════════════════════════════════════════════════════════
# quiz — 운전 중 음성 퀴즈 채점 (통과해도 단계를 내리지 않는다)
# ═══════════════════════════════════════════════════════════════
@app.post("/quiz/answer")
def quiz_answer(body: VoiceQuizAnswer, user: dict = Depends(current_user)):
    quiz = QUIZZES.get(body.quiz_id)
    if not quiz or quiz["user_id"] != user["id"]:
        raise HTTPException(status_code=404, detail="없는 퀴즈입니다")
    st = state_of(user["id"])
    heard = (body.answer_text or "").strip()
    passed = check_answer(body.quiz_id, heard) if heard else False  # 무응답은 실패
    line = {"type": quiz["type"], "asked": quiz["asked"], "heard": heard, "passed": passed,
            "answer_sec": body.answer_sec if heard else None}
    origin = next((e for e in EVENTS if e["id"] == quiz["event_id"]), None)
    if origin:
        origin["report"]["driving_quiz"].append(line)
    stage = refresh_stage(st)
    result = {"success": True, "passed": passed, "next_quiz": None, "stage_up": False, "stage": stage, "status": STAGE_LABELS[stage]}

    if passed:
        st["quiz_fail"] = 0
        return {**result, "message": "잘하셨습니다. 쉼터까지 조심히 가세요."}

    st["quiz_fail"] += 1
    if st["quiz_fail"] < VOICE_QUIZ_MAX_TRIES:  # 1번 실패 → 같은 유형 새 문제
        nxt = make_quiz(user["id"], quiz["type"], quiz["event_id"])
        return {**result, "next_quiz": nxt, "message": "다시 한 번 말씀해 주세요."}

    # 2번 실패 → 단계 +1 (최대 3) · 관리자 알림 · reason = no_response 경고 1줄
    failed = [line] if not origin else origin["report"]["driving_quiz"][-VOICE_QUIZ_MAX_TRIES:]
    new_stage = set_stage(st, stage + 1)
    ai = make_ai_text(new_stage, "microsleep", len(recent_sleeps(st)), st["last_closed_sec"], 0.0, drive_min_of(st), None, None)
    ai["report"]["situation"] = "운전 중 음성 퀴즈에 2번 답하지 못함"
    ai["report"]["driving_quiz"] = [dict(x) for x in failed]
    add_event(user["id"], new_stage, "no_response", ai["report"], summary="운전 중 음성 퀴즈에 2번 답하지 못했습니다.", guidance=ai["guidance"],
              lat=origin["latitude"] if origin else None, lng=origin["longitude"] if origin else None)
    st["quiz_fail"] = 0
    return {**result, "stage_up": new_stage > stage, "stage": new_stage, "status": STAGE_LABELS[new_stage],
            "message": "응답이 없어 관리자에게 알렸습니다. 안전한 곳에 정차해 주세요."}


# ═══════════════════════════════════════════════════════════════
# events — 내 경고 목록 · 처리 상태 변경
# ═══════════════════════════════════════════════════════════════
@app.get("/events/my")
def events_my(user: dict = Depends(current_user)):
    mine = [e for e in EVENTS if e["user_id"] == user["id"]]
    return [event_out(e) for e in sorted(mine, key=lambda e: e["id"], reverse=True)]


@app.patch("/events/{event_id}/status")
def event_status(event_id: int, body: StatusUpdate, admin: dict = Depends(require_admin)):
    event = next((e for e in EVENTS if e["id"] == event_id), None)
    if not event:
        raise HTTPException(status_code=404, detail="없는 경고입니다")
    event["status"] = body.status
    reset = body.status == "조치완료"
    if reset:  # 3단계 해제 — 앱은 다음 ping 에서 0단계
        reset_state(state_of(event["user_id"]))
    return {"success": True, "id": event_id, "status": event["status"], "stage_reset": reset}


# ═══════════════════════════════════════════════════════════════
# admin — 관리자 웹용
# ═══════════════════════════════════════════════════════════════
@app.get("/admin/events")
def admin_events(stage: Optional[int] = None, status: Optional[str] = None, admin: dict = Depends(require_admin)):
    rows = [e for e in EVENTS if (stage is None or e["stage"] == stage) and (status is None or e["status"] == status)]
    return [event_out(e, admin=True) for e in sorted(rows, key=lambda e: e["id"], reverse=True)]


@app.get("/admin/users")
def admin_users(admin: dict = Depends(require_admin)):
    out = []
    for u in USERS.values():
        mine = [e for e in EVENTS if e["user_id"] == u["id"]]
        out.append({**u, "event_count": len(mine), "last_event_at": max((e["created_at"] for e in mine), default=None)})
    return out


@app.get("/admin/stats/stage")
def admin_stats_stage(admin: dict = Depends(require_admin)):
    return [{"stage": s, "label": STAGE_LABELS[s], "count": sum(1 for e in EVENTS if e["stage"] == s)} for s in (1, 2, 3)]


@app.get("/admin/stats/hourly")
def admin_stats_hourly(admin: dict = Depends(require_admin)):
    counts = [0] * 24
    for e in EVENTS:
        counts[int(e["created_at"][11:13])] += 1
    return [{"hour": h, "count": c} for h, c in enumerate(counts)]


# ═══════════════════════════════════════════════════════════════
# chat — 규정 도우미 (RAG 대신 고정 대답)
# ═══════════════════════════════════════════════════════════════
@app.get("/chat/hello")
def chat_hello():
    return {"message": "안녕하세요. 졸음운전 · 휴게시간 규정을 물어보세요. (모의 서버)"}


@app.post("/chat")
def chat(body: ChatRequest, user: dict = Depends(current_user)):
    return {"success": True, "answer": f"[모의 답변] '{body.message}' 에 대한 규정 안내는 RAG 가 연결되면 표시됩니다.", "sources": MOCK_REGULATIONS[:1]}


# ═══════════════════════════════════════════════════════════════
# dev — 화면 상태 고르기 (진짜 서버에는 없음)
# ═══════════════════════════════════════════════════════════════
SCENARIOS = ["auto", "normal", "stage1", "stage2", "stage3", "rest_due"]


@app.post("/dev/scenario")
def dev_scenario(body: dict):
    name = str(body.get("scenario", ""))
    if name not in SCENARIOS:
        raise HTTPException(status_code=400, detail=f"scenario 는 {' · '.join(SCENARIOS)} 중 하나")
    if name == "rest_due":  # 한 번짜리 — 시나리오는 그대로 두고 연속 운전 시간만 2시간으로
        for st in STATES.values():
            st.update({"drive_start": st["drive_start"] or time.time(), "drive_offset_min": DRIVE_LIMIT_MIN, "rest_due_sent": False})
        return {"success": True, "scenario": SCENARIO["name"], "note": "다음 /drive/ping 에서 rest_due = true"}
    SCENARIO["name"] = name
    fs = forced_stage()
    for uid in USERS:
        st = state_of(uid)
        if name == "normal":
            reset_state(st)
        elif fs:
            st["stage"], st["sleeps"] = fs, [time.time()] * fs
    return {"success": True, "scenario": name}


@app.get("/dev/state")
def dev_state():
    return {"scenario": SCENARIO["name"], "timing": {"window_sec": WINDOW_SEC, "rest_sec": REST_SEC, "quiz_gap_sec": QUIZ_GAP_SEC},
            "users": {uid: {"stage": st["stage"], "sleep_count": len(recent_sleeps(st)), "drive_min": drive_min_of(st),
                            "quiz_fail": st["quiz_fail"], "resting": st["rest_started"] is not None, "ear_threshold": st["ear_threshold"]}
                      for uid, st in STATES.items()},
            "event_count": len(EVENTS)}


@app.post("/dev/reset")
def dev_reset():
    reset_all()
    return {"success": True, "message": "서버 메모리를 처음 상태로 되돌렸습니다"}


# ═══════════════════════════════════════════════════════════════
# [임시로 정한 것 — 기획안에 칸 이름이 없어서 D 가 정함. C 와 확인 필요]
#   로그인 · 가입 요청     JSON {email, password, name} 또는 폼(username=이메일). 비밀번호는 검사 안 함
#   로그인 응답            {success, access_token, token_type:"bearer", user:{id,email,name,role}}   ← 토큰 칸 이름 access_token 확정 필요
#   /detect 요청 Form      file(사진) · reason · closed_sec · perclos · eye_open_prob · latitude · longitude  (전부 글자로 받아 서버가 숫자로 바꿈)
#   /drive/calibrate       Form file (사진 1장). 5장째에 done=true · ear_threshold
#   /drive/resume 오류     정차 기록 없으면 400, 휴식 시간 전이면 409 (detail 글자) — 앱이 어떻게 보여줄지 확인
#   /events/my 한 줄       id · user_id · stage · stage_label · status · reason · ear · eye_closed_prob · method · perclos · summary · guidance
#                          · report(객체: situation · stage_reason · regulation · recommended_action · location · eye · driving_quiz · rest)
#                          · photo_url · latitude · longitude · created_at     (목록은 배열, 최신순)
#   /admin/events 한 줄    위와 같고 + user_name · user_email · user_phone · user_vehicle_no · address · urgent  (전화 · 차량이 없으면 '')
#   /admin/users 한 줄     {id · email · name · role · phone · vehicle_no · event_count · last_event_at}  (phone · vehicle_no 없으면 null)
#   PATCH /users/me        {phone?, vehicle_no?} → 내 정보 (빠진 칸은 그대로, '' 면 지움, 형식이 틀리면 422)
#   PATCH 요청/응답        {status} → {success, id, status, stage_reset}     status: 미확인 · 확인 · 조치완료 · 휴식완료 (아니면 422)
#   관리자 전용            PATCH /events/{id}/status · /admin/*  — role 이 admin 이 아니면 403 (mock 은 이메일이 admin 으로 시작하면 admin)
#   /chat 응답             {success, answer, sources}
#   /quiz/answer 응답      {success, passed, next_quiz, stage_up, stage, status, message}  (기획안 9-6)
# ═══════════════════════════════════════════════════════════════
if __name__ == "__main__":
    import uvicorn

    uvicorn.run("mock_server:app", host="0.0.0.0", port=8000, reload=True)
