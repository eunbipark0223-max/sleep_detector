# ═══════════════════════════════════════════════════════════════
# routers/user.py — 회원가입 · 로그인 · 구글 로그인 · 내 정보
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/routers/user.py (🟢 그대로 복사 + 이름만 맞춤)
#
# [이 파일이 하는 일]
#   - POST /users/signup {email, password, name, phone?, vehicle_no?, privacy_agreed?} · /users/login · /users/google  ·  GET /users/me
#     · /users/google {email, name, firebase_uid, id_token?} — 관리자 계정은 id_token 검증 필수 (services/firebase_verify.py) · GET /users/google/config = 관리자 웹용 Firebase 웹 설정
#     (회원가입 화면이 전화번호 · 차량번호를 같이 보냄. privacy_agreed=false 면 422. 동의 여부는 DB 칸을 늘리지 않아 저장하지 않음)
#   - 프로필 사진 POST · GET · DELETE /users/me/photo (수업 그대로, profile_screen)
#   - PATCH /users/me  {name?, phone?, vehicle_no?} — 기사 연락용 전화번호 · 차량번호 (profile_screen 에서 입력, 관리자 웹 연락처에 보임) · 이름은 관리자 설정 화면
#   - PUT /users/me/password {current_password, new_password} — 비밀번호 변경 (관리자 설정 화면, 가입과 같은 규칙. 구글 계정은 400)
#   - (11/19) POST /users/me/email/request {new_email, current_password} · /users/me/email/confirm {new_email, code}
#       이메일 변경 (관리자 웹 '내 정보'). 새 이메일로 6자리 인증번호(10분) → 확인하면 users.email 변경. 구글 계정은 400
#   - (11/17 C) 앱 회원가입 = 사번 확인 → 전화번호 인증 → 가입
#       POST /users/employee/check {emp_no, name?}   — 회사 명단(employees 표)에 있고 아직 가입 안 한 사번인지
#       POST /users/phone/send {phone}               — 인증번호 (시연용: 문자 대신 응답 demo_code)
#       POST /users/phone/verify {phone, code}       — 맞으면 phone_token → /users/signup 에 emp_no 와 같이 보냄
#       POST /users/email/send · /users/email/verify — 이메일도 같은 방식 (email_token)
#         (11/19) .env 에 구글 SMTP(SMTP_USER · SMTP_PASSWORD)가 있으면 /users/email/send 가 진짜 메일로 보냄 (services/mail_service.py) — 없으면 demo_code 시연용
#
# [수업에서 바꾼 것]
#   - 요청 · 응답 이름: schema 의 SignupRequest · LoginRequest · GoogleLoginRequest · UserResponse · LoginResponse (D)
#   - 로그인 응답: {access_token} → {success, access_token, token_type, user} (mock_server 와 같은 모양, 앱은 access_token 만 읽어도 됨)
#   - 토큰 검사는 auth.jwt.get_current_user 한 줄로
#   - 토큰 유효 시간 config.TOKEN_EXPIRE_MIN (12시간)
#   - 환영 메일(5초 sleep 연습 코드) 삭제
#
# [관리자 계정 만들기] 앱 · 웹에서 가입한 뒤 MySQL 에서:
#   UPDATE users SET role = 'admin' WHERE email = '관리자 이메일';
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

import os
import secrets
import threading
import time
import uuid

from fastapi import (
    APIRouter, status, HTTPException, Depends,
    UploadFile, File,
)
from fastapi.responses import FileResponse
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import config
from schema.request  import (
    SignupRequest, LoginRequest, GoogleLoginRequest, ProfileUpdate, PasswordChange,
    EmployeeCheckRequest, PhoneSendRequest, PhoneVerifyRequest, EmailSendRequest, EmailVerifyRequest,
    EmailChangeRequest, EmailChangeConfirm,
)
from services import employee_service, mail_service
from schema.response import UserResponse, LoginResponse
from database.db_connection import get_session
from models.models import User
from auth.password import hash_password, verify_password
from auth.jwt      import create_access_token, get_current_user
from services import firebase_verify

router = APIRouter(tags=["User"])

PROFILE_DIR = os.path.join(config.BASE_DIR, "uploads", "profiles")
os.makedirs(PROFILE_DIR, exist_ok=True)

PROFILE_ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp", ".heic"}
PROFILE_MAX_BYTES    = 5 * 1024 * 1024


def _login_response(user: User) -> LoginResponse:
    access_token = create_access_token(user_id=user.id, role=user.role)
    return LoginResponse(access_token=access_token, user=UserResponse.model_validate(user))


@router.post(
    "/users/signup",
    status_code=status.HTTP_201_CREATED,
    response_model=UserResponse,
)
def signup_user_handler(
    body   : SignupRequest,
    session: Session = Depends(get_session),
):

    stmt          = select(User).where(User.email == body.email)
    existing_user = session.scalar(stmt)

    if existing_user:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="이미 가입된 이메일이에요",
        )

    # (11/17 C) 사번으로 가입하는 앱: 사번이 명단에 있고 · 아직 안 쓰였고 · 전화번호를 인증했어야 한다
    emp_no = None
    if body.emp_no:
        try:
            emp = employee_service.check_employee(session, body.emp_no, body.name)
        except employee_service.EmployeeError as e:
            raise HTTPException(status_code=e.status, detail=e.message)
        if not employee_service.use_email_token(str(body.email), body.email_token):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="이메일 인증을 먼저 해 주세요")
        if not body.phone or not employee_service.use_phone_token(body.phone, body.phone_token):
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="전화번호 인증을 먼저 해 주세요")
        emp_no = emp.emp_no

    hashed_password = hash_password(body.password)

    user = User(
        emp_no         =emp_no,
        email          =str(body.email),
        hashed_password=hashed_password,
        name           =body.name,
        role           ="user",
        provider       ="email",
        phone          =body.phone or None,       # 앱 회원가입 화면에서 받은 값 (이미 형식 정리됨). 없으면 NULL
        vehicle_no     =body.vehicle_no or None,
    )
    session.add(user)
    session.commit()
    session.refresh(user)

    return user

@router.post("/users/employee/check", status_code=status.HTTP_200_OK)
def check_employee_handler(
    body   : EmployeeCheckRequest,
    session: Session = Depends(get_session),
):
    """(11/17 C) 회원가입 첫 단계 — 사번이 회사 명단에 있고 아직 가입 안 했는지. 200 {ok, emp_no, name}"""
    try:
        emp = employee_service.check_employee(session, body.emp_no, body.name)
    except employee_service.EmployeeError as e:
        raise HTTPException(status_code=e.status, detail=e.message)
    return {"ok": True, "emp_no": emp.emp_no, "name": emp.name}


@router.post("/users/phone/send", status_code=status.HTTP_200_OK)
def send_phone_code_handler(body: PhoneSendRequest):
    """(11/17 C) 전화번호 인증번호 받기 — 시연용: 문자를 보내지 않고 응답에 demo_code 로 번호를 준다 (5분 유효)"""
    code = employee_service.send_code(body.phone)
    return {"sent": True, "demo": True, "demo_code": code, "expires_sec": employee_service.CODE_TTL_SEC}


@router.post("/users/phone/verify", status_code=status.HTTP_200_OK)
def verify_phone_code_handler(body: PhoneVerifyRequest):
    """(11/17 C) 인증번호 확인 — 맞으면 가입 때 같이 보낼 phone_token (30분 유효)"""
    try:
        token = employee_service.verify_code(body.phone, body.code)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return {"verified": True, "phone": body.phone, "phone_token": token}


@router.post("/users/email/send", status_code=status.HTTP_200_OK)
def send_email_code_handler(body: EmailSendRequest):
    """이메일 인증번호 받기 (5분 유효).
    - .env 에 SMTP_USER · SMTP_PASSWORD 가 있으면 (11/19): 진짜 메일로만 보낸다. 번호는 응답에 절대 싣지 않음.
      같은 이메일 1분 간격 · 1시간 5번 · 서버 하루 100통을 넘으면 429 (Retry-After 초). 메일 서버 오류는 503.
    - 없으면 (11/17 C 시연용): 메일 없이 응답 demo_code 로 번호를 준다.
    """
    email = str(body.email)
    if not mail_service.is_enabled():
        code = employee_service.send_email_code(email)
        return {"sent": True, "demo": True, "demo_code": code, "expires_sec": employee_service.CODE_TTL_SEC}

    try:
        ticket = mail_service.reserve(email)
    except mail_service.MailRateLimited as e:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=e.message,
            headers={"Retry-After": str(e.retry_after)},
        )
    code = employee_service.send_email_code(email)
    try:
        mail_service.send_verification_code(email, code, employee_service.CODE_TTL_SEC // 60)
    except mail_service.MailError as e:
        mail_service.release(ticket)                  # 우리 쪽 문제로 사용자가 1분 기다리지 않게 횟수를 돌려 줌
        employee_service.discard_email_code(email)    # 받지도 못한 번호는 지움
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=e.message)
    return {"sent": True, "demo": False, "expires_sec": employee_service.CODE_TTL_SEC, "resend_after_sec": config.MAIL_COOLDOWN_SEC}


@router.post("/users/email/verify", status_code=status.HTTP_200_OK)
def verify_email_code_handler(body: EmailVerifyRequest):
    """(11/17 C) 이메일 인증번호 확인 — 맞으면 가입 때 같이 보낼 email_token (30분 유효)"""
    try:
        token = employee_service.verify_email_code(str(body.email), body.code)
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    return {"verified": True, "email": str(body.email), "email_token": token}


@router.post(
    "/users/login",
    status_code=status.HTTP_200_OK,
    response_model=LoginResponse,
)
def login_user_handler(
    body   : LoginRequest,
    session: Session = Depends(get_session),
):

    stmt = select(User).where(User.email == body.email)
    user = session.scalar(stmt)

    if not user or not user.hashed_password:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="이메일 또는 비밀번호가 올바르지 않아요",
        )

    if not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="이메일 또는 비밀번호가 올바르지 않아요",
        )

    return _login_response(user)

@router.post(
    "/users/google",
    status_code=status.HTTP_200_OK,
    response_model=LoginResponse,
)
def google_login_handler(
    body   : GoogleLoginRequest,
    session: Session = Depends(get_session),
):

    stmt = select(User).where(User.email == body.email)
    user = session.scalar(stmt)

    # (11/16) 이 요청은 앱이 보낸 이메일 · uid 를 그대로 믿는다 → 관리자 계정(또는 FIREBASE_VERIFY=true)은 구글이 서명한 id_token 을 확인해야 함
    if config.FIREBASE_VERIFY or (user is not None and user.role == "admin"):
        try:
            firebase_verify.verify_id_token(body.id_token or "", str(body.email), body.firebase_uid)
        except firebase_verify.FirebaseNotConfigured:
            raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                                detail="서버에 구글 로그인 설정(FIREBASE_PROJECT_ID)이 없어요")
        except firebase_verify.FirebaseVerifyError as e:
            print(f"[google] 토큰 검증 실패 {body.email}: {e}")
            raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="구글 인증을 확인할 수 없어요")

    if user is None:
        user = User(
            email          =str(body.email),
            hashed_password=None,
            name           =body.name,
            role           ="user",
            provider       ="google",
            firebase_uid   =body.firebase_uid,
        )
        session.add(user)
        session.commit()
        session.refresh(user)

    else:
        if user.provider != "google":
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="이미 이메일로 가입된 계정입니다. 이메일 로그인을 이용해주세요",
            )

        if not user.firebase_uid:
            user.firebase_uid = body.firebase_uid
            session.commit()

    return _login_response(user)

@router.get("/users/google/config")
def google_config_handler():
    """관리자 웹 로그인 화면이 구글 창을 띄우는 데 쓰는 Firebase 웹 설정 (공개 값). 서버 .env 에 없으면 enabled=false"""
    ready = bool(config.FIREBASE_PROJECT_ID and config.FIREBASE_API_KEY)
    return {
        "enabled"   : ready,
        "apiKey"    : config.FIREBASE_API_KEY if ready else "",
        "authDomain": f"{config.FIREBASE_PROJECT_ID}.firebaseapp.com" if ready else "",
        "projectId" : config.FIREBASE_PROJECT_ID if ready else "",
        "appId"     : config.FIREBASE_APP_ID if ready else "",
    }


def _me_dict(user: User) -> dict:
    return {
        "id"        : user.id,
        "email"     : user.email,
        "name"      : user.name,
        "role"      : user.role,
        "provider"  : user.provider,
        "photo_url" : user.photo_url,
        "phone"     : user.phone,
        "vehicle_no": user.vehicle_no,
        "created_at": user.created_at.isoformat() if user.created_at else None,
    }

@router.get("/users/me", status_code=status.HTTP_200_OK)
def get_me_handler(user: User = Depends(get_current_user)):
    return _me_dict(user)

@router.patch("/users/me", status_code=status.HTTP_200_OK)
def update_me_handler(
    body   : ProfileUpdate,
    session: Session = Depends(get_session),
    user   : User    = Depends(get_current_user),
):
    """내 이름 · 전화번호 · 차량번호 저장. 안 보낸 칸은 그대로, 전화 · 차량은 ''(빈 글자)면 지움. 형식이 틀리면 422(문구는 화면에 그대로 보여 줘도 됨)."""
    if "name" in body.model_fields_set and body.name is not None:
        user.name = body.name
    if "phone" in body.model_fields_set and body.phone is not None:
        user.phone = body.phone or None
    if "vehicle_no" in body.model_fields_set and body.vehicle_no is not None:
        user.vehicle_no = body.vehicle_no or None
    session.commit()
    return _me_dict(user)

@router.put("/users/me/password", status_code=status.HTTP_200_OK)
def change_my_password_handler(
    body   : PasswordChange,
    session: Session = Depends(get_session),
    user   : User    = Depends(get_current_user),
):
    """내 비밀번호 변경 (관리자 설정 화면). 지금 비밀번호가 맞아야 바뀜. 구글로 가입한 계정은 비밀번호가 없어서 거절."""
    if not user.hashed_password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="구글 계정은 비밀번호를 바꿀 수 없어요")
    if not verify_password(body.current_password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="지금 비밀번호가 맞지 않아요")
    user.hashed_password = hash_password(body.new_password)
    session.commit()
    return {"success": True}

# ── 이메일 변경 (11/19, 관리자 웹 '내 정보') ─────────────────────────────
#   이메일로 가입한 계정만. 새 이메일 + 지금 비밀번호 → 새 이메일로 6자리 인증번호(10분 · 5번까지) → 확인하면 users.email 이 바뀜
#   응답 모양은 모의 서버(mock_server.py)와 같음 → 관리자 웹 화면은 그대로
#   - SMTP 켜짐: 새 이메일로 진짜 메일 (횟수 제한은 가입 인증과 같은 mail_service.reserve). 번호는 응답에 싣지 않음
#   - SMTP 꺼짐(시연용): 응답 dev_code 로 번호를 줌 (화면이 '메일 대신 여기에' 로 보여 줌)
#   인증번호는 메모리에만 (서버를 다시 켜면 다시 받아야 함, DB 칸 추가 없음)
EMAIL_CHANGE_TTL_SEC = 10 * 60
EMAIL_CHANGE_MAX_TRIES = 5
_email_change_lock = threading.Lock()
_email_changes: dict[int, dict] = {}     # user_id → {email, code, expires, sent_at, tries}


def _email_owner_id(session: Session, email: str) -> int | None:
    return session.scalar(select(User.id).where(func.lower(User.email) == email.lower()))


def _check_email_account(user: User) -> None:
    if user.provider == "google" or not user.hashed_password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="구글 계정은 이메일을 바꿀 수 없어요")


@router.post("/users/me/email/request", status_code=status.HTTP_200_OK)
def request_email_change_handler(
    body   : EmailChangeRequest,
    session: Session = Depends(get_session),
    user   : User    = Depends(get_current_user),
):
    """이메일 변경 1단계 — 지금 비밀번호 확인 뒤 새 이메일로 인증번호. 200 {success, expires_in(초)} (+ 시연용이면 dev_code)"""
    _check_email_account(user)
    if not verify_password(body.current_password, user.hashed_password):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="지금 비밀번호가 맞지 않아요")
    new_email = str(body.new_email).strip()
    if new_email.lower() == (user.email or "").lower():
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="지금과 같은 이메일이에요")
    if _email_owner_id(session, new_email) not in (None, user.id):
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입된 이메일이에요")

    now = time.time()
    with _email_change_lock:                # 한 사람이 주소를 바꿔 가며 연타하지 못하게 (같은 주소 연타는 mail_service 가 막음)
        prev = _email_changes.get(user.id)
        if prev and now - prev["sent_at"] < config.MAIL_COOLDOWN_SEC:
            wait = int(prev["sent_at"] + config.MAIL_COOLDOWN_SEC - now) + 1
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                                detail=f"인증 메일을 방금 보냈어요. {wait}초 뒤에 다시 받아 주세요", headers={"Retry-After": str(wait)})

    ticket = None
    if mail_service.is_enabled():
        try:
            ticket = mail_service.reserve(new_email)
        except mail_service.MailRateLimited as e:
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS, detail=e.message,
                                headers={"Retry-After": str(e.retry_after)})

    code = f"{secrets.randbelow(1_000_000):06d}"
    with _email_change_lock:
        _email_changes[user.id] = {"email": new_email, "code": code, "expires": now + EMAIL_CHANGE_TTL_SEC, "sent_at": now, "tries": 0}

    if ticket is None:                      # 시연용 (SMTP 없음)
        return {"success": True, "expires_in": EMAIL_CHANGE_TTL_SEC, "dev_code": code}
    try:
        mail_service.send_verification_code(new_email, code, EMAIL_CHANGE_TTL_SEC // 60, title="이메일 변경 인증", where="관리자 웹")
    except mail_service.MailError as e:
        mail_service.release(ticket)
        with _email_change_lock:
            _email_changes.pop(user.id, None)
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail=e.message)
    return {"success": True, "expires_in": EMAIL_CHANGE_TTL_SEC}


@router.post("/users/me/email/confirm", status_code=status.HTTP_200_OK)
def confirm_email_change_handler(
    body   : EmailChangeConfirm,
    session: Session = Depends(get_session),
    user   : User    = Depends(get_current_user),
):
    """이메일 변경 2단계 — 인증번호가 맞으면 이메일을 바꾸고 바뀐 내 정보(GET /users/me 와 같은 모양)를 돌려준다"""
    _check_email_account(user)
    new_email = str(body.new_email).strip()
    with _email_change_lock:
        entry = _email_changes.get(user.id)
        if not entry or entry["email"].lower() != new_email.lower():
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="먼저 인증번호를 받아 주세요")
        if time.time() > entry["expires"]:
            _email_changes.pop(user.id, None)
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="인증번호가 만료됐어요. 다시 받아 주세요")
        if not secrets.compare_digest(body.code.strip(), entry["code"]):
            entry["tries"] += 1
            left = EMAIL_CHANGE_MAX_TRIES - entry["tries"]
            if left <= 0:
                _email_changes.pop(user.id, None)
                raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="인증번호가 맞지 않아요. 인증번호를 다시 받아 주세요")
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=f"인증번호가 맞지 않아요 (남은 횟수 {left}번)")
        _email_changes.pop(user.id, None)   # 맞았으면 한 번 쓰고 지움
        new_email = entry["email"]

    if _email_owner_id(session, new_email) not in (None, user.id):   # 받는 사이에 다른 사람이 그 주소로 가입한 경우
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입된 이메일이에요")
    user.email = new_email
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입된 이메일이에요")
    print(f"✅ [email-change] user {user.id} 이메일 변경 → {mail_service.mask_email(new_email)}")
    return _me_dict(user)


@router.post("/users/me/photo", status_code=status.HTTP_200_OK)
async def upload_my_photo_handler(
    file   : UploadFile = File(...),
    session: Session    = Depends(get_session),
    user   : User       = Depends(get_current_user),
):
    ext = os.path.splitext(file.filename or "photo.jpg")[1].lower() or ".jpg"
    if ext not in PROFILE_ALLOWED_EXTS:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"이미지 파일만 올릴 수 있습니다 ({', '.join(sorted(PROFILE_ALLOWED_EXTS))})",
        )

    content = await file.read()
    if not content:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="빈 파일입니다")
    if len(content) > PROFILE_MAX_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail=f"사진이 너무 큽니다 (최대 {PROFILE_MAX_BYTES // (1024*1024)}MB)",
        )

    new_name = f"u{user.id}_{uuid.uuid4().hex[:12]}{ext}"
    with open(os.path.join(PROFILE_DIR, new_name), "wb") as f:
        f.write(content)

    old_name = user.photo_url
    user.photo_url = new_name
    session.commit()

    if old_name:
        try:
            os.remove(os.path.join(PROFILE_DIR, old_name))
        except OSError:
            pass

    return {"success": True, "photo_url": new_name}

@router.get("/users/me/photo")
def get_my_photo_handler(user: User = Depends(get_current_user)):
    if not user.photo_url:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="프로필 사진이 없습니다")

    path = os.path.join(PROFILE_DIR, user.photo_url)
    if not os.path.exists(path):
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="사진 파일을 찾을 수 없습니다")

    return FileResponse(path)

@router.delete("/users/me/photo", status_code=status.HTTP_200_OK)
def delete_my_photo_handler(
    session: Session = Depends(get_session),
    user   : User    = Depends(get_current_user),
):
    old_name = user.photo_url
    user.photo_url = None
    session.commit()

    if old_name:
        try:
            os.remove(os.path.join(PROFILE_DIR, old_name))
        except OSError:
            pass

    return {"success": True}
