# ═══════════════════════════════════════════════════════════════
# routers/detect.py — 졸음 의심 사진 확인 + 운행 API  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0 (퀴즈 연결은 P1)
#
# [이 파일이 하는 일]
#   - POST /detect — 앱이 '졸음 의심' 때만 보냄 (사진 1장 + reason · closed_sec · perclos · eye_open_prob · 위도 · 경도, JWT 필수)
#     (11/16 재설계) 경고는 규칙이 바로 (응답 전 0.1초 미만) · AI 는 응답 뒤에서 관리자 보고서만
#     ── 응답 전 ──
#   -   ① 로그인 · 사진 확인 (uploads/tmp/ 에 잠깐) · 휴식 중이면 무시 · half(반쯤 감은 눈)는 4번 중 3번일 때만 확정
#   -   ② 확인 판정 face_service (CNN + EAR) → 취소면 사진 삭제 후 바로 응답 (is_sleep false, AI 안 부름)
#   -   ②-1 예비 경고 (PRE_WARN_ON, 11/15부터 기본 꺼짐)
#   -   ③ sleep_state 에 졸음 1회 → 규칙 단계 (0 ~ 3) · facts (10분 졸음 횟수 · 감은 시간 · 운전 시간) · stage_note
#   -   ④ 단계 · 기사 음성 · 요약 = 규칙 템플릿 (llm_service.template_summary · agent_service.rule_response)
#   -   ⑦ 저장 (확정 사진 uploads/events/ + DB 1줄, guidance = 기사가 실제로 들은 문장)
#   -   ⑧ 2단계만 음성 퀴즈 1문제 (경고 저장 뒤, quiz_id ↔ event_id 기억) · 3단계는 [깨어 있어요] 버튼
#   -   ⑨ 2단계부터 BackgroundTasks 로 _fill_ai_report 예약 → 앱에 응답
#     ── 응답 뒤 (2단계부터, 약 3 ~ 6초) ──
#   -   _fill_ai_report: LLM 상황 요약 → RAG 규정 → Agent 관리자 보고서 → 같은 경고 기록의 summary · report 채움
#       단계는 바꾸지 않음 (AGENT_MAX_STEP_UP = 0) · guidance 는 덮어쓰지 않음 · 실패해도 템플릿 기록 그대로
#   -   1단계는 AI 를 부르지 않음 (첫 졸음 · 무료 한도 보호)
#   -   reason 이 비어 있으면 '사진 1장 테스트' → 서버 EAR 만으로 판정
#   -   사진 없이 오면 (고개를 떨궈 얼굴을 놓친 채 감김, 10/28) → '얼굴 없음' 과 같이 앱 판단대로 확정 (method mlkit, photo_path 없음)
#       사진 1장 테스트(reason 없음)는 사진이 꼭 있어야 함 → 400
#   - POST /drive/start — 운행 시작: 0 · 1단계만 0 으로 (2 · 3단계 · 10분 졸음 기록은 유지), 연속 운전 시간 시작
#   - 휴식 중([정차했어요] ~ [운행 재개])에 온 /detect 는 기록하지 않음 — 휴식 화면 아래 운행 화면 카메라가 계속 돌아서
#     쉬면서 눈을 감으면 단계가 올라가던 문제 (11/03 A 확인)
#   - POST /drive/calibrate — 개인 기준 측정 사진 1장씩, 5장 모이면 서버 개인 기준 EAR 완성
#   - POST /drive/ping — 30초마다 (사진 없음). 응답: stage · status · drive_min · rest_due · rest_message
#   - POST /drive/rest — [정차했어요] → 휴식 시작 시각 기록
#   - GET  /drive/state — 앱을 껐다 켰을 때 이어 가기: active · stage · resting · rest_left_sec · summary · guidance
#   - POST /drive/end — [운행 종료] (홈 배너가 안 뜨게. 2 · 3단계는 그대로)
#   - POST /drive/resume — [운행 재개] → 15분 지났는지 서버 시각으로 검사 → 2단계면 1단계, 상태 '휴식완료'
#
# [주의]
#   - 응답 모양은 기획안 9-3 (졸음) · 9-5 (ping) 그대로 — 앱 sleep_response.dart · drive_status.dart 와 맞춰야 함
#     (D 의 mock_server.py 와도 같은 모양 → 앱은 주소만 바꾸면 진짜 서버로 넘어감)
#   - 숫자는 _normalize 로 int / float 확정해서 보냄 ('5' 같은 문자열 사고 방지)
#
# [연결 약속 — 다른 사람 파일의 이름]
#   - sleep_state (A): start_drive · reset · get_stage · add_sleep · set_stage · facts · start_rest · rest_elapsed_min · finish_rest
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

import shutil
import time

from fastapi import APIRouter, BackgroundTasks, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from sqlalchemy import select
from sqlalchemy.orm import Session

import config
from fastapi.security import HTTPAuthorizationCredentials

from auth.jwt import bearer, get_current_user, refreshed_token
from database.db_connection import SessionLocal, get_session
from models.models import SleepEvent, User
from schema.request import DrivePing
from services import (agent_service, drive_timer, face_service, llm_service, rag_service, sleep_state,
                      voice_quiz_service)

router = APIRouter(tags=["운행 · 감지"])

ACTIVE_PING_SEC = 5 * 60   # 앱이 꺼진 지 이 시간 안이면 홈 화면이 '진행 중인 운행' 으로 봄 (2 · 3단계 · 휴식 중은 시간과 상관없이)
PRE_WARN_VOICE = "졸음이 느껴지면 창문을 열고 환기해 주세요. 다시 졸면 주의 단계로 경고해요."   # 예비 경고 음성 (mock_server 와 같은 문장, 11/12)
ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024

# 개인 기준 측정: 사진을 CALIB_FRAMES 장 모을 때까지 기사별로 잠깐 보관 (끝나면 지움)
_calib_photos = {}       # user_id → [임시 사진 경로, ...]
# [정차했어요] 때 휴식완료로 바꿀 2단계 경고 번호
_rest_event = {}         # user_id → event_id
_stop_event = {}         # (11/26) user_id → [정차했어요] 를 누를 때 열려 있던 2 · 3단계 경고 (AI 보고서 '기사님이 한 일')
_lock = threading.Lock()
# 서버를 켠 뒤 /detect 판정 방식별 건수 (GET /health — method 가 cnn 이 아니면 폴백이 난 것)
_method_counts = {"cnn": 0, "ear": 0, "mlkit": 0}


def _num(v):
    """Form 으로 온 숫자 글자 → float (비었거나 이상하면 None)"""
    try:
        return None if v in (None, "") else float(v)
    except (TypeError, ValueError):
        return None


def _r(v, n=3):
    return None if v is None else round(float(v), n)


def _label(stage):
    return config.STAGE_LABELS.get(int(stage), "")


async def _save_upload(file: UploadFile, folder: str, prefix: str) -> str:
    """사진 확인 (확장자 · 크기) → folder 에 저장 → 경로."""
    ext = os.path.splitext(file.filename or "photo.jpg")[1].lower() or ".jpg"
    if ext not in ALLOWED_EXTS:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, f"이미지 파일만 올릴 수 있습니다 ({', '.join(sorted(ALLOWED_EXTS))})")
    content = await file.read()
    if not content:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "빈 파일입니다")
    if len(content) > MAX_UPLOAD_BYTES:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "사진이 너무 큽니다 (최대 10MB)")
    os.makedirs(folder, exist_ok=True)
    # 원래 이름 일부를 뒤에 남긴다 — face_service 가짜 모드가 파일 이름의 closed / noface 로 판정하기 때문
    stem = "".join(ch for ch in os.path.splitext(os.path.basename(file.filename or ""))[0] if ch.isalnum() or ch in "-_")[:20]
    path = os.path.join(folder, f"{prefix}_{uuid.uuid4().hex[:12]}{'_' + stem if stem else ''}{ext}")
    with open(path, "wb") as f:
        f.write(content)
    return path


def _remove(path):
    try:
        os.remove(path)
    except OSError:
        pass


# (11/25 팀장) 고개 숙임 경고에도 관리자 웹 사진 — 앱은 숙임을 처음 사진과 보내고, 서버가 취소하면(얼굴 없음 · 눈 뜸)
#   숙인 채 계속이면 사진 없이 다시 보낸다 → 그 경고는 사진이 없었음. 취소된 사진을 잠깐(HELD_PHOTO_SEC) 들고 있다가
#   사진 없이 온 경고가 확정되면 그 사진을 붙인다. 시간이 지나거나 다음 취소 사진이 오면 바로 지움 (개인정보)
HELD_PHOTO_SEC = 60
_held_photos: dict[int, tuple[str, float]] = {}     # user_id → (임시 사진 경로, 취소 시각)


def _sweep_held():
    """시간이 지난 들고 있던 사진을 모두 지움 (다른 기사 것 포함 — 다시 보내지 않은 사진이 남지 않게)"""
    now = time.time()
    with _lock:
        old = [uid for uid, (_, at) in _held_photos.items() if now - at > HELD_PHOTO_SEC]
        paths = [_held_photos.pop(uid)[0] for uid in old]
    for p in paths:
        _remove(p)


def _hold_photo(user_id: int, path):
    if not path:
        return
    _sweep_held()
    with _lock:
        old = _held_photos.pop(user_id, None)
        _held_photos[user_id] = (path, time.time())
    if old:
        _remove(old[0])


def _take_held_photo(user_id: int):
    """HELD_PHOTO_SEC 안에 취소된 사진이 있으면 꺼내 준다 (한 번만). 오래된 것은 지움."""
    _sweep_held()
    with _lock:
        held = _held_photos.pop(user_id, None)
    if not held:
        return None
    path, at = held
    if time.time() - at > HELD_PHOTO_SEC or not os.path.exists(path):
        _remove(path)
        return None
    return path


def _open_stage2_event(session: Session, user_id: int) -> Optional[SleepEvent]:
    """[정차했어요] 때 휴식완료로 바꿀 경고 — 가장 최근의 아직 처리 안 된 2단계 경고."""
    return session.scalar(
        select(SleepEvent)
        .where(SleepEvent.user_id == user_id, SleepEvent.stage == 2, SleepEvent.status.in_(["미확인", "확인"]))
        .order_by(SleepEvent.id.desc())
    )


def _open_alert_event(session: Session, user_id: int) -> Optional[SleepEvent]:
    """(11/26 팀장) [정차했어요] 를 누를 때 열려 있는 가장 최근의 2 · 3단계 경고 — 그 보고서에 '정차함' 을 남긴다."""
    return session.scalar(
        select(SleepEvent)
        .where(SleepEvent.user_id == user_id, SleepEvent.stage >= 2, SleepEvent.status.in_(["미확인", "확인"]))
        .order_by(SleepEvent.id.desc())
    )


def _add_report(event: SleepEvent, key: str, value) -> None:
    try:
        report = json.loads(event.report) if event.report else {}
    except (TypeError, ValueError):
        report = {}
    report[key] = value
    event.report = json.dumps(report, ensure_ascii=False)


def method_counts() -> dict:
    """서버를 켠 뒤 판정 방식별 건수 (main.py GET /health)"""
    with _lock:
        return dict(_method_counts)


# ───────────────────────────────────────────────
# 운행 API
# ───────────────────────────────────────────────
# ───────────────────────────────────────────────
# POST /drive/wake — (11/15 팀장) 3단계 [깨어 있어요] 응답 {pressed, sec}
#   3단계 경고는 들어오는 순간 관리자에게 긴급으로 이미 간다 → 여기서는 그 경고 기록(report.wake)에 응답만 덧붙인다
#   pressed=True  : 10초 안에(또는 늦게라도) 눌렀음 → 관리자 웹 초록 '깨어 있음 (N초)'
#   pressed=False : 10초 동안 안 누름 → 관리자 웹 빨간 '응답 없음' · 배너 '바로 전화하세요' (알림음은 다시 울리지 않음)
#   가장 최근의 미처리 3단계 경고에 붙인다 (없으면 아무것도 안 함)
# ───────────────────────────────────────────────
@router.post("/drive/wake")
def drive_wake_handler(body: dict, session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    pressed = bool(body.get("pressed"))
    sec = body.get("sec")
    event = session.scalar(
        select(SleepEvent)
        .where(SleepEvent.user_id == user.id, SleepEvent.stage >= 3, SleepEvent.status != "조치완료")
        .order_by(SleepEvent.created_at.desc(), SleepEvent.id.desc())
    )
    if event is None:
        return {"success": True, "event_id": None}
    try:
        report = json.loads(event.report) if isinstance(event.report, str) and event.report else dict(event.report or {})
    except (TypeError, ValueError):
        report = {}
    report["wake"] = {"pressed": pressed, "sec": round(float(sec), 1) if isinstance(sec, (int, float)) else None,
                      "at": datetime.now().isoformat(timespec="seconds")}
    event.report = json.dumps(report, ensure_ascii=False)
    session.commit()
    print(f"[detect] {datetime.now():%H:%M:%S} u{user.id} 3단계 응답 → {'깨어 있음' if pressed else '응답 없음'}"
          f"{f' ({sec}초)' if sec is not None else ''} · 경고 #{event.id}")
    return {"success": True, "event_id": event.id, "pressed": pressed}


@router.post("/drive/start")
def drive_start_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    # 2 · 3단계는 유지 — 다시 시작으로 경고를 끌 수 없게 (기획안 8장, 11/03 A start_drive)
    stage = int(sleep_state.start_drive(user.id)["stage"])
    drive_timer.start(user.id)
    last_id = session.execute(select(SleepEvent.id).where(SleepEvent.user_id == user.id)
                              .order_by(SleepEvent.id.desc()).limit(1)).scalar() or 0
    with _lock:
        # (11/16) 운행 종료 리포트는 이 운행부터 센다 — DB 시각(created_at)은 DB 시간대라 시각 대신 마지막 경고 번호로
        _session_start[user.id] = (datetime.now(), last_id)
        for p in _calib_photos.pop(user.id, []):
            _remove(p)
        _rest_event.pop(user.id, None)
    return {"success": True, "message": "운행을 시작합니다", "stage": stage, "status": _label(stage)}


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
        threshold = face_service.calibrate(photos, user_id=user.id)   # user_id → 뜬 눈 EAR 중간값도 저장 (반쯤 감은 눈 기준, 11/10)
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
    authorization: HTTPAuthorizationCredentials | None = Depends(bearer),
):
    """30초마다. 단계(1단계 자동 해제 · 조치완료 반영) · 연속 운전 시간 · 휴게 알림 · (토큰이 곧 끝나면) 새 토큰."""
    t = drive_timer.ping(user.id)
    stage = int(sleep_state.get_stage(user.id))

    if t["rest_overdue"]:                    # 휴게 알림 뒤 15분 안에 안 쉼 → 경고 1줄 (단계는 그대로)
        # (11/23 팀장) 관리자 상세 'AI 분석 결과' 칸을 AI 없이 정해진 문장으로 채움 — 숫자 · 규정이 정해져 있어 정확하고 무료 한도도 안 씀
        situation = (f"연속 {drive_timer.span_text(t['drive_min'])} 운전 · "
                     f"휴게 알림 뒤 {config.REST_GRACE_MIN}분 동안 쉬지 않음")
        session.add(SleepEvent(
            user_id=user.id, stage=max(stage, 1), reason="rest_overdue", method="mlkit",
            perclos=body.perclos if body else None,
            summary=situation,
            guidance=f"가까운 졸음쉼터에서 {config.REST_MIN}분 이상 쉬어 주세요.",
            report=json.dumps({
                "situation": situation,
                "stage_reason": f"\"연속 {drive_timer.span_text(config.DRIVE_LIMIT_MIN)} 운전 후 {config.REST_MIN}분 휴식\" 규정 미준수",
                "regulation": drive_timer.rest_rule(),
                "recommended_action": "기사에게 연락해 휴식 안내",
                "drive_min": t["drive_min"],
                "is_real": {"llm": False, "rag": False, "agent": False, "driver_voice": False},   # 정해진 문장 (AI 아님)
            }, ensure_ascii=False),
        ))
        session.commit()

    out = {"stage": stage, "status": _label(stage), "drive_min": int(t["drive_min"]),
           "rest_due": bool(t["rest_due"]),
           # (11/24 팀장) 휴게 안내는 다른 경고처럼 '○○님, ' 으로 시작
           "rest_message": f"{_driver_name(user.name) or '기사'}님, {t['rest_message']}" if t["rest_message"] else ""}
    new_token = refreshed_token(authorization, user)
    if new_token:                            # 앱이 저장해서 다음 요청부터 씀 (운행 중 401 방지)
        out["access_token"] = new_token
    return out


@router.get("/drive/state")
def drive_state_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """앱을 껐다 켰을 때 '진행 중인 운행'을 이어 가기 위한 지금 상태 (홈 화면 배너 · 운행 화면 이어받기).

    active  : 이어서 운행할 것이 있음 — 2 · 3단계(풀릴 때까지) · 휴식 중 · 최근 ping 이 ACTIVE_PING_SEC 안
    resting : [정차했어요] 뒤 쉬는 중 (rest_left_sec = 남은 초, 0 이면 [운행 재개] 가능)
    summary · guidance : 지금 단계를 만든 가장 최근 경고의 글 (이어서 연 경고 화면에 보여 줌)
    """
    stage = int(sleep_state.get_stage(user.id))
    elapsed = sleep_state.rest_elapsed_min(user.id)
    resting = elapsed is not None
    age = drive_timer.last_ping_age(user.id)
    recent = age is not None and age <= ACTIVE_PING_SEC
    summary = guidance = ""
    if stage >= 1:
        event = session.scalar(
            select(SleepEvent)
            .where(SleepEvent.user_id == user.id, SleepEvent.stage >= 1, SleepEvent.reason != "rest_overdue",
                   SleepEvent.status.in_(["미확인", "확인"]))
            .order_by(SleepEvent.id.desc())
        )
        if event:
            summary, guidance = event.summary or "", event.guidance or ""
    return {"active": bool(stage >= 2 or resting or recent), "stage": stage, "status": _label(stage),
            "resting": resting,
            "rest_left_sec": max(0, int(round(config.REST_WAIT_SEC - elapsed * 60))) if resting else 0,
            "drive_min": int(drive_timer.drive_min(user.id)), "summary": summary, "guidance": guidance}


_session_start: dict[int, tuple] = {}   # user_id → (시작 시각, 그때 마지막 경고 id)
# (11/18 팀장) 운행 종료 리포트의 AI 문장 — 뒤에서 채움. report_id → {user_id, done, summary, advice, is_real, at}
_drive_reports: dict[str, dict] = {}
DRIVE_REPORT_KEEP_SEC = 600   # 10분 지난 것은 지움 (앱은 화면을 연 동안만 물어봄)
STAGE1_DELIVERED = "졸음이 감지됐어요. 정신 차려 주세요."   # (11/18) 앱 1단계 음성과 같은 문장 (drive_screen._stage1Voice · stage_texts)
# (11/23 팀장 용어표) 운행 리포트 타임라인 = 기사 앱 말 (관리자 웹은 admin.html REASON_LABEL)
_REASON_TEXT = {"microsleep": "순간 졸음", "perclos": "졸음 잦음", "no_face": "고개 숙임", "half": "눈 반쯤 감김",
                "rest_overdue": "휴식 안 함", "no_response": "퀴즈 응답 없음", "pre_warning": "첫 졸음"}


def _driver_name(name):
    """(11/17 팀장) 기사 이름만 — '박은비' (없으면 ''). 앱 AuthService.driverName 과 같음
    운행 리포트: '이름 기사님' · 음성: '이름님' — 이름이 없으면 둘 다 '기사님'"""
    return (name or "").strip()


def _fill_drive_report(report_id, stats):
    """(11/18 팀장) [운행 종료] 뒤 뒤에서 — AI 리포트 문장을 만들어 _drive_reports 에 넣는다 (실패하면 템플릿 그대로 done)"""
    ai = agent_service.drive_report(stats)
    with _lock:
        item = _drive_reports.get(report_id)
        if item is not None:
            item.update({"done": True, "summary": ai["summary"], "advice": ai["advice"], "is_real": ai["is_real"]})
    print(f"[detect] 운행 리포트 {report_id[:8]} 뒤에서 채움 ({'AI' if ai['is_real'] else '템플릿'})")


@router.get("/drive/report/{report_id}")
def drive_report_handler(report_id: str, user: User = Depends(get_current_user)):
    """(11/18 팀장) 운행 종료 리포트의 AI 문장 — 앱이 리포트 화면을 연 동안 몇 초마다 물어봄. 아직이면 done=False"""
    with _lock:
        item = _drive_reports.get(report_id)
    if item is None or item["user_id"] != user.id:
        raise HTTPException(status_code=404, detail="리포트가 없어요")
    return {k: item[k] for k in ("done", "summary", "advice", "is_real")}


@router.post("/drive/end")
def drive_end_handler(background: BackgroundTasks, session: Session = Depends(get_session),
                      user: User = Depends(get_current_user)):
    """[운행 종료] — 단계는 그대로(2 · 3단계는 계속 이어짐), 진행 중인 운행만 끝냄.
    (11/16 팀장) + 오늘 운행 AI 리포트: 운행 시간 · 졸음 횟수 · 최고 단계 · 휴식 · 시간표 · 다음 운행 조언"""
    drive_timer.end(user.id)
    with _lock:
        started, last_id = _session_start.pop(user.id, (None, 0))
    now = datetime.now()
    if started is None or (now - started).total_seconds() > 16 * 3600:   # 서버가 다시 켜졌거나 너무 오래된 운행
        started = None
    events = []
    if started is not None:
        events = session.execute(
            select(SleepEvent).where(SleepEvent.user_id == user.id, SleepEvent.id > last_id)
            .order_by(SleepEvent.id)).scalars().all()
    sleeps = [e for e in events if e.reason != "rest_overdue"]
    rests = []
    timeline = []
    for e in events:
        rep = json.loads(e.report) if e.report else {}
        if rep.get("rest"):
            rests.append(rep["rest"])
        timeline.append({"time": e.created_at.strftime("%H:%M") if e.created_at else "", "stage": int(e.stage or 0),
                         "reason": _REASON_TEXT.get(e.reason or "", "졸음"), "event_id": e.id,
                         **({"rest": rep["rest"]} if rep.get("rest") else {}),
                         **({"wake": rep["wake"]} if rep.get("wake") else {})})
    stats = {
        "drive_min": int((now - started).total_seconds() // 60) if started else 0,
        "sleep_count": len(sleeps),
        "max_stage": max([int(e.stage or 0) for e in sleeps], default=0),
        "rest_count": len(rests),
        "rest_min": sum(int(r.get("minutes") or 0) for r in rests),
        "timeline": timeline,
    }
    # (11/18 팀장) 템플릿 문장으로 바로 답하고, AI 문장은 뒤에서 → 앱이 GET /drive/report/{report_id} 로 받아 바꿔 끼움
    #   (전에는 AI 를 기다렸다 답해서, Gemini 가 느린 날엔 6초 시간 초과로 거의 템플릿이었음)
    ai = agent_service.drive_report_template(stats)
    report_id = uuid.uuid4().hex
    pending = bool(agent_service.USE_REAL_AI)
    with _lock:
        cutoff = time.time() - DRIVE_REPORT_KEEP_SEC
        for k in [k for k, v in _drive_reports.items() if v["at"] < cutoff]:
            del _drive_reports[k]
        _drive_reports[report_id] = {"user_id": user.id, "done": not pending, "at": time.time(), **ai}
    if pending:
        background.add_task(_fill_drive_report, report_id, dict(stats))
    print(f"[detect] {now:%H:%M:%S} u{user.id} 운행 종료 리포트 · {stats['drive_min']}분 · 졸음 {stats['sleep_count']}번 · "
          f"최고 {stats['max_stage']}단계 · 휴식 {stats['rest_count']}번 (템플릿 먼저{' · AI 는 뒤에서' if pending else ''})")
    return {"success": True, "report": {
        **stats, "name": f"{_driver_name(user.name)} 기사님".strip(),
        "started": started.strftime("%H:%M") if started else "", "ended": now.strftime("%H:%M"),
        "summary": ai["summary"], "advice": ai["advice"], "is_real": False,
        "report_id": report_id, "ai_pending": pending}}


@router.post("/drive/rest")
def drive_rest_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """[정차했어요] → 휴식 시작 시각 기록 (서버 시각). 이미 쉬는 중이면 시작 시각은 그대로 두고 남은 시간만 돌려준다
    (앱을 껐다 켜고 휴식 화면을 이어 열어도 15분이 처음부터 다시 시작되지 않게)."""
    elapsed = sleep_state.rest_elapsed_min(user.id)
    if elapsed is None:
        sleep_state.start_rest(user.id)
        elapsed = 0.0
        stop_ev = _open_alert_event(session, user.id)
        if stop_ev is not None:   # (11/26 팀장) AI 보고서 '기사님이 한 일' — [정차했어요] 를 눌러 정차함
            _add_report(stop_ev, "stopped", {"at": datetime.now().strftime("%H:%M")})
            session.commit()
        with _lock:
            if stop_ev is not None:
                _stop_event[user.id] = stop_ev.id
            else:
                _stop_event.pop(user.id, None)
        event = _open_stage2_event(session, user.id)
        with _lock:
            if event:
                _rest_event[user.id] = event.id
            else:
                _rest_event.pop(user.id, None)
    else:
        with _lock:
            if user.id not in _rest_event:   # 서버가 다시 켜져 기억이 비었으면 다시 찾아 둔다
                event = _open_stage2_event(session, user.id)
                if event:
                    _rest_event[user.id] = event.id
    left_sec = max(1, int(round(config.REST_WAIT_SEC - elapsed * 60)))
    return {"success": True, "message": f"{config.REST_WAIT_TEXT} 쉬고 출발하세요", "rest_sec": left_sec,
            "started": datetime.now().strftime("%H:%M")}


@router.post("/drive/resume")
def drive_resume_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """[운행 재개] → 서버 시각으로 15분 검사 → 2단계면 1단계로, 그 경고는 '휴식완료'."""
    elapsed = sleep_state.rest_elapsed_min(user.id)
    if elapsed is None:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "정차 기록이 없습니다. [정차했어요] 를 먼저 눌러 주세요")
    if elapsed * 60 < config.REST_WAIT_SEC:
        left = max(1, int(round(config.REST_WAIT_SEC - elapsed * 60)))
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
    # (11/26) 3단계 등 정차를 남긴 경고가 휴식완료 경고와 다르면 그쪽에도 휴식 기록 (단계 · 상태는 그대로)
    with _lock:
        stop_id = _stop_event.pop(user.id, None)
    stop_ev = session.get(SleepEvent, stop_id) if stop_id and stop_id != (event.id if event else None) else None
    if stop_ev is not None:
        now = datetime.now()
        started = datetime.fromtimestamp(now.timestamp() - elapsed * 60)
        _add_report(stop_ev, "rest", {"started": started.strftime("%H:%M"), "resumed": now.strftime("%H:%M"),
                                      "minutes": int(elapsed)})
        session.commit()

    message = {0: "운행을 재개합니다", 1: "주의 단계로 다시 출발합니다",
               3: "긴급 단계는 관리자가 조치완료를 누르기 전까지 해제되지 않습니다"}.get(stage, "운행을 재개합니다")
    return {"success": True, "stage": stage, "status": _label(stage), "message": message}


# ───────────────────────────────────────────────
# POST /detect — 졸음 의심 사진 1장 확인 (기획안 9장)
# ───────────────────────────────────────────────
BG_SESSION = SessionLocal   # 뒤에서 기록을 채울 때 쓰는 DB 세션 (요청 세션은 답한 뒤 닫힘 · 시험 도구가 바꿔 끼움)


def _fill_ai_report(event_id, user_id, eye_info, facts, rule_stage, location):
    """(11/16 팀장) 경고를 먼저 보낸 뒤 뒤에서 — LLM 상황 설명 → RAG 규정 → Agent 보고서 로 경고 기록 1건을 채운다.
    단계는 바꾸지 않는다 (규칙 단계 그대로, AGENT_MAX_STEP_UP = 0). 실패해도 템플릿 기록이 이미 저장돼 있음.
    (11/26) 얼굴 사진은 관리자 확인용 — AI(Gemini) 에는 보내지 않는다. 경고 수치값 (eye_info · facts) 만 넘긴다."""
    t0 = time.perf_counter()
    try:
        analysis = llm_service.interpret_situation(None, eye_info)
        t1 = time.perf_counter()
        regulations = rag_service.search_regulations(analysis.get("summary", ""))
        t2 = time.perf_counter()
        agent = agent_service.generate_response(eye_info, analysis, regulations, facts, rule_stage, location, user_id)
        t3 = time.perf_counter()
    except Exception as e:
        print(f"[detect] 경고 #{event_id} AI 보고서 실패 → 템플릿 기록 그대로: {type(e).__name__} {str(e)[:120]}")
        return
    db = BG_SESSION()
    try:
        event = db.get(SleepEvent, event_id)
        if event is None:
            return
        try:
            report = json.loads(event.report or "{}")
        except ValueError:
            report = {}
        report.update(agent["report"])   # 상황 · 단계 이유 · 규정 · 권장 조치 · 위치 (eye · facts · 퀴즈 기록은 그대로)
        report["regulations"] = [{"title": r["title"], "source": r["source"]} for r in regulations]
        report["is_real"] = {"llm": bool(analysis.get("is_real")), "rag": any(r.get("is_real") for r in regulations),
                             "agent": bool(agent["is_real"]), "driver_voice": False}
        event.summary = (analysis.get("summary") or event.summary or "")[:255]
        # (11/18 팀장) guidance(기사님께 전달한 안내)는 덮어쓰지 않음 — 기사가 실제로 들은 문장 그대로
        event.report = json.dumps(report, ensure_ascii=False)
        db.commit()
        print(f"[detect] 경고 #{event_id} AI 보고서 채움 (뒤에서) · LLM {t1 - t0:.1f}초 · RAG {t2 - t1:.1f}초 · "
              f"Agent {t3 - t2:.1f}초 ({'AI' if agent['is_real'] else '규칙'})")
    finally:
        db.close()


@router.post("/detect")
async def detect_handler(
    file: UploadFile | None = File(None),  # 없으면 = 고개를 떨궈 얼굴을 놓친 채 감김 (eye_monitor) → 앱 판단대로
    reason: str = Form(""),                # microsleep / perclos / "" (사진 1장 테스트)
    closed_sec: str = Form(""),
    perclos: str = Form(""),
    eye_open_prob: str = Form(""),
    latitude: str = Form(""),
    longitude: str = Form(""),
    background: BackgroundTasks = None,
    session: Session = Depends(get_session),
    user: User = Depends(get_current_user),
):
    # ① 로그인 · 사진 확인 (검사하는 동안만 임시 보관)
    reason = reason if reason in ("microsleep", "perclos", "half") else ""   # half = 반쯤 감은 눈 확인 (10초마다 1장, 11/10)
    if file is None and not reason:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "사진이 필요합니다 (사진 없이는 운행 중 졸음 의심만 보낼 수 있음)")
    if reason and sleep_state.get_state(user.id).get("rest_started_at") is not None:
        # 휴식 중 — 운행 중 졸음 의심은 세지 않는다 (사진도 받지 않음). 사진 1장 테스트(reason 없음)는 그대로 판정
        stage = int(sleep_state.get_stage(user.id))
        print(f"[detect] {datetime.now():%H:%M:%S} u{user.id} {reason} → 휴식 중이라 무시 (단계 {stage})")
        return {"success": True, "face_found": False, "ear": None, "eye_closed_prob": None, "eye_open_prob": None,
                "method": "mlkit", "perclos": None, "ear_threshold": None, "is_sleep": False, "reason": "",
                "stage": stage, "status": _label(stage), "summary": "휴식 중", "guidance": "", "driver_voice": "",
                "sleep_count_10min": int(sleep_state.facts(user.id)["sleep_count_10min"]),
                "voice_quiz": None, "regulations": [], "event_id": None}
    t_start = time.perf_counter()   # 단계별 걸린 시간 (응답이 느릴 때 어디서 걸렸는지 터미널로 보기, 11/05)
    # 반쯤 감은 눈 확인 (11/10 팀장) — 앱이 눈 뜬 상태에서 10초마다 보낸 사진 1장
    #   서버 EAR < 출발 전 뜬 눈 EAR × 0.85 (face_service.check_half) → 최근 4번 중 3번이면 피로 확정 (sleep_state.add_half)
    #   확정 전에는 조용히 응답하고 사진은 바로 지움 (경고 · 취소 글자 없음). 확정되면 아래 PERCLOS 확정과 같은 길 (report 에 trigger half)
    half = None
    tmp_path = None
    if reason == "half":
        if file is None:
            raise HTTPException(status.HTTP_400_BAD_REQUEST, "반쯤 감은 눈 확인에는 사진이 필요합니다")
        tmp_path = await _save_upload(file, config.UPLOAD_TMP_DIR, f"u{user.id}h")
        half = await run_in_threadpool(face_service.check_half, tmp_path, user.id)
        if not sleep_state.add_half(user.id, half["is_half"]):
            _remove(tmp_path)
            stage = int(sleep_state.get_stage(user.id))
            return {"success": True, "face_found": half["ear"] is not None, "ear": _r(half["ear"]), "eye_closed_prob": None,
                    "eye_open_prob": None, "method": "ear", "perclos": None, "ear_threshold": _r(half["baseline"]),
                    "is_sleep": False, "reason": "", "stage": stage, "status": _label(stage), "summary": "", "guidance": "",
                    "driver_voice": "", "sleep_count_10min": int(sleep_state.facts(user.id)["sleep_count_10min"]),
                    "voice_quiz": None, "regulations": [], "event_id": None}
        print(f"[detect] {datetime.now():%H:%M:%S} u{user.id} half → 반쯤 감은 눈 피로 확정 (EAR {half['ear']} < "
              f"평소 {half['baseline']} × 0.85) → PERCLOS 로 확정")
        reason = "perclos"
    elif file is not None:
        tmp_path = await _save_upload(file, config.UPLOAD_TMP_DIR, f"u{user.id}")
    closed, pc, open_prob = _num(closed_sec), _num(perclos), _num(eye_open_prob)
    lat, lng = _num(latitude), _num(longitude)

    # ② 확인 판정 (MediaPipe EAR / CNN)
    #   사진 없음 = 서버가 볼 얼굴이 없음 → '얼굴 없음' 과 같이 앱 판단대로 확정 (method mlkit, 기획안 5-2)
    if tmp_path is None:
        eye = {"face_found": False, "ear": None, "eye_closed_prob": None, "method": "mlkit",
               "ear_threshold": None, "is_sleep": True}
    else:
        eye = await run_in_threadpool(face_service.check_eyes, tmp_path, user.id, reason or None)
    t_eye = time.perf_counter()
    base = {
        "success": True, "face_found": bool(eye.get("face_found")), "ear": _r(eye.get("ear")),
        "eye_closed_prob": _r(eye.get("eye_closed_prob")), "eye_open_prob": _r(open_prob),
        "method": eye.get("method") or "ear", "perclos": _r(pc), "ear_threshold": _r(eye.get("ear_threshold")),
    }
    with _lock:
        _method_counts[base["method"]] = _method_counts.get(base["method"], 0) + 1
    # 판정 한 줄 (시연 폰 시험에서 왜 확정 · 취소됐는지 터미널로 보기, 11/03) — 사진 · 개인정보는 찍지 않음
    print(f"[detect] {datetime.now():%H:%M:%S} u{user.id} {reason or '사진테스트'} closed={closed} perclos={pc} "
          f"app_open={open_prob} photo={'Y' if tmp_path else 'N'} → face={base['face_found']} ear={base['ear']}"
          f"(기준 {base['ear_threshold']}) cnn={base['eye_closed_prob']} method={base['method']} "
          f"{'확정' if eye.get('is_sleep') else '취소'} 단계 {sleep_state.get_stage(user.id)} 눈판정 {t_eye - t_start:.1f}초")
    if not eye.get("is_sleep"):             # 취소 → AI 를 부르지 않고 바로 응답, 사진은 지움 (개인정보)
        _hold_photo(user.id, tmp_path)      # (11/25) 단, 숙인 채 사진 없이 다시 오면 붙이려고 HELD_PHOTO_SEC 동안만 들고 있음
        stage = int(sleep_state.get_stage(user.id))
        return {**base, "is_sleep": False, "reason": "", "stage": stage, "status": _label(stage),
                "summary": "", "guidance": "", "driver_voice": "",
                "sleep_count_10min": int(sleep_state.facts(user.id)["sleep_count_10min"]),
                "voice_quiz": None, "regulations": [], "event_id": None}

    # ②-1 (11/12 팀장 결정 · A sleep_state.try_pre_warn) 운행 중 첫 졸음 = 예비 경고
    #   0단계 · 이번 운행 처음이면 단계 · 10분 졸음 횟수를 건드리지 않고 알림만 (AI 안 부름 → 빠르게, 퀴즈 없음)
    #   반쯤 감은 눈 확정(half)은 건너뜀 — 이미 약 30초를 모은 확정이라 바로 1단계 (try_pre_warn 이 False)
    #   DB 에 남기지 않음 (운행 기록 · 관리자 경고 목록 · 통계에 0단계가 섞임) → 사진도 지움. 서버 로그 한 줄만
    #   계속 감고 있으면 앱 eye_monitor 가 6초에 다시 보냄 → 그때는 아래 ③ 으로 1단계. 사진 1장 테스트(reason 없음)는 예비 경고 없음
    if config.PRE_WARN_ON and reason and sleep_state.try_pre_warn(user.id, "half" if half is not None else reason):  # 11/15 기본 꺼짐
        _remove(tmp_path)
        stage = int(sleep_state.get_stage(user.id))
        print(f"[detect]   → 예비 경고 (운행 중 첫 졸음 · 단계 {stage} 그대로 · 기록 안 남김) · 합계 {time.perf_counter() - t_start:.1f}초")
        return {**base, "is_sleep": False, "pre_warning": True, "reason": "pre_warning", "stage": stage, "status": _label(stage),
                "summary": "", "guidance": "", "driver_voice": PRE_WARN_VOICE,
                "sleep_count_10min": int(sleep_state.facts(user.id)["sleep_count_10min"]),
                "voice_quiz": None, "regulations": [], "event_id": None}

    # ③ 졸음 기록 → 규칙 단계 (사진 1장 테스트에서 감음이면 미세수면으로 기록)
    reason = reason or "microsleep"
    reset_mark = sleep_state.reset_count(user.id)   # AI 처리 중에 관리자가 해제하는지 보려고 기억 (11/05)
    prev_stage = int(sleep_state.get_stage(user.id))
    rule_stage = int(sleep_state.add_sleep(user.id, reason, closed or 0.0))
    f = sleep_state.facts(user.id)
    facts = {"sleep_count_10min": int(f["sleep_count_10min"]), "last_closed_sec": float(f["last_closed_sec"] or 0),
             "drive_min": drive_timer.drive_min(user.id)}
    # (11/12 팀장) 10분 횟수보다 단계가 높으면 = 주의(1단계)에서 다시 졸아 올라감 (휴식 뒤 1단계 등).
    #   이때 "10분 안 첫 번째 졸음"이라고 하면 2단계와 말이 안 맞아서, 횟수 대신 이 이유를 문장에 쓴다
    #   (11/16) 2단계에서 또 졸아 3단계가 된 경우는 "휴식 권고 단계에서 다시 졸음"
    stage_note = (f"{config.STAGE_LABELS.get(prev_stage, '주의')} 단계에서 다시 졸음"
                  if rule_stage > min(3, facts["sleep_count_10min"]) and prev_stage >= 1 else "")
    if stage_note:
        facts["stage_note"] = stage_note
    eye_info = {"reason": reason, "closed_sec": closed, "perclos": pc, "eye_open_prob": open_prob,
                "ear": eye.get("ear"), "method": base["method"], "sleep_count_10min": facts["sleep_count_10min"],
                "stage_note": stage_note}

    # ④ 단계 · 음성 = 규칙만 → 바로 답한다 (11/16 팀장: 운전자를 즉시 깨우는 게 목표)
    #   전에는 2단계부터 LLM → RAG → Agent 를 다 기다린 뒤 답해서 경고가 3~7초 늦었고, Agent 가 단계를 +1 올리기도 했음
    #   이제 LLM · RAG · Agent 는 답한 뒤 뒤에서 돌아 이 경고 기록의 요약 · 안내문 · 관리자 보고서만 채운다 (_fill_ai_report)
    #   1단계는 뒤에서도 AI 를 부르지 않음 (첫 졸음 · 기록 요약은 숫자 템플릿)
    t_ai = time.perf_counter()
    location = f"{lat:.5f}, {lng:.5f}" if lat is not None and lng is not None else ""
    analysis = llm_service.template_summary(eye_info)
    t_llm = t_rag = time.perf_counter()
    regulations = []
    agent = agent_service.rule_response(eye_info, analysis, regulations, facts, rule_stage, location)
    t_agent = time.perf_counter()
    # AI 처리 중에 관리자가 [조치완료] 했으면 단계를 다시 올리지 않는다 — 경고 기록은 '조치완료' 로 남김 (11/05)
    released = sleep_state.reset_count(user.id) != reset_mark
    if released:
        stage = int(sleep_state.get_stage(user.id))
    else:
        stage = int(sleep_state.set_stage(user.id, agent["stage"]))   # 올리기만 (sleep_state 가 보증)
    print(f"[detect]   → 10분 졸음 {facts['sleep_count_10min']}번 · 규칙 {rule_stage}단계 → 최종 {stage}단계 (바로 답함)"
          f"{' (관리자 해제됨)' if released else ''}")

    # ⑦ 저장 — 확정 사진만 uploads/events/ 로, DB 1줄 (사진 없이 온 경고는 photo_path 없음 → 관리자 웹 '사진 없음')
    #   (11/25) 사진 없이 온 경고(숙인 채 재전송)면 방금 취소된 숙임 사진을 붙인다 (_take_held_photo, 60초 안)
    held_photo = False
    if tmp_path is None:
        tmp_path = _take_held_photo(user.id)
        held_photo = tmp_path is not None
    photo_path = None
    if tmp_path is not None:
        os.makedirs(config.UPLOAD_EVENT_DIR, exist_ok=True)
        photo_name = os.path.basename(tmp_path)
        shutil.move(tmp_path, os.path.join(config.UPLOAD_EVENT_DIR, photo_name))
        photo_path = f"uploads/events/{photo_name}"
    report = {
        **agent["report"],
        "eye": {"closed_sec": closed, "perclos": pc, "eye_open_prob": open_prob, "ear": eye.get("ear"),
                "photo": tmp_path is not None,
                **({"photo_note": "처음 의심 때 사진 (고개 숙임)"} if held_photo else {}),
                **({"trigger": "half", "half_ear": half["ear"], "half_baseline": half["baseline"]} if half else {})},
        "driving_quiz": [],
        "facts": facts,
        "is_real": {"llm": bool(analysis.get("is_real")), "rag": any(r.get("is_real") for r in regulations),
                    "agent": bool(agent["is_real"]), "driver_voice": bool(agent["voice_is_real"])},
    }
    # (11/18 팀장) 경고 기록의 '기사님께 전달한 안내' = 기사가 실제로 들은 문장 (이름 빼고)
    #   1단계: 앱 고정 문장 (drive_screen._stage1Voice) · 2 · 3단계: 아래 driver_voice 의 문장. Agent 가 덮어쓰지 않음
    delivered = STAGE1_DELIVERED if stage <= 1 else agent["driver_voice"]
    event = SleepEvent(
        user_id=user.id, stage=int(agent["stage"]) if released else stage, ear=eye.get("ear"),
        eye_closed_prob=eye.get("eye_closed_prob"),
        method=base["method"], reason=reason, perclos=pc,
        summary=(analysis.get("summary") or "")[:255], guidance=delivered[:255],
        report=json.dumps(report, ensure_ascii=False), photo_path=photo_path,
        latitude=lat, longitude=lng, status="조치완료" if released else "미확인",
    )
    session.add(event)
    session.commit()
    session.refresh(event)

    # ⑧ 운전 중 음성 퀴즈 (경고를 저장한 뒤 → event_id 를 함께 기억)
    #   (11/18 팀장) 2분 간격 뺌 — 목적은 깨우기. 2단계에 들어갈 때마다 반드시 낸다
    #   (질문 폭탄 걱정 없음: 2단계에서 또 졸면 퀴즈 없이 바로 3단계 · 3단계는 [깨어 있어요] 버튼)
    voice_quiz = None
    # (11/15 팀장) 기사에게는 ① 정신 차리세요(예비 · 1단계) ② 쉬어 가세요(2) ③ 지금 멈추세요(3) — 퀴즈는 2단계부터
    if config.QUIZ_MODE == "voice" and not released and stage == 2:  # 3단계는 [깨어 있어요] 버튼 (11/15)
        voice_quiz = voice_quiz_service.make_quiz(user.id, event_id=event.id)

    # ⑨ 2단계부터 — 답한 뒤 뒤에서 LLM · RAG · Agent 로 이 기록의 요약 · 안내문 · 관리자 보고서를 채움 (단계는 그대로)
    if rule_stage >= 2 and background is not None:
        background.add_task(_fill_ai_report, event.id, user.id, eye_info, facts, rule_stage, location)   # 사진은 안 넘김 (11/26)

    t_end = time.perf_counter()
    print(f"[detect]   → 걸린 시간: 눈판정 {t_eye - t_start:.1f}초 · 저장 · 퀴즈 {t_end - t_agent:.1f}초 · "
          f"합계 {t_end - t_start:.1f}초{' (AI 보고서는 뒤에서)' if rule_stage >= 2 else ''}")

    return {
        **base, "is_sleep": True, "reason": reason, "stage": stage, "status": _label(stage),
        "summary": event.summary or "", "guidance": delivered,
        # (11/16 팀장) 음성은 '이름 + 사실 하나 + 행동 하나' 한 문장 (약 4초)
        "driver_voice": f"{_driver_name(user.name) or '기사'}님, {agent['driver_voice']}",
        "sleep_count_10min": facts["sleep_count_10min"], "voice_quiz": voice_quiz,
        "regulations": [{"title": r["title"], "source": r["source"], "content": r["content"]} for r in regulations],
        "event_id": event.id,
    }