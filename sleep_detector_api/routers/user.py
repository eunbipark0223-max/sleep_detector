# ═══════════════════════════════════════════════════════════════
# routers/user.py — 회원가입 · 로그인 · 구글 로그인 · 내 정보
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/routers/user.py (🟢 그대로 복사 + 이름만 맞춤)
#
# [이 파일이 하는 일]
#   - POST /users/signup {email, password, name, phone?, vehicle_no?, privacy_agreed?} · /users/login · /users/google  ·  GET /users/me
#     (회원가입 화면이 전화번호 · 차량번호를 같이 보냄. privacy_agreed=false 면 422. 동의 여부는 DB 칸을 늘리지 않아 저장하지 않음)
#   - 프로필 사진 POST · GET · DELETE /users/me/photo (수업 그대로, profile_screen)
#   - PATCH /users/me  {name?, phone?, vehicle_no?} — 기사 연락용 전화번호 · 차량번호 (profile_screen 에서 입력, 관리자 웹 연락처에 보임) · 이름은 관리자 설정 화면
#   - PUT /users/me/password {current_password, new_password} — 비밀번호 변경 (관리자 설정 화면, 가입과 같은 규칙. 구글 계정은 400)
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
import uuid

from fastapi import (
    APIRouter, status, HTTPException, Depends,
    UploadFile, File,
)
from fastapi.responses import FileResponse
from sqlalchemy import select
from sqlalchemy.orm import Session

import config
from schema.request  import SignupRequest, LoginRequest, GoogleLoginRequest, ProfileUpdate, PasswordChange
from schema.response import UserResponse, LoginResponse
from database.db_connection import get_session
from models.models import User
from auth.password import hash_password, verify_password
from auth.jwt      import create_access_token, get_current_user

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
            detail="이미 사용중인 이메일입니다",
        )

    hashed_password = hash_password(body.password)

    user = User(
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
            detail="이메일 또는 비밀번호가 올바르지 않습니다",
        )

    if not verify_password(body.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="이메일 또는 비밀번호가 올바르지 않습니다",
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
