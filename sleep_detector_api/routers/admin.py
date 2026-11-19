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
#     기사 계정은 관리자가 만들지 않는다 — 기사가 앱 회원가입(POST /users/signup)으로 직접 가입하면 같은 DB 라서 이 목록에 나타남 (11/10)
#   - GET /admin/stats/* — (P2) 단계별 · 시간대별 통계
#   - (11/19) POST /admin/signup/check {employee_no} · POST /admin/signup {employee_no, name, email, password}
#       관리자 웹 '사번으로 가입하기' (static/admin_signup.html). 로그인 없이 부름. 인증된 사번 목록은 .env ADMIN_EMPLOYEE_NOS
#       (비어 있으면 503 — 관리자 가입 닫힘). 모의 서버와 같은 응답 · 문구라 화면은 그대로
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
import ipaddress
import os
import re
import threading
import time
from functools import lru_cache
from typing import Optional

import requests
from dotenv import load_dotenv
from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

import config
from auth.jwt import get_current_user
from auth.password import hash_password
from database.orm import get_db
from models.models import SleepEvent, User
from schema.request import AdminEmployeeCheck, AdminSignupRequest
from services import drive_timer
from schema.response import (
    STAGE_LABELS,
    AdminEventResponse,
    AdminUserResponse,
    HourStat,
    SleepEventResponse,
    StageStat,
)

load_dotenv()
DRIVING_PING_SEC = 120   # 마지막 ping 이 이 안이면 '주행 중' (앱은 30초마다 ping)
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
        age = drive_timer.last_ping_age(user.id)         # 운행 기록이 없거나 [운행 종료] 를 눌렀으면 None
        driving = age is not None and age <= DRIVING_PING_SEC
        out.append(AdminUserResponse(id=user.id, email=user.email, name=user.name, role=user.role, phone=user.phone, vehicle_no=user.vehicle_no,
                                     event_count=count, last_event_at=last, driving=driving, drive_min=drive_timer.drive_min(user.id) if driving else 0))
    return out


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


# ── 관리자 가입 (관리자 웹 admin_signup.html, 11/19) ─────────────────
#   회사가 따로 정한 '인증된 사번'(.env ADMIN_EMPLOYEE_NOS)만 관리자 계정을 만들 수 있다. 로그인 없이 부르는 API (가입 전이니까)
#   - 한 사번 = 한 계정: 가입에 쓴 사번은 users.emp_no 에 남긴다 (기사 사번과 같은 칸 → 두 목록에 같은 번호가 있어도 한 번만 쓰임)
#   - 사번 알아맞히기 방지: 같은 접속 주소에서 10분에 5번 틀리면 429 (모의 서버와 같은 규칙)
#     접속 주소는 PC 서버 = 연결한 주소, Railway = X-Real-IP 헤더 (config.TRUST_X_REAL_IP, 11/19 팀장 지적)
#   - 응답 · 문구는 모의 서버(mock_server.py)와 같은 모양 → 관리자 웹 화면은 고치지 않음
_signup_lock = threading.RLock()                # 같은 사번 동시 가입 막기 (가입 안에서 사번 확인이 한 번 더 잡으므로 RLock) (로컬 DB 의 users.emp_no 에는 고유 제약이 없을 수 있음)
_signup_fails: dict[str, list[float]] = {}      # 접속 주소 → 사번을 틀린 시각들


def _client_key(request: Request) -> str:
    """사번을 틀린 횟수를 셀 '접속 주소'. Railway 에서는 X-Real-IP (모두 같은 주소로 보여서 한 사람 실수로 모두 잠기는 것 방지)."""
    if config.TRUST_X_REAL_IP:
        real = (request.headers.get("x-real-ip") or "").strip()
        try:
            return str(ipaddress.ip_address(real))       # IP 모양이 아니면 아래 기본값으로
        except ValueError:
            pass
    return request.client.host if request.client else "?"


def _check_admin_employee(raw: str, request: Request, db: Session) -> str:
    """관리자 가입에 쓸 수 있는 사번이면 정리한 사번. 아니면 HTTPException."""
    no = re.sub(r"\s", "", raw or "")
    if not re.fullmatch(r"\d{4,12}", no):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="사번은 숫자 4~12자리로 입력해 주세요")
    if not config.ADMIN_EMPLOYEE_NOS:
        print("⚠️ [admin-signup] .env 에 ADMIN_EMPLOYEE_NOS 가 없어 관리자 가입이 닫혀 있음 (관리자는 tools/make_admin.py 로)")
        raise HTTPException(status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="관리자 가입이 아직 열려 있지 않아요. 담당자에게 문의해 주세요")

    who, now = _client_key(request), time.time()
    window = config.ADMIN_SIGNUP_LOCK_MIN * 60
    with _signup_lock:
        if len(_signup_fails) > 1000:           # 오래된 기록 정리 (아무 주소에서나 틀려도 메모리가 계속 늘지 않게)
            for k in [k for k, v in _signup_fails.items() if not v or v[-1] < now - window]:
                _signup_fails.pop(k, None)
        fails = [t for t in _signup_fails.get(who, []) if t > now - window]
        if len(fails) >= config.ADMIN_SIGNUP_MAX_FAILS:
            raise HTTPException(status_code=status.HTTP_429_TOO_MANY_REQUESTS,
                                detail=f"사번을 너무 많이 틀렸어요. {config.ADMIN_SIGNUP_LOCK_MIN}분 뒤에 다시 시도해 주세요",
                                headers={"Retry-After": str(int(fails[0] + window - now) + 1)})
        if no not in config.ADMIN_EMPLOYEE_NOS:
            fails.append(now)
            _signup_fails[who] = fails
            raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="등록되지 않은 사번이에요")
        _signup_fails.pop(who, None)            # 맞게 넣으면 틀린 기록은 지움

    if db.scalar(select(User.id).where(User.emp_no == no)) is not None:
        raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입에 쓰인 사번이에요")
    return no


@router.post("/signup/check")
def admin_signup_check(body: AdminEmployeeCheck, request: Request, db: Session = Depends(get_db)):
    """관리자 가입 1단계 — 인증된 사번이고 아직 가입에 안 쓰였는지. 200 {success}"""
    _check_admin_employee(body.employee_no, request, db)
    return {"success": True}


@router.post("/signup", status_code=status.HTTP_201_CREATED)
def admin_signup(body: AdminSignupRequest, request: Request, db: Session = Depends(get_db)):
    """관리자 가입 2단계 — 사번을 한 번 더 확인하고 관리자(role=admin) 계정을 만든다. 그 뒤 이메일 · 비밀번호로 로그인"""
    email = str(body.email)
    with _signup_lock:                          # 확인 ~ 저장 사이에 같은 사번 · 이메일로 끼어들지 못하게
        no = _check_admin_employee(body.employee_no, request, db)
        if db.scalar(select(User.id).where(User.email == email)) is not None:
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입된 이메일이에요")
        user = User(
            emp_no=no,
            email=email,
            hashed_password=hash_password(body.password),
            name=body.name,
            role="admin",
            provider="email",
        )
        db.add(user)
        try:
            db.commit()
        except IntegrityError:
            db.rollback()
            raise HTTPException(status_code=status.HTTP_409_CONFLICT, detail="이미 가입된 이메일 또는 사번이에요")
    print(f"✅ [admin-signup] 관리자 가입: 사번 {no} → user {user.id}")
    return {"success": True}
