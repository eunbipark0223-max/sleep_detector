# ═══════════════════════════════════════════════════════════════
# routers/detect.py — 졸음 의심 사진 확인 + 운행 API  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0 (퀴즈 연결은 P1)
# 수업 원본: road_hazard_api/routers/detect.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - POST /detect — 앱이 '졸음 의심' 때만 보냄 (사진 1장 + reason · closed_sec · perclos · eye_open_prob · 위도 · 경도, JWT 필수)
#   -   ① 로그인 · 사진 확인 (uploads/tmp/ 에 잠깐)
#   -   ② 확인 판정 face_service → 취소면 사진 삭제 후 바로 응답 (is_sleep false, AI 안 부름)
#   -   ③ sleep_state 에 졸음 1회 → 규칙 단계   ④ LLM 요약   ⑤ RAG 규정
#   -   ⑥ Agent 단계 · 안내문 · 보고서 · driver_voice → 바닥 · 천장 검사 + 음성 보고 숫자 검사
#   -   ⑦ 저장 (사진 uploads/events/ + DB 1줄)   ⑧ 음성 퀴즈 1문제 (경고 저장 뒤, quiz_id ↔ event_id 기억)
#   -   reason 이 비어 있으면 '사진 1장 테스트' → 서버 EAR 만으로 판정
#   - POST /drive/start — 운행 시작: 졸음 기록 · 단계 0, 연속 운전 시간 시작
#   - POST /drive/calibrate — 개인 기준 측정 사진 1장씩, 5장 모이면 서버 개인 기준 EAR 완성
#   - POST /drive/ping — 30초마다 (사진 없음). 응답: stage · status · drive_min · rest_due · rest_message
#   - POST /drive/rest — [정차했어요] → 휴식 시작 시각 기록
#   - POST /drive/resume — [운행 재개] → 15분 지났는지 서버 시각으로 검사 → 2단계면 1단계, 상태 '휴식완료'
#
# [주의]
#   - 응답 모양은 기획안 9-3 (졸음) · 9-5 (ping) 그대로 — 앱 sleep_response.dart · drive_status.dart 와 맞춰야 함
#     (D 의 mock_server.py 와도 같은 모양 → 앱은 주소만 바꾸면 진짜 서버로 넘어감)
#   - 숫자는 _normalize 로 int / float 확정해서 보냄 (수업에서 배운 '5' 문자열 사고 방지)
#
# [연결 약속 — 다른 사람 파일의 이름]
#   - sleep_state (A): reset · get_stage · add_sleep · set_stage · facts · start_rest · rest_elapsed_min · finish_rest
#                      · get_ear_threshold · set_ear_threshold
#   - face_service (A): check_eyes(path, user_id, reason) · calibrate(paths)
#   - drive_timer (팀장): start · ping · rest_done · drive_min
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

import json
import os
import threading
import uuid
from datetime import datetime
from typing import Optional

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

import config
from auth.jwt import get_current_user
from database.db_connection import get_session
from models.models import SleepEvent, User
from schema.request import DrivePing
from services import drive_timer, face_service, sleep_state

router = APIRouter(tags=["운행 · 감지"])

ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024

# 개인 기준 측정: 사진을 CALIB_FRAMES 장 모을 때까지 기사별로 잠깐 보관 (끝나면 지움)
_calib_photos = {}       # user_id → [임시 사진 경로, ...]
# [정차했어요] 때 휴식완료로 바꿀 2단계 경고 번호
_rest_event = {}         # user_id → event_id
_lock = threading.Lock()


def _label(stage):
    return config.STAGE_LABELS.get(int(stage), "")


async def _save_upload(file: UploadFile, folder: str, prefix: str) -> str:
    """사진 확인 (확장자 · 크기) → folder 에 저장 → 경로. 수업 detect.py 의 검사 그대로."""
    ext = os.path.splitext(file.filename or "photo.jpg")[1].lower() or ".jpg"
    if ext not in ALLOWED_EXTS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"이미지 파일만 올릴 수 있습니다 ({', '.join(sorted(ALLOWED_EXTS))})")
    content = await file.read()
    if not content:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "빈 파일입니다")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "사진이 너무 큽니다 (최대 10MB)")
    os.makedirs(folder, exist_ok=True)
    path = os.path.join(folder, f"{prefix}_{uuid.uuid4().hex[:12]}{ext}")
    with open(path, "wb") as f:
        f.write(content)
    return path


def _remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


def _open_stage2_event(session: Session, user_id: int) -> Optional[SleepEvent]:
    """[정차했어요] 때 휴식완료로 바꿀 경고 — 가장 최근의 아직 처리 안 된 2단계 경고."""
    return session.scalar(
        select(SleepEvent)
        .where(SleepEvent.user_id == user_id, SleepEvent.stage == 2, SleepEvent.status.in_(["미확인", "확인"]))
        .order_by(SleepEvent.id.desc())
    )


# ───────────────────────────────────────────────
# 운행 API
# ───────────────────────────────────────────────
@router.post("/drive/start")
def drive_start_handler(user: User = Depends(get_current_user)):
    sleep_state.reset(user.id)
    drive_timer.start(user.id)
    with _lock:
        for p in _calib_photos.pop(user.id, []):
            _remove(p)
        _rest_event.pop(user.id, None)
    return {"success": True, "message": "운행을 시작합니다", "stage": 0, "status": _label(0)}


@router.post("/drive/calibrate")
async def drive_calibrate_handler(file: UploadFile = File(...), user: User = Depends(get_current_user)):
    """출발 때 '정면 5초' — 사진 1장씩. CALIB_FRAMES 장이 모이면 서버 개인 기준 EAR 완성."""
    path = await _save_upload(file, config.UPLOAD_TMP_DIR, f"calib_u{user.id}")
    with _lock:
        photos = _calib_photos.setdefault(user.id, [])
        photos.append(path)
        count = len(photos)
        done = count >= config.CALIB_FRAMES
        if done:
            _calib_photos.pop(user.id, None)

    if not done:
        return {"success": True, "count": count, "needed": config.CALIB_FRAMES, "done": False, "ear_threshold": None}

    try:
        threshold = face_service.calibrate(photos)
    finally:
        for p in photos:                     # 개인정보 — 측정이 끝나면 사진은 남기지 않음
            _remove(p)
    sleep_state.set_ear_threshold(user.id, threshold)
    return {"success": True, "count": config.CALIB_FRAMES, "needed": config.CALIB_FRAMES, "done": True,
            "ear_threshold": round(float(threshold), 3)}


@router.post("/drive/ping")
def drive_ping_handler(
    body: Optional[DrivePing] = None,
    session: Session = Depends(get_session),
    user: User = Depends(get_current_user),
):
    """30초마다. 단계(1단계 자동 해제 · 조치완료 반영) · 연속 운전 시간 · 휴게 알림."""
    t = drive_timer.ping(user.id)
    stage = int(sleep_state.get_stage(user.id))

    if t["rest_overdue"]:                    # 휴게 알림 뒤 15분 안에 안 쉼 → 경고 1줄 (단계는 그대로)
        session.add(SleepEvent(
            user_id=user.id, stage=max(stage, 1), reason="rest_overdue", method="mlkit",
            perclos=body.perclos if body else None,
            summary=f"휴게 알림 뒤 {config.REST_GRACE_MIN}분이 지나도록 휴식하지 않았습니다 (연속 운전 {t['drive_min']}분).",
            guidance=f"가까운 졸음쉼터에서 {config.REST_MIN}분 이상 쉬어 주세요.",
            report=json.dumps({"situation": "휴게 미준수", "drive_min": t["drive_min"]}, ensure_ascii=False),
        ))
        session.commit()

    return {"stage": stage, "status": _label(stage), "drive_min": int(t["drive_min"]),
            "rest_due": bool(t["rest_due"]), "rest_message": t["rest_message"]}


@router.post("/drive/rest")
def drive_rest_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """[정차했어요] → 휴식 시작 시각 기록 (서버 시각)."""
    sleep_state.start_rest(user.id)
    event = _open_stage2_event(session, user.id)
    with _lock:
        if event:
            _rest_event[user.id] = event.id
        else:
            _rest_event.pop(user.id, None)
    return {"success": True, "message": f"{config.REST_MIN}분 쉬고 출발하세요", "rest_sec": config.REST_MIN * 60,
            "started": datetime.now().strftime("%H:%M")}


@router.post("/drive/resume")
def drive_resume_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """[운행 재개] → 서버 시각으로 15분 검사 → 2단계면 1단계로, 그 경고는 '휴식완료'."""
    elapsed = sleep_state.rest_elapsed_min(user.id)
    if elapsed is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "정차 기록이 없습니다. [정차했어요] 를 먼저 눌러 주세요")
    if elapsed < config.REST_MIN:
        left = max(1, int(round((config.REST_MIN - elapsed) * 60)))
        raise HTTPException(status.HTTP_409_CONFLICT, f"아직 휴식 시간이 지나지 않았습니다 ({left}초 남음)")

    stage = int(sleep_state.get_stage(user.id))
    if stage == 2:                           # 2단계만 1단계로. 3단계는 관리자만 해제
        stage = int(sleep_state.finish_rest(user.id))
    drive_timer.rest_done(user.id)

    with _lock:
        event_id = _rest_event.pop(user.id, None)
    event = session.get(SleepEvent, event_id) if event_id else None
    if event:
        report = json.loads(event.report) if event.report else {}
        now = datetime.now()
        started = datetime.fromtimestamp(now.timestamp() - elapsed * 60)
        report["rest"] = {"started": started.strftime("%H:%M"), "resumed": now.strftime("%H:%M"),
                          "minutes": int(elapsed)}
        event.report = json.dumps(report, ensure_ascii=False)
        event.status = "휴식완료"
        session.commit()

    message = {0: "운행을 재개합니다", 1: "주의 단계로 다시 출발합니다",
               3: "긴급 단계는 관리자가 조치완료를 누르기 전까지 해제되지 않습니다"}.get(stage, "운행을 재개합니다")
    return {"success": True, "stage": stage, "status": _label(stage), "message": message}
