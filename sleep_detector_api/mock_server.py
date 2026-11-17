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
#       POST /admin/signup/check · /admin/signup   관리자 회원가입 (11/17): 회사가 정한 '인증된 사번'(모의 기본 20240001~20240005)만, 한 사번은 한 번만
#       POST /users/me/email/request · /users/me/email/confirm   이메일 변경 (11/17): 새 이메일 + 지금 비밀번호 → 6자리 인증번호 → 확인. 구글 계정은 거절.
#                          모의라서 메일은 안 보내고 서버 화면(로그)에 인증번호를 찍고, 응답의 dev_code 로도 알려 준다 (진짜 서버는 메일로만 보내고 dev_code 는 주지 않음)
#       POST /detect                       졸음 의심 사진 1장 + reason · closed_sec · perclos · eye_open_prob · latitude · longitude (Form)
#       POST /drive/start · /drive/calibrate · /drive/ping · /drive/rest · /drive/resume
#       GET  /drive/state · POST /drive/end   앱을 껐다 켰을 때 [이어서 운행] (진짜 서버와 같은 모양)
#       POST /quiz/answer                  VoiceQuizAnswer (quiz_id · answer_text · answer_sec)
#       GET  /events/my · GET /events/{id}/photo (본인 또는 관리자) · PATCH /events/{id}/status
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
#     음성 퀴즈는 2단계에 들어갈 때마다 (11/18 2분 간격 뺌, 진짜 서버와 같음). 진짜 값은 config.py (REST_MIN · WINDOW_MIN)
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
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, EmailStr, Field

from schema.request import PasswordChange, ProfileUpdate, check_password_rules, format_phone, format_vehicle_no   # 전화번호 · 차량번호 형식 검사는 진짜 서버와 같은 것을 쓴다
from services import employee_service   # (11/17 C) 시연용 사번 목록 · 전화번호 인증 (DB 없이 씀)

# ── 기준 숫자 (진짜 서버는 config.py 에서 가져옴) ──────────────────
WINDOW_SEC = int(os.getenv("MOCK_WINDOW_SEC", "60"))          # 1단계 자동 해제 · 졸음 횟수를 세는 구간 (진짜 600)
REST_SEC = int(os.getenv("MOCK_REST_SEC", "10"))              # 휴식 시간 (진짜 900)
PRE_WARN_ON = os.getenv("PRE_WARN_ON", "false").lower() in ("1", "true", "yes")  # (11/15) 예비 경고 기본 꺼짐
DRIVE_LIMIT_MIN = 120                                         # 연속 운전 휴게 알림
CALIB_FRAMES = 5                                              # 개인 기준 측정 사진 수
LISTEN_SEC = 10                                               # 음성 퀴즈 듣는 시간 (10/29 STT 시험으로 7 → 10)
REPEAT_MIN_SCORE = 0.7                                        # 따라 말하기 통과 유사도 (11/02 STT 시험 결과 0.8 → 0.7, 진짜 서버 config 와 같게)
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
        "last_quiz_at": 0.0, "quiz_fail": 0, "last_ping": None, "ended": False,
        "calib": 0, "ear_threshold": DEFAULT_EAR_THRESHOLD,
        "pre_warned": False,  # (11/12) 이번 운행에서 예비 경고를 했는지
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
    3: "관리자에게 알렸어요. 안전한 곳에 바로 정차해 주세요.",
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
        summary = f"최근 30초 중 {int(round(perclos * 100))}% 동안 눈을 감아 피로가 쌓인 상태로 보여요. 10분 안에 {count}번째 졸음이에요."
    else:
        summary = f"약 {closed}초간 눈을 감은 미세수면 상태로 보여요. 10분 안에 {count}번째 졸음이에요." if closed >= 1 else f"졸음이 감지됐어요. 10분 안에 {count}번째 졸음이에요."
    # (11/16 팀장) 음성은 '사실 하나 + 행동 하나' 짧은 한 문장 (진짜 서버 agent_service._template_voice 와 같음, 이름은 응답 때 붙임)
    if stage == 1:
        voice = f"{closed}초 동안 눈을 감았어요. 정신 차려 주세요." if closed >= 1 else "눈을 자주 감고 있어요. 정신 차려 주세요."
    elif stage == 2:
        voice = f"10분 새 {count}번 졸았어요. 가까운 쉼터에서 쉬어 가세요."
    else:
        voice = f"10분 새 {count}번 졸았어요. 지금 바로 정차하세요."
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
        speak = f"깨어 있는지 확인할게요. {_ko_number(a)} 더하기 {_ko_number(b)}는?"
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
    out["photo_url"] = f"/events/{e['id']}/photo" if e["photo_path"] else None    # 진짜 서버와 같음: 로그인 필요한 API 주소 (폴더는 공개 안 함)
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
              summary="약 2초간 눈을 감은 미세수면 상태로 보여요. 10분 안에 1번째 졸음이에요.", guidance=GUIDANCE[1], ear=0.17, method="ear",
              perclos=0.12, eye_closed_prob=0.82, lat=37.4021, lng=127.1088, status="확인", created_at=_now_text(now - timedelta(hours=3)))
    add_event(1, 2, "perclos", {"situation": "10분 안 두 번째 졸음, PERCLOS 33%", "stage_reason": STAGE_REASON[2],
              "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[2], "location": "37.4105, 127.1190",
              "eye": {"closed_sec": 0.8, "perclos": 0.33, "eye_open_prob": 0.4}, "driving_quiz": quiz_ok,
              "rest": {"started": "03:20", "resumed": "03:38", "minutes": 18},
              "is_real": {"llm": True, "rag": False, "agent": True, "driver_voice": True}},  # 시험용: 규정 검색만 가짜로 대체된 경고
              summary="최근 30초 중 33% 동안 눈을 감아 피로가 쌓인 상태로 보여요. 10분 안에 2번째 졸음이에요.", guidance=GUIDANCE[2],
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


def seed_more() -> None:
    """(11/16) 관리자 화면 시험용: 기사를 더 늘리고 최근 7일 경고를 흩어 놓는다 (목록 · 그래프가 비어 보이지 않게). 항상 같은 값 (random 씨앗 고정)."""
    now = datetime.now()
    people = [
        ("park@test.com", "박정민", "010-3412-1182", "70바 1182"), ("seo@test.com", "서준호", "010-2287-6834", "12다 6834"),
        ("kang@test.com", "강민서", "010-5521-3391", "25가 3391"), ("lee@test.com", "이서윤", "010-8830-3320", "91사 3320"),
        ("choi@test.com", "최도윤", "010-7742-9021", "83아 9021"), ("jung@test.com", "정예린", "010-6615-2275", "70바 2275"),
        ("han@test.com", "한승우", "010-9104-1190", "82가 1190"), ("yoon@test.com", "윤지호", "010-4478-5547", "91사 5547"),
        ("oh@test.com", "오민재", "010-3369-7712", "83아 7712"),
    ]
    spots = [(37.4021, 127.1088), (37.4105, 127.1190), (37.3950, 127.1100), (37.4300, 127.1300), (36.9921, 127.9246)]
    rng = random.Random(7)

    def make(user_id: int, stage: int, reason: str, when: datetime, status: str, r: Optional[random.Random] = None) -> None:
        lat, lng = (r or rng).choice(spots)
        ai = make_ai_text(stage, reason, min(stage + 1, 3), 2.0, 0.3, 120, lat, lng)
        if reason == "no_response":
            ai["report"]["situation"] = "운전 중 음성 퀴즈에 2번 답하지 못함"
            ai["summary"] = "운전 중 음성 퀴즈에 2번 답하지 못했습니다."
        add_event(user_id, stage, reason, ai["report"], summary=ai["summary"], guidance=ai["guidance"], ear=0.18, method="ear",
                  perclos=0.3, eye_closed_prob=0.7, lat=lat, lng=lng, status=status, created_at=_now_text(when))

    users = [add_user(email, name, phone=phone, vehicle_no=plate) for email, name, phone, plate in people]
    for u in users:                                   # 최근 7일에 흩어진 지난 경고 (이미 처리됨)
        for _ in range(rng.randint(1, 5)):
            stage = rng.choice([1, 1, 1, 2, 2, 3])
            reason = rng.choice(["microsleep", "perclos"]) if stage < 3 else "no_response"
            when = now - timedelta(days=rng.randint(0, 6), hours=rng.randint(1, 23), minutes=rng.randint(0, 59))
            make(u["id"], stage, reason, when, "조치완료" if stage == 3 else ("휴식완료" if stage == 2 else "확인"))
    by_name = {u["name"]: u["id"] for u in users}     # 지금 막 들어온 경고 (처리 전) — 홈의 긴급 경고 · 알림 시험용
    make(by_name["박정민"], 3, "no_response", now - timedelta(minutes=12), "미확인")
    make(by_name["서준호"], 3, "perclos", now - timedelta(minutes=5), "미확인")
    make(by_name["이서윤"], 2, "perclos", now - timedelta(minutes=20), "미확인")
    make(by_name["최도윤"], 1, "microsleep", now - timedelta(minutes=8), "미확인")
    make(by_name["정예린"], 1, "rest_overdue", now - timedelta(minutes=35), "미확인")
    # 지금 주행 중인 기사 (관리자 홈 '주행 중 기사' 시험용): 연속 운전 분을 다르게
    for who, minutes in [("박정민", 140), ("서준호", 95), ("이서윤", 62), ("최도윤", 38), ("정예린", 121), ("강민서", 12)]:
        st = state_of(by_name[who])
        st.update({"drive_start": time.time() - minutes * 60, "last_ping": time.time(), "ended": False, "demo_driving": True})
    # (11/17) 지난달 경고 — 관리자 졸음 경고 화면 요약 카드의 '지난달보다' 비교 시험용. 따로 씨앗(11)을 써서 위 값들(이번 주 경고 · 위치)은 그대로.
    rng_old = random.Random(11)
    prev_last = now.replace(day=1) - timedelta(days=1)          # 지난달 마지막 날
    for u in users:
        for _ in range(rng_old.randint(2, 4)):
            stage = rng_old.choice([1, 1, 1, 2, 2, 3])
            reason = rng_old.choice(["microsleep", "perclos"]) if stage < 3 else "no_response"
            when = prev_last.replace(day=rng_old.randint(1, prev_last.day), hour=rng_old.randint(0, 23), minute=rng_old.randint(0, 59), second=0, microsecond=0)
            make(u["id"], stage, reason, when, "조치완료" if stage == 3 else ("휴식완료" if stage == 2 else "확인"), rng_old)


def demo_history(user_id: int) -> int:
    """(11/17 C) 화면 확인용 운행 기록 — 최근 3주에 걸친 경고 + 방금 생긴 경고 2개(알림 '새 알림' 확인용).

    구글로 처음 로그인한 기사에게 자동으로, 다른 계정은 POST /mock/demo-history {email} 로 넣는다. 넣은 개수를 돌려준다.
    """
    now = datetime.now()
    quiz_ok = [{"type": "add", "asked": "23+45", "heard": "육십팔", "passed": True, "answer_sec": 2.1}]
    quiz_fail = [{"type": "repeat", "asked": "졸리면 쉬어 가겠습니다", "heard": "", "passed": False, "answer_sec": None}]
    situations = {
        "microsleep": "약 {s}초간 눈을 감은 미세수면 상태로 보여요.",
        "perclos": "최근 30초 중 {p}% 동안 눈을 감아 피로가 쌓인 상태로 보여요.",
        "rest_overdue": "연속 운전 2시간 안내 뒤 15분 안에 쉬지 않았어요.",
        "no_response": "운전 중 음성 퀴즈에 2번 답하지 못했어요.",
    }
    # (며칠 전, 시, 분, 단계, 이유, 처리 상태)  — 0일 전 = 오늘
    plan = [
        (20, 6, 40, 1, "microsleep", "확인"), (18, 14, 5, 2, "perclos", "휴식완료"), (16, 3, 22, 1, "microsleep", "확인"),
        (15, 4, 10, 3, "no_response", "조치완료"), (12, 23, 48, 1, "rest_overdue", "확인"), (10, 2, 15, 2, "perclos", "휴식완료"),
        (8, 5, 30, 1, "microsleep", "확인"), (6, 16, 45, 1, "microsleep", "확인"), (5, 1, 55, 2, "perclos", "휴식완료"),
        (3, 4, 20, 3, "no_response", "조치완료"), (2, 13, 10, 1, "rest_overdue", "확인"), (1, 6, 5, 2, "perclos", "휴식완료"),
        (0, max(now.hour - 3, 0), 12, 1, "microsleep", "확인"),
    ]
    spots = [(37.4021, 127.1088), (37.4105, 127.1190), (36.3504, 127.3845), (35.8714, 128.6014), (37.2636, 127.0286)]
    n = 0
    for i, (days, h, m, stage, reason, status) in enumerate(plan):
        t = (now - timedelta(days=days)).replace(hour=h, minute=m, second=0, microsecond=0)
        if t > now:
            t = now - timedelta(hours=1)
        lat, lng = spots[i % len(spots)]
        closed = round(1.2 + (i % 4) * 0.4, 1)
        perclos = 0.18 + (i % 5) * 0.05
        add_event(user_id, stage, reason, {
            "situation": situations[reason].format(s=closed, p=int(perclos * 100)), "stage_reason": STAGE_REASON[stage],
            "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[stage], "location": f"{lat}, {lng}",
            "eye": {"closed_sec": closed, "perclos": perclos, "eye_open_prob": 0.3} if reason in ("microsleep", "perclos") else None,
            "driving_quiz": quiz_fail if reason == "no_response" else quiz_ok,
            "rest": {"started": f"{h:02d}:{(m + 3) % 60:02d}", "resumed": f"{(h + 1) % 24:02d}:{m:02d}", "minutes": 20} if status == "휴식완료" else None,
        }, summary=situations[reason].format(s=closed, p=int(perclos * 100)), guidance=GUIDANCE[stage],
            ear=0.18, method="ear", perclos=perclos, eye_closed_prob=0.7, lat=lat, lng=lng, status=status,
            created_at=_now_text(t))
        n += 1
    # 방금 생긴 경고 2개 — 알림 화면 '새 알림' 과 종 빨간 숫자 확인용
    for mins, stage, reason in ((6, 1, "microsleep"), (1, 2, "perclos")):
        add_event(user_id, stage, reason, {"situation": situations[reason].format(s=1.8, p=31), "stage_reason": STAGE_REASON[stage],
                  "regulation": MOCK_REGULATIONS[0]["title"], "recommended_action": RECOMMENDED[stage], "location": "37.4021, 127.1088",
                  "eye": {"closed_sec": 1.8, "perclos": 0.31, "eye_open_prob": 0.3}, "driving_quiz": quiz_ok},
                  summary=situations[reason].format(s=1.8, p=31), guidance=GUIDANCE[stage], ear=0.18, method="ear",
                  perclos=0.31, lat=37.4021, lng=127.1088, created_at=_now_text(now - timedelta(minutes=mins)))
        n += 1
    return n


@app.post("/mock/demo-history")
async def mock_demo_history(request: Request):
    """(11/17 C) 화면 확인용 운행 기록 넣기 — {email} 계정에 (없으면 422)"""
    body = await read_body(request)
    email = str(body.get("email") or "").strip()
    user = next((u for u in USERS.values() if u["email"] == email), None)
    if user is None:
        raise HTTPException(status_code=422, detail="그 이메일의 계정이 없어요 (앱에서 먼저 로그인해 주세요)")
    return {"success": True, "user_id": user["id"], "added": demo_history(user["id"])}


def reset_all() -> None:
    USERS.clear(); EVENTS.clear(); STATES.clear(); QUIZZES.clear(); PHOTOS.clear()
    _next.update({"user": 1, "event": 1})
    SCENARIO["name"] = "auto"
    add_user("driver@test.com", "김기사", phone="010-2345-6789", vehicle_no="경기 34나 7890")
    add_user("admin@test.com", "관리자", "admin")
    add_user("driver2@test.com", "이기사")          # 일부러 전화번호 · 차량번호 없이 — 관리자 웹의 '미등록' 표시 시험용
    seed()
    seed_more()


reset_all()
os.makedirs(EVENT_DIR, exist_ok=True)
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
    history: Optional[list] = None   # 앱이 보내는 이전 대화 [{role, text}] (진짜 chat_service 가 쓴다)


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
        raise HTTPException(status_code=400, detail="이미 가입된 이메일이에요")
    try:   # 전화번호 · 차량번호 · 동의 검사는 진짜 서버(SignupRequest)와 같은 규칙
        phone = format_phone(str(body["phone"])) if str(body.get("phone") or "").strip() else None
        vehicle_no = format_vehicle_no(str(body["vehicle_no"])) if str(body.get("vehicle_no") or "").strip() else None
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    if body.get("privacy_agreed") is False:
        raise HTTPException(status_code=422, detail="개인정보 수집 · 이용에 동의해야 가입할 수 있어요.")
    # (11/17 C) 사번으로 가입하면 사번 확인 · 전화 인증 표 확인 (진짜 서버 routers/user.py 와 같은 규칙)
    emp_no = None
    if str(body.get("emp_no") or "").strip():
        emp_no = _check_emp_no(str(body["emp_no"]))
        if not employee_service.use_email_token(email, body.get("email_token")):
            raise HTTPException(status_code=400, detail="이메일 인증을 먼저 해 주세요")
        if not phone or not employee_service.use_phone_token(phone, body.get("phone_token")):
            raise HTTPException(status_code=400, detail="전화번호 인증을 먼저 해 주세요")
    user = add_user(email, str(body.get("name") or email.split("@")[0]), phone=phone, vehicle_no=vehicle_no)
    user["emp_no"] = emp_no
    return {"success": True, "message": "가입되었습니다", "user": user}


# (11/17 C) 사번 확인 · 전화번호 인증 (시연용) — 진짜 서버와 같은 주소 · 같은 응답 모양
def _check_emp_no(raw: str) -> str:
    no = employee_service.normalize_emp_no(raw)
    if no not in {n for n, _ in employee_service.DEMO_EMPLOYEES}:
        raise HTTPException(status_code=404, detail="등록되지 않은 사번이에요")
    if any(u.get("emp_no") == no for u in USERS.values()):
        raise HTTPException(status_code=409, detail="이미 가입된 사번이에요")
    return no


@app.post("/users/employee/check")
async def employee_check(request: Request):
    body = await read_body(request)
    no = _check_emp_no(str(body.get("emp_no") or ""))
    return {"ok": True, "emp_no": no, "name": None}


def _phone_or_422(raw) -> str:
    try:
        return format_phone(str(raw or ""))
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))


@app.post("/users/phone/send")
async def phone_send(request: Request):
    body = await read_body(request)
    code = employee_service.send_code(_phone_or_422(body.get("phone")))
    return {"sent": True, "demo": True, "demo_code": code, "expires_sec": employee_service.CODE_TTL_SEC}


_EMAIL_RULE = re.compile(r"^[^\s@]+@[^\s@]+\.[^\s@]+$")


def _email_or_422(raw) -> str:
    email = str(raw or "").strip()
    if not _EMAIL_RULE.match(email):
        raise HTTPException(status_code=422, detail="이메일 형식이 올바르지 않아요")
    return email


@app.post("/users/email/send")
async def email_send(request: Request):
    body = await read_body(request)
    code = employee_service.send_email_code(_email_or_422(body.get("email")))
    return {"sent": True, "demo": True, "demo_code": code, "expires_sec": employee_service.CODE_TTL_SEC}


@app.post("/users/email/verify")
async def email_verify(request: Request):
    body = await read_body(request)
    email = _email_or_422(body.get("email"))
    try:
        token = employee_service.verify_email_code(email, str(body.get("code") or ""))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"verified": True, "email": email, "email_token": token}


@app.post("/users/phone/verify")
async def phone_verify(request: Request):
    body = await read_body(request)
    phone = _phone_or_422(body.get("phone"))
    try:
        token = employee_service.verify_code(phone, str(body.get("code") or ""))
    except ValueError as e:
        raise HTTPException(status_code=400, detail=str(e))
    return {"verified": True, "phone": phone, "phone_token": token}


@app.post("/users/login")
async def login(request: Request):
    body = await read_body(request)
    email = str(body.get("email") or body.get("username") or "").strip()  # OAuth2 폼이면 username
    if not email:
        raise HTTPException(status_code=422, detail="email 이 필요합니다")
    return login_response(add_user(email, email.split("@")[0], "admin" if email.startswith("admin") else "user"))


@app.get("/users/google/config")
def google_config():
    # 진짜 서버는 .env 의 FIREBASE_* 값을 돌려줌. 모의 서버는 구글 창을 열 수 없으니 mock=true 로 알려서 시험용 관리자로 바로 로그인
    return {"enabled": True, "mock": True, "apiKey": "", "authDomain": "", "projectId": "mock", "appId": ""}


@app.post("/users/google")
async def login_google(request: Request):
    # (11/16 D) 관리자 웹 구글 로그인 시험 · (11/17 C) 앱 구글 로그인은 이메일로 계정을 찾거나 만든다
    body = await read_body(request)
    email = str(body.get("email") or "").strip()
    if email.startswith("admin"):          # 관리자 웹 구글 로그인 시험 (진짜 서버는 관리자 계정이면 id_token 을 검증함)
        existed = any(str(u["email"]).lower() == email.lower() for u in USERS.values())
        google_admin = add_user(email, str(body.get("name") or "관리자"), "admin")
        if not existed:
            google_admin["provider"] = "google"                  # 구글로 새로 만든 계정만 표시 (설정에서 이메일 변경 불가). 이미 있던 이메일 계정은 그대로 둠 (진짜 서버는 이때 409)
        return login_response(google_admin)
    if not email:
        return login_response(USERS[1])  # 예전 시험 스크립트처럼 아무것도 안 보내면 기본 기사
    is_new = not any(u["email"] == email for u in USERS.values())
    user = add_user(email, str(body.get("name") or email.split("@")[0]))
    user.setdefault("provider", "google")
    if is_new:
        demo_history(user["id"])  # (11/17 C) 처음 로그인한 구글 계정에 화면 확인용 운행 기록 (연습 서버만)
    return login_response(user)


@app.get("/users/me")
def me(user: dict = Depends(current_user)):
    photo = PHOTOS.get(user["id"])
    return {**user, "provider": user.get("provider", "email"), "photo_url": photo["name"] if photo else None}


# 내 전화번호 · 차량번호 — 진짜 서버(routers/user.py)와 같은 규칙 (schema.request 의 검사를 그대로 씀): 빠진 칸은 그대로, ''면 지움
@app.patch("/users/me")
def update_me(body: ProfileUpdate, user: dict = Depends(current_user)):
    if "name" in body.model_fields_set and body.name is not None:
        user["name"] = body.name
    if "phone" in body.model_fields_set and body.phone is not None:
        user["phone"] = body.phone or None
    if "vehicle_no" in body.model_fields_set and body.vehicle_no is not None:
        user["vehicle_no"] = body.vehicle_no or None
    return me(user)


# 비밀번호 변경 — 새 비밀번호 규칙은 진짜 서버와 같음. 모의 서버는 로그인이 비밀번호를 보지 않아서, 처음 바꿀 때는 지금 비밀번호를 검사하지 않고
# 한 번 바꾼 뒤부터는 그 비밀번호와 맞는지 본다 (관리자 설정 화면의 '비밀번호 불일치' 시험용. 서버를 다시 켜면 처음 상태)
_PASSWORDS: dict = {}   # user_id → 마지막으로 바꾼 비밀번호


@app.put("/users/me/password")
def change_my_password(body: PasswordChange, user: dict = Depends(current_user)):
    saved = _PASSWORDS.get(user["id"])
    if saved is not None and body.current_password != saved:
        raise HTTPException(status_code=400, detail="지금 비밀번호가 맞지 않아요")
    _PASSWORDS[user["id"]] = body.new_password
    return {"success": True}


# 관리자 회원가입 (11/17) — 회사가 따로 정해 둔 '인증된 사번'(숫자) 목록에 있는 번호만 가입할 수 있고, 한 사번으로는 한 번만 가입한다.
#   모의 서버의 인증된 사번: MOCK_EMPLOYEE_NOS 환경변수(쉼표로 구분), 없으면 20240001 ~ 20240005.
#   사번 알아맞히기를 막으려고 같은 접속에서 10분에 5번 틀리면 잠시 막는다. 진짜 서버는 목록을 .env 나 별도 파일에서 읽고, 쓴 사번 기록이 필요함 (칸 추가는 팀과 정함)
EMPLOYEE_NOS = {s.strip() for s in os.getenv("MOCK_EMPLOYEE_NOS", "20240001,20240002,20240003,20240004,20240005").split(",") if s.strip()}
_EMP_USED: dict = {}      # 사번 → 가입한 user_id
_EMP_FAILS: dict = {}     # 접속 주소 → 틀린 시각들


class EmployeeCheck(BaseModel):
    employee_no: str


class AdminSignupRequest(BaseModel):
    employee_no: str
    name: str = Field(..., min_length=1, max_length=50)
    email: EmailStr
    password: str


def _check_employee(raw: str, request: Request) -> str:
    no = re.sub(r"\s", "", str(raw or ""))
    if not re.fullmatch(r"\d{4,12}", no):
        raise HTTPException(status_code=400, detail="사번은 숫자 4~12자리로 입력해 주세요")
    who = request.client.host if request.client else "?"
    now = time.time()
    fails = [t for t in _EMP_FAILS.get(who, []) if now - t < 600]
    if len(fails) >= 5:
        raise HTTPException(status_code=429, detail="사번을 너무 많이 틀렸어요. 10분 뒤에 다시 시도해 주세요")
    if no not in EMPLOYEE_NOS:
        fails.append(now); _EMP_FAILS[who] = fails
        raise HTTPException(status_code=400, detail="등록되지 않은 사번이에요")
    if no in _EMP_USED:
        raise HTTPException(status_code=409, detail="이미 가입에 쓰인 사번이에요")
    return no


@app.post("/admin/signup/check")
def admin_signup_check(body: EmployeeCheck, request: Request):
    _check_employee(body.employee_no, request)
    return {"success": True}


@app.post("/admin/signup")
def admin_signup(body: AdminSignupRequest, request: Request):
    no = _check_employee(body.employee_no, request)
    try:
        check_password_rules(body.password)            # 진짜 서버와 같은 비밀번호 규칙 (한국어 문구)
    except ValueError as e:
        raise HTTPException(status_code=422, detail=str(e))
    email = str(body.email).strip().lower()
    if any(str(u["email"]).lower() == email for u in USERS.values()):
        raise HTTPException(status_code=409, detail="이미 사용중인 이메일입니다")
    user = add_user(email, body.name.strip(), "admin")
    user["employee_no"] = no                          # 사번은 관리자 계정에만 붙음 (기사 화면에는 내보내지 않음)
    _EMP_USED[no] = user["id"]
    _PASSWORDS[user["id"]] = body.password            # 모의 로그인은 비밀번호를 안 보지만, 비밀번호 변경 시험이 되게 기억해 둠
    return {"success": True}


# 이메일 변경 (11/17) — 이메일로 가입한 계정만. 새 이메일 + 지금 비밀번호 → 6자리 인증번호(10분 · 5번까지) → 확인하면 users.email 이 바뀜.
# 모의 서버라 메일은 안 보내고 서버 화면(로그)에 인증번호를 찍는다. 응답의 dev_code 는 모의 서버에서만 (진짜 서버는 메일로만 알려 줌). 인증번호는 메모리에만 보관 (DB 칸 추가 없음)
EMAIL_CODE_TTL_SEC = 600
EMAIL_CODE_RESEND_SEC = int(os.getenv("MOCK_EMAIL_RESEND_SEC", "20"))     # 다시 받기 간격 (진짜는 60초로 하면 됨. 시험하기 좋게 20초)
EMAIL_CODE_MAX_TRIES = 5
_EMAIL_CODES: dict = {}   # user_id → {email, code, expires, sent_at, tries}


class EmailChangeRequest(BaseModel):
    new_email: EmailStr
    current_password: str


class EmailChangeConfirm(BaseModel):
    new_email: EmailStr
    code: str


def _email_taken(email: str, my_id: int) -> bool:
    return any(str(u["email"]).lower() == email and u["id"] != my_id for u in USERS.values())


@app.post("/users/me/email/request")
def request_email_change(body: EmailChangeRequest, user: dict = Depends(current_user)):
    if user.get("provider") == "google":
        raise HTTPException(status_code=400, detail="구글 계정은 이메일을 바꿀 수 없어요")
    saved = _PASSWORDS.get(user["id"])
    if saved is not None and body.current_password != saved:
        raise HTTPException(status_code=400, detail="지금 비밀번호가 맞지 않아요")
    new_email = str(body.new_email).strip().lower()
    if new_email == str(user["email"]).lower():
        raise HTTPException(status_code=400, detail="지금과 같은 이메일이에요")
    if _email_taken(new_email, user["id"]):
        raise HTTPException(status_code=409, detail="이미 사용중인 이메일입니다")
    now = time.time()
    prev = _EMAIL_CODES.get(user["id"])
    if prev and now - prev["sent_at"] < EMAIL_CODE_RESEND_SEC:
        raise HTTPException(status_code=429, detail=f"잠시 뒤에 다시 받아 주세요 ({int(EMAIL_CODE_RESEND_SEC - (now - prev['sent_at'])) + 1}초)")
    code = f"{random.randint(0, 999999):06d}"
    _EMAIL_CODES[user["id"]] = {"email": new_email, "code": code, "expires": now + EMAIL_CODE_TTL_SEC, "sent_at": now, "tries": 0}
    print(f"[모의 메일] {new_email} 로 보낸 인증번호: {code} (10분 안에 입력)")
    return {"success": True, "expires_in": EMAIL_CODE_TTL_SEC, "dev_code": code}


@app.post("/users/me/email/confirm")
def confirm_email_change(body: EmailChangeConfirm, user: dict = Depends(current_user)):
    if user.get("provider") == "google":
        raise HTTPException(status_code=400, detail="구글 계정은 이메일을 바꿀 수 없어요")
    new_email = str(body.new_email).strip().lower()
    entry = _EMAIL_CODES.get(user["id"])
    if not entry or entry["email"] != new_email:
        raise HTTPException(status_code=400, detail="먼저 인증번호를 받아 주세요")
    if time.time() > entry["expires"]:
        _EMAIL_CODES.pop(user["id"], None)
        raise HTTPException(status_code=400, detail="인증번호가 만료됐어요. 다시 받아 주세요")
    if body.code.strip() != entry["code"]:
        entry["tries"] += 1
        left = EMAIL_CODE_MAX_TRIES - entry["tries"]
        if left <= 0:
            _EMAIL_CODES.pop(user["id"], None)
            raise HTTPException(status_code=400, detail="인증번호가 맞지 않아요. 인증번호를 다시 받아 주세요")
        raise HTTPException(status_code=400, detail=f"인증번호가 맞지 않아요 (남은 횟수 {left}번)")
    if _email_taken(new_email, user["id"]):                       # 받는 사이에 다른 사람이 쓴 경우
        _EMAIL_CODES.pop(user["id"], None)
        raise HTTPException(status_code=409, detail="이미 사용중인 이메일입니다")
    user["email"] = new_email
    _EMAIL_CODES.pop(user["id"], None)
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
# ───────────────────────────────────────────────
# POST /drive/wake — (11/15 팀장) 3단계 [깨어 있어요] 응답 {pressed, sec}
#   3단계 경고는 들어오는 순간 관리자에게 긴급으로 이미 간다 → 여기서는 그 경고 기록(report.wake)에 응답만 덧붙인다
#   pressed=True  : 10초 안에(또는 늦게라도) 눌렀음 → 관리자 웹 초록 '깨어 있음 (N초)'
#   pressed=False : 10초 동안 안 누름 → 관리자 웹 빨간 '응답 없음' · 배너 '바로 전화하세요' (알림음은 다시 울리지 않음)
#   가장 최근의 미처리 3단계 경고에 붙인다 (없으면 아무것도 안 함)
# ───────────────────────────────────────────────
@app.post("/drive/wake")
async def drive_wake(request: Request, user: dict = Depends(current_user)):
    body = await read_body(request)
    pressed = bool(body.get("pressed"))
    sec = body.get("sec")
    open3 = [e for e in EVENTS if e["user_id"] == user["id"] and e["stage"] >= 3 and e["status"] != "조치완료"]
    if not open3:
        return {"success": True, "event_id": None}
    event = max(open3, key=lambda e: (e["created_at"], e["id"]))
    event["report"]["wake"] = {"pressed": pressed, "sec": round(float(sec), 1) if isinstance(sec, (int, float)) else None,
                               "at": datetime.now().isoformat(timespec="seconds")}
    return {"success": True, "event_id": event["id"], "pressed": pressed}


def _driver_name(name) -> str:
    return (name or "").strip()   # (11/17 팀장) 이름만 — 리포트 '이름 기사님' · 음성 '이름님' (진짜 서버와 같음)


@app.post("/drive/start")
def drive_start(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    reset_state(st)
    st["session"] = (datetime.now(), _next["event"] - 1)   # (11/16) 운행 종료 리포트: 이 뒤의 경고만
    st.update({"drive_start": time.time(), "drive_offset_min": 0, "rest_due_sent": False, "last_quiz_at": 0.0, "last_ping": time.time(),
               "pre_warned": False})  # (11/12 팀장) 운행마다 첫 졸음은 예비 경고 한 번
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
        st["pre_warned"] = False  # (11/12) 앱은 운행마다 출발 전 측정을 함 → 새 운행의 첫 졸음은 다시 예비 경고
    return {"success": True, "face_found": True, "count": CALIB_FRAMES if done else st["calib"], "needed": CALIB_FRAMES,
            "done": done, "ear_threshold": st["ear_threshold"] if done else None}


@app.post("/drive/ping")
def drive_ping(body: Optional[DrivePing] = None, user: dict = Depends(current_user)):
    st = state_of(user["id"])
    if st["drive_start"] is None:  # /drive/start 없이 와도 시작한 것으로 본다
        st["drive_start"] = time.time()
    st["last_ping"] = time.time()
    st["ended"] = False  # 운행 종료 뒤 다시 ping 이 오면 이어서 운전 중 (진짜 서버 drive_timer.ping 과 같음)
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


# 앱을 껐다 켰을 때 '진행 중인 운행'을 이어 가기 위한 지금 상태 (진짜 서버 GET /drive/state 와 같은 모양)
ACTIVE_PING_SEC = 5 * 60  # 마지막 ping 이 이 시간 안이면 진행 중 (2 · 3단계 · 휴식 중은 시간과 상관없이)


@app.get("/drive/state")
def drive_state(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    stage = refresh_stage(st)
    resting = st["rest_started"] is not None
    last = st["last_ping"]
    recent = last is not None and not st["ended"] and time.time() - last <= ACTIVE_PING_SEC
    summary = guidance = ""
    if stage >= 1:
        open_events = [e for e in EVENTS if e["user_id"] == user["id"] and e["stage"] >= 1 and e["reason"] != "rest_overdue"
                       and e["status"] in ("미확인", "확인")]
        if open_events:
            summary, guidance = open_events[-1].get("summary") or "", open_events[-1].get("guidance") or ""
    left = max(0, int(round(REST_SEC - (time.time() - st["rest_started"])))) if resting else 0
    return {"active": bool(stage >= 2 or resting or recent), "stage": stage, "status": STAGE_LABELS[stage],
            "resting": resting, "rest_left_sec": left, "drive_min": drive_min_of(st), "summary": summary, "guidance": guidance}


_REASON_TEXT = {"microsleep": "눈 감김", "perclos": "피로 누적", "no_face": "고개 숙임", "half": "눈 반쯤 감김"}


@app.post("/drive/end")
def drive_end(user: dict = Depends(current_user)):
    """[운행 종료] — 단계는 그대로, 운전 시간 기록도 그대로 ('끝남' 표시만).
    (11/16 팀장) + 오늘 운행 AI 리포트 (진짜 서버 detect.drive_end_handler 와 같은 모양, 문장은 템플릿)"""
    st = state_of(user["id"])
    st["ended"] = True
    started, last_id = st.pop("session", None) or (None, 0)
    now = datetime.now()
    mine = [e for e in EVENTS if e["user_id"] == user["id"] and e["id"] > last_id and e["stage"] >= 1] if started else []
    sleeps = [e for e in mine if e["reason"] != "rest_overdue"]
    rests = [e["report"]["rest"] for e in mine if (e.get("report") or {}).get("rest")]
    timeline = [{"time": e["created_at"][11:16], "stage": e["stage"], "reason": _REASON_TEXT.get(e["reason"], "졸음"),
                 "event_id": e["id"], **({"rest": e["report"]["rest"]} if e["report"].get("rest") else {}),
                 **({"wake": e["report"]["wake"]} if e["report"].get("wake") else {})} for e in mine]
    stats = {"drive_min": int((now - started).total_seconds() // 60) + int(st.get("drive_offset_min") or 0) if started else 0,
             "sleep_count": len(sleeps), "max_stage": max((e["stage"] for e in sleeps), default=0),
             "rest_count": len(rests), "rest_min": sum(int(r.get("minutes") or 0) for r in rests), "timeline": timeline}
    n, top, rc = stats["sleep_count"], stats["max_stage"], stats["rest_count"]
    drive = _drive_text(stats["drive_min"])
    if n == 0:
        summary = f"오늘 {drive} 동안 졸음 없이 운행했어요." if stats["drive_min"] >= 1 else "오늘 졸음 없이 운행했어요."
        advice = "지금처럼 2시간마다 쉬어 가세요."
    else:
        summary = (f"오늘 {drive} 운행 중 " if stats["drive_min"] >= 1 else "오늘 운행 중 ") + f"{n}번 졸음이 감지됐어요." + (
            " 긴급 단계까지 올라갔어요." if top >= 3 else (" 쉬어 가라는 안내가 있었어요." if top == 2 else ""))
        advice = "다음 운행 전에는 충분히 자고 출발하세요." if top >= 3 else "졸음이 오면 바로 쉼터에서 15분 쉬어 가세요."
    if rc:
        summary += f" 휴식은 {rc}번 했어요."
    return {"success": True, "report": {**stats, "name": f"{_driver_name(user.get('name'))} 기사님".strip(),
            "started": started.strftime("%H:%M") if started else "", "ended": now.strftime("%H:%M"),
            "summary": summary, "advice": advice, "is_real": False}}


@app.post("/drive/rest")
def drive_rest(user: dict = Depends(current_user)):
    st = state_of(user["id"])
    if st["rest_started"] is None:
        st["rest_started"] = time.time()
        open_events = [e for e in EVENTS if e["user_id"] == user["id"] and e["stage"] == 2 and e["status"] in ("미확인", "확인")]
        st["rest_event_id"] = open_events[-1]["id"] if open_events else None
    # 이미 쉬는 중이면 시작 시각은 그대로, 남은 시간만 (앱을 껐다 켜고 휴식 화면을 이어 열어도 처음부터 다시 시작하지 않게)
    left = max(1, int(round(REST_SEC - (time.time() - st["rest_started"]))))
    return {"success": True, "message": "15분 쉬고 출발하세요", "rest_sec": left, "started": _now_text()}


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
    if reason == "half":  # 반쯤 감은 눈 확인 (11/10) — 모의 서버는 판정하지 않고 언제나 '확정 아님' (조용히, 사진은 안 남김)
        stage = refresh_stage(st)
        return {"success": True, "face_found": photo is not None, "ear": None, "eye_closed_prob": None, "eye_open_prob": None,
                "method": "ear", "perclos": None, "ear_threshold": None, "is_sleep": False, "reason": "", "stage": stage,
                "status": STAGE_LABELS[stage], "summary": "", "guidance": "", "driver_voice": "",
                "sleep_count_10min": len(recent_sleeps(st)), "voice_quiz": None, "regulations": [], "event_id": None}
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

    # ②-1 (11/12 팀장) 예비 경고 — 운행 중 첫 졸음이고 지금 0단계면 단계를 올리지 않고 알림만 (횟수에 안 셈, 퀴즈 없음, 기록은 남김)
    fs = forced_stage()
    if PRE_WARN_ON and not fs and not st.get("pre_warned", True) and refresh_stage(st) == 0:  # 11/15 기본 꺼짐 (진짜 서버와 같게)
        st["pre_warned"] = True
        voice = "졸음이 느껴지면 창문을 열고 환기해 주세요. 다시 졸면 주의 단계로 경고해요."
        event = add_event(user["id"], 0, "pre_warning", {"situation": "운행 중 첫 졸음 — 예비 경고", "trigger": reason,
                          "eye": {"closed_sec": closed, "perclos": perclos_v, "eye_open_prob": open_prob, "ear": ear, "photo": photo is not None},
                          "driving_quiz": [], "rest": None},
                          summary="운행 중 첫 졸음이라 예비 경고만 했습니다.", guidance="창문을 열고 환기해 주세요.", ear=ear,
                          eye_closed_prob=None if open_prob is None else round(1 - open_prob, 3), method=base["method"], perclos=perclos_v,
                          photo_path=None, lat=lat, lng=lng)
        return {**base, "is_sleep": False, "pre_warning": True, "reason": "pre_warning", "stage": 0, "status": STAGE_LABELS[0],
                "summary": "", "guidance": "", "driver_voice": voice, "sleep_count_10min": len(recent_sleeps(st)), "voice_quiz": None,
                "regulations": [], "event_id": event["id"]}

    # ③ 졸음 1회 기록 → 규칙 단계 (시나리오 stageN 이면 그 단계로 고정)
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

    # ⑧ 음성 퀴즈 1문제 — 2단계에 들어갈 때마다 (11/18 팀장: 2분 간격 뺌, 2단계에서 또 졸면 바로 3단계라 연달아 나오지 않음)
    voice_quiz = None
    if stage == 2:  # (11/15) 퀴즈는 2단계에서만 (3단계는 [깨어 있어요])
        voice_quiz = make_quiz(user["id"], event_id=event["id"])
        st["last_quiz_at"] = time.time()
        st["quiz_fail"] = 0

    return {**base, "is_sleep": True, "reason": reason, "stage": stage, "status": STAGE_LABELS[stage], "summary": ai["summary"],
            "guidance": ai["guidance"], "driver_voice": f"{_driver_name(user.get('name')) or '기사'}님, {ai['driver_voice']}",
            "sleep_count_10min": count, "voice_quiz": voice_quiz,
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
        return {**result, "message": {2: "확인했어요. 쉼터까지 조심히 가세요.", 3: "확인했어요. 안전한 곳에 정차해 주세요."}.get(stage, "확인했어요. 안전 운행하세요.")}

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
            "message": "응답이 없어 관리자에게 알렸어요. 안전한 곳에 정차해 주세요."}


# ═══════════════════════════════════════════════════════════════
# events — 내 경고 목록 · 처리 상태 변경
# ═══════════════════════════════════════════════════════════════
@app.get("/events/my")
def events_my(user: dict = Depends(current_user)):
    mine = [e for e in EVENTS if e["user_id"] == user["id"]]
    return [event_out(e) for e in sorted(mine, key=lambda e: e["id"], reverse=True)]


@app.get("/events/{event_id}/photo")
def event_photo(event_id: int, user: dict = Depends(current_user)):
    """진짜 서버 routers/event.py event_photo 와 같음: 그 경고의 기사 본인 또는 관리자만, 아니면 똑같이 404."""
    event = next((e for e in EVENTS if e["id"] == event_id), None)
    if not event or not event["photo_path"] or (user["role"] != "admin" and event["user_id"] != user["id"]):
        raise HTTPException(status_code=404, detail="사진이 없습니다")
    path = os.path.join(EVENT_DIR, os.path.basename(event["photo_path"]))
    if not os.path.isfile(path):
        raise HTTPException(status_code=404, detail="사진이 없습니다")
    return FileResponse(path, headers={"Cache-Control": "private, no-store"})


@app.patch("/events/{event_id}/status")
def event_status(event_id: int, body: StatusUpdate, admin: dict = Depends(require_admin)):
    event = next((e for e in EVENTS if e["id"] == event_id), None)
    if not event:
        raise HTTPException(status_code=404, detail="없는 경고입니다")
    if body.status == "확인" and event["status"] != "미확인":  # 진짜 서버와 같음: '확인'(열어 봄)은 미확인일 때만
        return {"success": True, "id": event_id, "status": event["status"], "stage_reset": False}
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
        st = STATES.get(u["id"]) or {}
        last = st.get("last_ping")
        driving = bool(last) and not st.get("ended") and (bool(st.get("demo_driving")) or time.time() - last <= 120)   # 진짜 서버와 같음: 마지막 ping 2분 안
        out.append({**u, "event_count": len(mine), "last_event_at": max((e["created_at"] for e in mine), default=None),
                    "driving": driving, "drive_min": drive_min_of(st) if driving else 0})
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
# chat — 규정 도우미 (knowledge/*.txt 진짜 규정 원문)
#   - .env 에 GEMINI_API_KEY 가 있으면 진짜 chat_service (RAG + Gemini 답변)
#   - 없으면 knowledge/*.txt 를 같은 방식(rag_service 의 읽기 · 자르기)으로 읽어, 글자 겹침으로 질문과 가까운 규정 원문만 보여 준다
#     (AI 답변은 없음 → 앱에 "AI 답변 아님 — 규정 원문"으로 표시). 키 없이도 돌아야 하는 가짜 버전 규칙을 지킴
# ═══════════════════════════════════════════════════════════════
import math
from collections import Counter

_KB = {"chunks": None, "df": None}


def _grams(text: str) -> set:
    t = re.sub(r"[^0-9A-Za-z가-힣]", "", text)
    return {t[i:i + 2] for i in range(len(t) - 1)}


def _load_knowledge():
    """knowledge/*.txt → 호 단위 조각 (진짜 서버와 같은 rag_service 읽기 · 자르기, 외부 호출 없음). 한 번만 읽는다."""
    if _KB["chunks"] is None:
        try:
            from services import rag_service
            chunks = [c["metadata"] for c in rag_service._chunk(rag_service._read_docs())]
        except Exception as e:
            print(f"[mock chat] knowledge 읽기 실패 → 고정 규정만 사용: {type(e).__name__}: {e}")
            chunks = []
        df = Counter()
        for m in chunks:
            m["_grams"] = _grams(m["title"] + " " + m["content"])
            df.update(m["_grams"])
        _KB["chunks"], _KB["df"] = chunks, df
    return _KB["chunks"], _KB["df"]


def _real_ai_available() -> bool:
    try:
        from dotenv import load_dotenv
        load_dotenv(os.path.join(BASE_DIR, ".env"), override=True)   # 서버를 켠 뒤에 .env 에 키를 넣어도 읽도록 (빈 값으로 먼저 읽혀 있을 수 있음)
    except Exception:
        pass
    return len(os.getenv("GEMINI_API_KEY", "")) > 10


def search_knowledge(query: str, k: int = 4):
    """질문과 글자(두 글자씩)가 많이 겹치는 규정 조각 k개. 같은 문서가 k 를 다 채우지 않게 문서당 2개까지."""
    chunks, df = _load_knowledge()
    q = _grams(query)
    if not chunks or not q:
        return []
    n = len(chunks)
    scored = []
    for m in chunks:
        common = q & m["_grams"]
        if not common:
            continue
        score = sum(math.log(1 + n / df[g]) for g in common) / (len(m["_grams"]) ** 0.3)
        scored.append((score, m))
    scored.sort(key=lambda x: -x[0])
    out, per_file = [], Counter()
    for _, m in scored:
        if per_file[m["file"]] >= 2:
            continue
        per_file[m["file"]] += 1
        out.append({"title": m["title"], "source": m["source"], "content": m["content"], "is_real": True})
        if len(out) == k:
            break
    return out


@app.get("/chat/hello")
def chat_hello():
    if _real_ai_available():
        try:
            from services import chat_service
            return {"message": chat_service.hello()}
        except Exception:
            pass
    return {"message": "안녕하세요, 졸음 가드 규정 도우미예요. 졸음운전 · 연속 운전 휴게시간 규정을 물어보세요. (규정 원문 검색)"}


@app.post("/chat")
def chat(body: ChatRequest, user: dict = Depends(current_user)):
    if _real_ai_available():
        try:
            from services import chat_service
            return {"success": True, **chat_service.answer(body.message, body.history or [])}
        except Exception as e:
            print(f"[mock chat] 진짜 chat_service 실패 → 규정 원문 검색으로: {type(e).__name__}: {e}")
    found = search_knowledge(body.message)
    if not found:
        return {"success": True, "is_real": False, "sources": [],
                "answer": "질문과 관련된 규정을 찾지 못했어요. 졸음운전 · 휴게시간 · 휴대전화 사용 같은 낱말로 물어봐 주세요."}
    return {"success": True, "is_real": False, "sources": found,
            "answer": f"AI 답변 없이, 질문과 가장 가까운 규정 원문 {len(found)}건을 보여 드려요. (아래 규정을 눌러 원문을 확인하세요)"}


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
    return {"scenario": SCENARIO["name"], "timing": {"window_sec": WINDOW_SEC, "rest_sec": REST_SEC},
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
#   /admin/users 한 줄     {id · email · name · role · phone · vehicle_no · event_count · last_event_at · driving · drive_min}  (phone · vehicle_no 없으면 null)
#   PATCH /users/me        {phone?, vehicle_no?} → 내 정보 (빠진 칸은 그대로, '' 면 지움, 형식이 틀리면 422)
#   PATCH 요청/응답        {status} → {success, id, status, stage_reset}     status: 미확인 · 확인 · 조치완료 · 휴식완료 (아니면 422)
#   관리자 전용            PATCH /events/{id}/status · /admin/*  — role 이 admin 이 아니면 403 (mock 은 이메일이 admin 으로 시작하면 admin)
#   /chat 응답             {success, answer, sources}
#   /quiz/answer 응답      {success, passed, next_quiz, stage_up, stage, status, message}  (기획안 9-6)
# ═══════════════════════════════════════════════════════════════
if __name__ == "__main__":
    import uvicorn

    uvicorn.run("mock_server:app", host="0.0.0.0", port=8000, reload=True)
