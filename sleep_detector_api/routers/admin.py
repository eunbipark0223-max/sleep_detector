# ═══════════════════════════════════════════════════════════════
# routers/admin.py — 관리자 웹용 API
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0 (통계는 P2)
# 수업 원본: road_hazard_api/routers/admin.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - GET /admin/events — 졸음 경고 목록 (사진 · 위치 · 단계 · 보고서 · 상태)
#   - GET /admin/users — 기사 목록 (+ 전화번호 · 차량번호). /admin/events 한 줄에도 user_phone · user_vehicle_no 가 붙음 (연락 창)
#     전화번호는 개인정보 → 관리자 API 에서만 내려보냄 (기사용 /events/my 에는 없음)
#   - POST /admin/users — 관리자가 기사 계정 추가 {name, email, phone, vehicle_no?, privacy_agreed} (11/09)
#     → 임시 비밀번호를 서버가 만들어 응답에 한 번만 실어 줌 (DB 에는 해시만). 이미 있는 이메일이면 409
#   - GET /admin/stats/* — (P2) 단계별 · 시간대별 통계
#
# [주의]
#   - get_road_address (카카오 주소 변환) 는 그대로 유지
#
# [연결 약속 — 다른 사람 파일의 이름. 다르면 아래 import 한 줄만 고친다]
#   - database.orm.get_db · auth.jwt.get_current_user (수업 그대로 복사하는 파일)
#   - models.models.User(id · email · name · role) · SleepEvent(기획안 칸 그대로)
#   - require_admin 은 이 파일에 둠 (event.py 도 여기서 가져다 씀)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import os
from functools import lru_cache
from typing import Optional

import requests
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from auth.jwt import get_current_user
from auth.password import hash_password
from database.orm import get_db
from models.models import SleepEvent, User
from schema.request import AdminDriverCreate, make_temp_password
from schema.response import (
    STAGE_LABELS,
    AdminDriverCreated,
    AdminEventResponse,
    AdminUserResponse,
    HourStat,
    SleepEventResponse,
    StageStat,
)

load_dotenv()
KAKAO_API_KEY = os.getenv("KAKAO_API_KEY", "")
KAKAO_ADDRESS_URL = "https://dapi.kakao.com/v2/local/geo/coord2address.json"

router = APIRouter(prefix="/admin", tags=["admin"])


def require_admin(user: User = Depends(get_current_user)) -> User:
    """관리자만 통과 (role 값 user / admin 은 수업 그대로)."""
    if user.role != "admin":
        raise HTTPException(status_code=403, detail="관리자만 사용할 수 있습니다")
    return user


@lru_cache(maxsize=512)
def _address_cached(lat: float, lng: float) -> str:
    resp = requests.get(
        KAKAO_ADDRESS_URL,
        params={"x": lng, "y": lat},
        headers={"Authorization": f"KakaoAK {KAKAO_API_KEY}"},
        timeout=3,
    )
    resp.raise_for_status()
    docs = resp.json().get("documents", [])
    if not docs:
        return ""
    road = docs[0].get("road_address") or docs[0].get("address") or {}
    return road.get("address_name", "")


def get_road_address(lat: Optional[float], lng: Optional[float]) -> str:
    """위도 · 경도 → 도로명 주소 (카카오). 키가 없거나 실패하면 빈 값 — 관리자 웹은 좌표만 보여 주면 됨."""
    if lat is None or lng is None or not KAKAO_API_KEY:
        return ""
    try:
        return _address_cached(round(lat, 4), round(lng, 4))  # 소수 4자리(약 10m)로 묶어 같은 곳은 한 번만 부름
    except (requests.RequestException, ValueError):
        return ""


def _admin_row(event: SleepEvent, user: Optional[User]) -> AdminEventResponse:
    row = AdminEventResponse.from_event(event)
    row.user_name = user.name if user else ""
    row.user_email = user.email if user else ""
    row.user_phone = (user.phone or "") if user else ""
    row.user_vehicle_no = (user.vehicle_no or "") if user else ""
    row.address = get_road_address(event.latitude, event.longitude)
    row.urgent = event.stage == 3 or event.reason == "no_response"  # 빨간 줄
    return row


@router.get("/events", response_model=list[AdminEventResponse])
def admin_events(
    stage: Optional[int] = None,
    status: Optional[str] = None,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    stmt = select(SleepEvent, User).outerjoin(User, User.id == SleepEvent.user_id)
    if stage is not None:
        stmt = stmt.where(SleepEvent.stage == stage)
    if status:
        stmt = stmt.where(SleepEvent.status == status)
    rows = db.execute(stmt.order_by(SleepEvent.id.desc())).all()
    return [_admin_row(event, user) for event, user in rows]


@router.get("/users", response_model=list[AdminUserResponse])
def admin_users(db: Session = Depends(get_db), _admin: User = Depends(require_admin)):
    counts = {
        user_id: (count, last)
        for user_id, count, last in db.execute(
            select(SleepEvent.user_id, func.count(SleepEvent.id), func.max(SleepEvent.created_at)).group_by(SleepEvent.user_id)
        ).all()
    }
    out = []
    for user in db.execute(select(User).order_by(User.id)).scalars().all():
        count, last = counts.get(user.id, (0, None))
        out.append(AdminUserResponse(id=user.id, email=user.email, name=user.name, role=user.role, phone=user.phone, vehicle_no=user.vehicle_no,
                                     event_count=count, last_event_at=last))
    return out


@router.post("/users", status_code=201, response_model=AdminDriverCreated)
def create_driver(body: AdminDriverCreate, db: Session = Depends(get_db), _admin: User = Depends(require_admin)):
    """관리자가 기사 계정을 만든다 (앱 회원가입과 같은 칸 · 규칙). 기사는 이메일 + 임시 비밀번호로 앱에 로그인."""
    email = str(body.email)
    if db.scalar(select(User).where(User.email == email)):
        raise HTTPException(status_code=409, detail="이미 가입된 이메일이에요")
    temp_password = make_temp_password()
    user = User(email=email, hashed_password=hash_password(temp_password), name=body.name, role="user", provider="email",
                phone=body.phone, vehicle_no=body.vehicle_no)
    db.add(user)
    db.commit()
    db.refresh(user)
    return AdminDriverCreated(id=user.id, email=user.email, name=user.name, role=user.role, phone=user.phone, vehicle_no=user.vehicle_no,
                              event_count=0, last_event_at=None, temp_password=temp_password)


# ── 통계 (P2) ─────────────────────────────────────────────────
@router.get("/stats/stage", response_model=list[StageStat])
def stats_stage(db: Session = Depends(get_db), _admin: User = Depends(require_admin)):
    counts = dict(db.execute(select(SleepEvent.stage, func.count(SleepEvent.id)).group_by(SleepEvent.stage)).all())
    return [StageStat(stage=s, label=STAGE_LABELS[s], count=counts.get(s, 0)) for s in (1, 2, 3)]


@router.get("/stats/hourly", response_model=list[HourStat])
def stats_hourly(db: Session = Depends(get_db), _admin: User = Depends(require_admin)):
    counts = [0] * 24
    for (created_at,) in db.execute(select(SleepEvent.created_at)).all():  # 시각 뽑기는 DB 마다 달라서 파이썬에서 셈
        counts[created_at.hour] += 1
    return [HourStat(hour=h, count=c) for h, c in enumerate(counts)]
