# ═══════════════════════════════════════════════════════════════
# auth/jwt.py — JWT 토큰 만들기 · 검사 (로그인 증명)
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/auth/jwt.py (🟢 그대로 복사 + get_current_user 추가)
#
# [이 파일이 하는 일]
#   - create_access_token(user_id, role) · decode_access_token(token) — 수업 그대로
#   - 🆕 get_current_user — 라우터에서 user: User = Depends(get_current_user) 한 줄로 로그인한 사람을 받는다
#       (토큰 없음 → 401, 토큰 이상 · 만료 → 401, 지워진 사용자 → 404)
#       event.py · admin.py (D) · detect.py · quiz.py (팀장) 가 씀
#
# [주의]
#   - 토큰 유효 시간은 config.TOKEN_EXPIRE_MIN (12시간) — 수업 60분이면 운행 중에 끊김
#   - SECRET_KEY 는 .env (비어 있으면 기본 문자열 — 팀원 PC 끼리는 달라도 됨, 배포 때는 꼭 넣기)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

import jwt
from datetime import datetime, timedelta, timezone
from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from sqlalchemy.orm import Session
from dotenv import load_dotenv
import os

import config
from database.db_connection import get_session
from models.models import User

load_dotenv()

SECRET_KEY = os.getenv("SECRET_KEY") or "sleep-detector-secret-key"
ALGORITHM  = "HS256"

bearer = HTTPBearer(auto_error=False)

def create_access_token(user_id: int, role: str, expires_minutes: int = config.TOKEN_EXPIRE_MIN) -> str:

    payload = {
        "user_id": user_id,
        "role"   : role,

        "exp"    : datetime.now(timezone.utc) + timedelta(minutes=expires_minutes),
    }

    return jwt.encode(payload, SECRET_KEY, algorithm=ALGORITHM)

def decode_access_token(token: str) -> dict:
    try:
        payload = jwt.decode(token, SECRET_KEY, algorithms=[ALGORITHM])

        return {
            "user_id": payload["user_id"],
            "role"   : payload.get("role", "user"),
        }

    except jwt.ExpiredSignatureError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Token expired",
        )

    except jwt.InvalidTokenError:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token",
        )

# 🆕 수업 라우터마다 반복하던 "토큰 꺼내기 → 풀기 → 사용자 찾기" 를 한 함수로
def get_current_user(
    authorization: HTTPAuthorizationCredentials | None = Depends(bearer),
    session: Session = Depends(get_session),
) -> User:
    if not authorization:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="로그인이 필요합니다",
        )
    token_data = decode_access_token(authorization.credentials)

    user = session.get(User, token_data["user_id"])
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="사용자를 찾을 수 없습니다. 다시 로그인해주세요",
        )
    return user
