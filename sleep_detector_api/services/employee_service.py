# ═══════════════════════════════════════════════════════════════
# services/employee_service.py — 사번 확인 · 전화번호 인증 (시연용) (11/17 C)
# ═══════════════════════════════════════════════════════════════
# [이 파일이 하는 일]
#   - ensure_schema(engine)  : 이미 만들어진 DB 의 users 표에 emp_no 칸이 없으면 붙이고,
#                              employees 표가 비어 있으면 시연용 사번(DEMO_EMPLOYEES)을 넣는다
#   - check_employee(...)    : 사번이 회사 명단에 있고 아직 가입 안 했는지
#   - send_code(phone)       : 6자리 인증번호를 만들어 5분 동안 기억 (진짜 문자는 안 보냄 → 번호를 응답으로 돌려줌)
#   - send_email_code / verify_email_code / use_email_token : 이메일도 같은 방식 (진짜 메일은 안 보냄)
#   - verify_code(phone,code): 맞으면 가입 때 낼 인증 표(token, 30분) 를 준다
#   - use_phone_token(...)   : 가입할 때 그 전화번호로 인증한 표인지 확인하고 한 번 쓰면 지운다
#
# [주의] 전화번호 인증은 시연용 — 문자 서비스 없이 인증번호를 앱 화면에 보여 준다.
#        진짜 문자를 보내려면 send_code 안에서 문자 서비스(예: 네이버 클라우드 SENS)를 부르면 된다.
#        인증 기록은 메모리에만 있어서 서버를 껐다 켜면 다시 인증해야 한다.
# ═══════════════════════════════════════════════════════════════
import random
import re
import secrets
import threading
import time

# DB 관련 import 는 함수 안에서 (mock_server 가 전화 인증만 빌려 쓸 때 DB 없이도 읽히게)

# 시연용 사번 (employees 표가 비어 있을 때만 들어감). 이름이 None 이면 이름은 확인하지 않는다
DEMO_EMPLOYEES = [(f"2026{n:04d}", None) for n in range(1, 21)]  # 20260001 ~ 20260020

CODE_TTL_SEC = 5 * 60      # 인증번호 유효 시간
TOKEN_TTL_SEC = 30 * 60    # 인증 뒤 가입까지 기다려 주는 시간
MAX_TRIES = 5              # 인증번호 틀려도 되는 횟수

_lock = threading.Lock()
_codes: dict[str, tuple[str, float, int]] = {}   # 전화번호(숫자만) → (인증번호, 만료 시각, 틀린 횟수)
_tokens: dict[str, tuple[str, float]] = {}       # token → (전화번호 숫자만, 만료 시각)


def normalize_emp_no(value: str) -> str:
    return re.sub(r"\s", "", value or "").upper()


def _digits(phone: str) -> str:
    return re.sub(r"\D", "", phone or "")


# ── DB 준비 ─────────────────────────────────────────────────────
def ensure_schema(engine) -> None:
    """users.emp_no 칸이 없으면 붙이고, employees 표가 비었으면 시연용 사번을 넣는다."""
    from sqlalchemy import inspect, select, text
    from sqlalchemy.orm import Session
    from models.models import Employee
    cols = {c["name"] for c in inspect(engine).get_columns("users")}
    if "emp_no" not in cols:
        with engine.begin() as conn:
            conn.execute(text("ALTER TABLE users ADD COLUMN emp_no VARCHAR(20) NULL"))
        print("✅ users 표에 emp_no(사번) 칸 추가")
    with Session(engine) as db:
        if db.scalar(select(Employee).limit(1)) is None:
            db.add_all([Employee(emp_no=no, name=name) for no, name in DEMO_EMPLOYEES])
            db.commit()
            print(f"✅ 시연용 사번 {len(DEMO_EMPLOYEES)}개 등록 ({DEMO_EMPLOYEES[0][0]} ~ {DEMO_EMPLOYEES[-1][0]})")


# ── 사번 ────────────────────────────────────────────────────────
class EmployeeError(Exception):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status
        self.message = message


def check_employee(db, emp_no: str, name: str | None = None):
    """명단에 있고 · (이름이 등록돼 있으면) 이름이 같고 · 아직 가입 안 한 사번이면 Employee. 아니면 EmployeeError."""
    from sqlalchemy import select
    from models.models import Employee, User
    no = normalize_emp_no(emp_no)
    emp = db.get(Employee, no) if no else None
    if emp is None:
        raise EmployeeError(404, "등록되지 않은 사번이에요")
    if emp.name and name is not None and emp.name.strip() != name.strip():
        raise EmployeeError(400, "사번과 이름이 맞지 않아요")
    if db.scalar(select(User).where(User.emp_no == no)) is not None:
        raise EmployeeError(409, "이미 가입된 사번이에요")
    return emp


# ── 전화번호 · 이메일 인증 (시연용) ─────────────────────────────
#   같은 저장소를 쓰고 열쇠만 'phone:01012345678' · 'email:a@b.com' 으로 나눈다
def _phone_key(phone: str) -> str:
    return "phone:" + _digits(phone)


def _email_key(email: str) -> str:
    return "email:" + (email or "").strip().lower()


def _send(key: str) -> str:
    code = f"{random.randint(0, 999999):06d}"
    with _lock:
        _codes[key] = (code, time.time() + CODE_TTL_SEC, 0)
    return code


def _verify(key: str, code: str) -> str:
    """맞으면 가입용 token. 틀리면 ValueError(메시지)."""
    now = time.time()
    with _lock:
        saved = _codes.get(key)
        if saved is None or saved[1] < now:
            _codes.pop(key, None)
            raise ValueError("인증번호가 만료됐어요. 다시 받아 주세요")
        right, exp, tries = saved
        if (code or "").strip() != right:
            tries += 1
            if tries >= MAX_TRIES:
                _codes.pop(key, None)
                raise ValueError("인증번호를 여러 번 틀렸어요. 다시 받아 주세요")
            _codes[key] = (right, exp, tries)
            raise ValueError("인증번호가 맞지 않아요")
        _codes.pop(key, None)
        token = secrets.token_urlsafe(16)
        _tokens[token] = (key, now + TOKEN_TTL_SEC)
        return token


def _use(key: str, token: str | None) -> bool:
    """가입할 때: 이 값으로 인증받은 표면 True (한 번 쓰면 지움)."""
    if not token:
        return False
    with _lock:
        saved = _tokens.get(token)
        if saved is None or saved[1] < time.time() or saved[0] != key:
            return False
        _tokens.pop(token, None)
        return True


def send_code(phone: str) -> str:
    return _send(_phone_key(phone))


def verify_code(phone: str, code: str) -> str:
    return _verify(_phone_key(phone), code)


def use_phone_token(phone: str, token: str | None) -> bool:
    return _use(_phone_key(phone), token)


# (11/17 C) 이메일 인증 — 시연용: 메일을 보내지 않고 인증번호를 응답으로 돌려준다
def send_email_code(email: str) -> str:
    return _send(_email_key(email))


def verify_email_code(email: str, code: str) -> str:
    return _verify(_email_key(email), code)


def use_email_token(email: str, token: str | None) -> bool:
    return _use(_email_key(email), token)
