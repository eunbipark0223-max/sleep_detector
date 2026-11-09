# ═══════════════════════════════════════════════════════════════
# routers/event.py — 내 경고 목록 · 처리 상태 변경
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0
# 수업 원본: road_hazard_api/routers/hazard.py (🟡 이름 변경 + 수정)
#
# [이 파일이 하는 일]
#   - GET /events/my — 내 경고 목록 (앱 운행 기록 화면)
#   - PATCH /events/{id}/status — 관리자가 상태 변경. '조치완료'면 sleep_state reset → 3단계 해제 (앱은 다음 ping 에서 0단계)
#     '확인'은 미확인일 때만 바뀐다 (관리자 웹이 상세를 열 때 자동으로 보냄, 11/09)
#
# [주의]
#   - 수업의 POST /hazards (직접 신고) · POST /reports 는 만들지 않는다
#
# [연결 약속 — 다른 사람 파일의 이름. 다르면 아래 import 한 줄만 고친다]
#   - services.sleep_state.reset(user_id) — 그 기사의 졸음 기록 · 단계를 0 으로 (A)
#   - 휴식완료 상태는 /drive/resume (detect.py) 가 직접 바꾼다. 여기서는 관리자 화면의 변경만
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select
from sqlalchemy.orm import Session

from auth.jwt import get_current_user
from database.orm import get_db
from models.models import SleepEvent, User
from routers.admin import require_admin
from schema.request import StatusUpdate
from schema.response import SleepEventResponse
from services import sleep_state

router = APIRouter(prefix="/events", tags=["events"])


@router.get("/my", response_model=list[SleepEventResponse])
def my_events(db: Session = Depends(get_db), user: User = Depends(get_current_user)):
    """내 경고 목록, 최신순 (앱 운행 기록 · 홈의 최근 경고)."""
    events = db.execute(
        select(SleepEvent).where(SleepEvent.user_id == user.id).order_by(SleepEvent.id.desc())
    ).scalars().all()
    return [SleepEventResponse.from_event(e) for e in events]


@router.patch("/{event_id}/status")
def update_status(
    event_id: int,
    body: StatusUpdate,
    db: Session = Depends(get_db),
    _admin: User = Depends(require_admin),
):
    """관리자가 경고 처리 상태를 바꾼다. 조치완료 → 그 기사의 3단계를 푼다."""
    event = db.get(SleepEvent, event_id)
    if event is None:
        raise HTTPException(status_code=404, detail="없는 경고입니다")
    # '확인' = 관리자 웹이 경고 상세를 열면 자동으로 보내는 '열어 봄' 표시 (11/09).
    # 미확인일 때만 바꾼다 — 이미 조치완료 · 휴식완료인 경고를 늦게 도착한 '확인'이 되돌리지 않게
    if body.status == "확인" and event.status != "미확인":
        return {"success": True, "id": event.id, "status": event.status, "stage_reset": False}
    event.status = body.status
    db.commit()

    stage_reset = body.status == "조치완료"
    if stage_reset:
        sleep_state.reset(event.user_id)  # 앱은 다음 ping 에서 0단계를 받는다
    return {"success": True, "id": event.id, "status": event.status, "stage_reset": stage_reset}
