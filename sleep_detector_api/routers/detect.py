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
#   - 숫자는 _normalize 로 int / float 확정해서 보냄 (수업에서 배운 '5' 문자열 사고 방지)
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

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from fastapi.concurrency import run_in_threadpool
from sqlalchemy import select
from sqlalchemy.orm import Session

import config
from fastapi.security import HTTPAuthorizationCredentials

from auth.jwt import bearer, get_current_user, refreshed_token
from database.db_connection import get_session
from models.models import SleepEvent, User
from schema.request import DrivePing
from services import (agent_service, drive_timer, face_service, llm_service, rag_service, sleep_state,
                      voice_quiz_service)

router = APIRouter(tags=["운행 · 감지"])

ACTIVE_PING_SEC = 5 * 60   # 앱이 꺼진 지 이 시간 안이면 홈 화면이 '진행 중인 운행' 으로 봄 (2 · 3단계 · 휴식 중은 시간과 상관없이)
ALLOWED_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
MAX_UPLOAD_BYTES = 10 * 1024 * 1024

# 개인 기준 측정: 사진을 CALIB_FRAMES 장 모을 때까지 기사별로 잠깐 보관 (끝나면 지움)
_calib_photos = {}       # user_id → [임시 사진 경로, ...]
# [정차했어요] 때 휴식완료로 바꿀 2단계 경고 번호
_rest_event = {}         # user_id → event_id
# 운전 중 음성 퀴즈 최소 간격 (VOICE_QUIZ_GAP_SEC) — 마지막으로 낸 시각
_last_quiz_at = {}       # user_id → time.time()
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


def _open_stage2_event(session: Session, user_id: int) -> Optional[SleepEvent]:
    """[정차했어요] 때 휴식완료로 바꿀 경고 — 가장 최근의 아직 처리 안 된 2단계 경고."""
    return session.scalar(
        select(SleepEvent)
        .where(SleepEvent.user_id == user_id, SleepEvent.stage == 2, SleepEvent.status.in_(["미확인", "확인"]))
        .order_by(SleepEvent.id.desc())
    )


def method_counts() -> dict:
    """서버를 켠 뒤 판정 방식별 건수 (main.py GET /health)"""
    with _lock:
        return dict(_method_counts)


# ───────────────────────────────────────────────
# 운행 API
# ───────────────────────────────────────────────
@router.post("/drive/start")
def drive_start_handler(user: User = Depends(get_current_user)):
    # 2 · 3단계는 유지 — 다시 시작으로 경고를 끌 수 없게 (기획안 8장, 11/03 A start_drive)
    stage = int(sleep_state.start_drive(user.id)["stage"])
    drive_timer.start(user.id)
    with _lock:
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
    authorization: HTTPAuthorizationCredentials | None = Depends(bearer),
):
    """30초마다. 단계(1단계 자동 해제 · 조치완료 반영) · 연속 운전 시간 · 휴게 알림 · (토큰이 곧 끝나면) 새 토큰."""
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

    out = {"stage": stage, "status": _label(stage), "drive_min": int(t["drive_min"]),
           "rest_due": bool(t["rest_due"]), "rest_message": t["rest_message"]}
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
            "rest_left_sec": max(0, int(round(config.REST_MIN * 60 - elapsed * 60))) if resting else 0,
            "drive_min": int(drive_timer.drive_min(user.id)), "summary": summary, "guidance": guidance}


@router.post("/drive/end")
def drive_end_handler(user: User = Depends(get_current_user)):
    """[운행 종료] — 단계는 그대로(2 · 3단계는 계속 이어짐), 진행 중인 운행만 끝냄."""
    drive_timer.end(user.id)
    return {"success": True}


@router.post("/drive/rest")
def drive_rest_handler(session: Session = Depends(get_session), user: User = Depends(get_current_user)):
    """[정차했어요] → 휴식 시작 시각 기록 (서버 시각). 이미 쉬는 중이면 시작 시각은 그대로 두고 남은 시간만 돌려준다
    (앱을 껐다 켜고 휴식 화면을 이어 열어도 15분이 처음부터 다시 시작되지 않게)."""
    elapsed = sleep_state.rest_elapsed_min(user.id)
    if elapsed is None:
        sleep_state.start_rest(user.id)
        elapsed = 0.0
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
    left_sec = max(1, int(round(config.REST_MIN * 60 - elapsed * 60)))
    return {"success": True, "message": f"{config.REST_MIN}분 쉬고 출발하세요", "rest_sec": left_sec,
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


# ───────────────────────────────────────────────
# POST /detect — 졸음 의심 사진 1장 확인 (기획안 9장)
# ───────────────────────────────────────────────
@router.post("/detect")
async def detect_handler(
    file: UploadFile | None = File(None),  # 없으면 = 고개를 떨궈 얼굴을 놓친 채 감김 (eye_monitor) → 앱 판단대로
    reason: str = Form(""),                # microsleep / perclos / "" (사진 1장 테스트)
    closed_sec: str = Form(""),
    perclos: str = Form(""),
    eye_open_prob: str = Form(""),
    latitude: str = Form(""),
    longitude: str = Form(""),
    session: Session = Depends(get_session),
    user: User = Depends(get_current_user),
):
    # ① 로그인 · 사진 확인 (검사하는 동안만 임시 보관)
    reason = reason if reason in ("microsleep", "perclos") else ""
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
    tmp_path = await _save_upload(file, config.UPLOAD_TMP_DIR, f"u{user.id}") if file is not None else None
    closed, pc, open_prob = _num(closed_sec), _num(perclos), _num(eye_open_prob)
    lat, lng = _num(latitude), _num(longitude)

    # ② 확인 판정 (MediaPipe EAR / CNN)
    #   사진 없음 = 서버가 볼 얼굴이 없음 → '얼굴 없음' 과 같이 앱 판단대로 확정 (method mlkit, 기획안 5-2)
    if tmp_path is None:
        eye = {"face_found": False, "ear": None, "eye_closed_prob": None, "method": "mlkit",
               "ear_threshold": None, "is_sleep": True}
    else:
        eye = await run_in_threadpool(face_service.check_eyes, tmp_path, user.id, reason or None)
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
          f"{'확정' if eye.get('is_sleep') else '취소'} 단계 {sleep_state.get_stage(user.id)}")
    if not eye.get("is_sleep"):             # 취소 → AI 를 부르지 않고 바로 응답, 사진은 지움 (개인정보)
        _remove(tmp_path)
        stage = int(sleep_state.get_stage(user.id))
        return {**base, "is_sleep": False, "reason": "", "stage": stage, "status": _label(stage),
                "summary": "", "guidance": "", "driver_voice": "",
                "sleep_count_10min": int(sleep_state.facts(user.id)["sleep_count_10min"]),
                "voice_quiz": None, "regulations": [], "event_id": None}

    # ③ 졸음 기록 → 규칙 단계 (사진 1장 테스트에서 감음이면 미세수면으로 기록)
    reason = reason or "microsleep"
    reset_mark = sleep_state.reset_count(user.id)   # AI 처리 중에 관리자가 해제하는지 보려고 기억 (11/05)
    rule_stage = int(sleep_state.add_sleep(user.id, reason, closed or 0.0))
    f = sleep_state.facts(user.id)
    facts = {"sleep_count_10min": int(f["sleep_count_10min"]), "last_closed_sec": float(f["last_closed_sec"] or 0),
             "drive_min": drive_timer.drive_min(user.id)}
    eye_info = {"reason": reason, "closed_sec": closed, "perclos": pc, "eye_open_prob": open_prob,
                "ear": eye.get("ear"), "method": base["method"], "sleep_count_10min": facts["sleep_count_10min"]}

    # ④ LLM 요약  ⑤ RAG 규정  ⑥ Agent (모두 실패하면 가짜로 — 각 서비스가 is_real 로 알려 줌)
    analysis = await run_in_threadpool(llm_service.interpret_situation, tmp_path, eye_info)
    regulations = await run_in_threadpool(rag_service.search_regulations, analysis.get("summary", ""))
    location = f"{lat:.5f}, {lng:.5f}" if lat is not None and lng is not None else ""
    agent = await run_in_threadpool(agent_service.generate_response, eye_info, analysis, regulations, facts,
                                    rule_stage, location, user.id)
    # AI 처리 중에 관리자가 [조치완료] 했으면 단계를 다시 올리지 않는다 — 경고 기록은 '조치완료' 로 남김 (11/05)
    released = sleep_state.reset_count(user.id) != reset_mark
    if released:
        stage = int(sleep_state.get_stage(user.id))
    else:
        stage = int(sleep_state.set_stage(user.id, agent["stage"]))   # 올리기만 (sleep_state 가 보증)
    print(f"[detect]   → 10분 졸음 {facts['sleep_count_10min']}번 · 규칙 {rule_stage}단계 · Agent {agent['stage']}단계 "
          f"({'AI' if agent['is_real'] else '규칙'}) → 최종 {stage}단계{' (처리 중 관리자 해제)' if released else ''}")

    # ⑦ 저장 — 확정 사진만 uploads/events/ 로, DB 1줄 (사진 없이 온 경고는 photo_path 없음 → 관리자 웹 '사진 없음')
    photo_path = None
    if tmp_path is not None:
        os.makedirs(config.UPLOAD_EVENT_DIR, exist_ok=True)
        photo_name = os.path.basename(tmp_path)
        shutil.move(tmp_path, os.path.join(config.UPLOAD_EVENT_DIR, photo_name))
        photo_path = f"uploads/events/{photo_name}"
    report = {
        **agent["report"],
        "eye": {"closed_sec": closed, "perclos": pc, "eye_open_prob": open_prob, "ear": eye.get("ear"),
                "photo": tmp_path is not None},
        "driving_quiz": [],
        "facts": facts,
        "is_real": {"llm": bool(analysis.get("is_real")), "rag": any(r.get("is_real") for r in regulations),
                    "agent": bool(agent["is_real"]), "driver_voice": bool(agent["voice_is_real"])},
    }
    event = SleepEvent(
        user_id=user.id, stage=int(agent["stage"]) if released else stage, ear=eye.get("ear"),
        eye_closed_prob=eye.get("eye_closed_prob"),
        method=base["method"], reason=reason, perclos=pc,
        summary=(analysis.get("summary") or "")[:255], guidance=agent["guidance"][:255],
        report=json.dumps(report, ensure_ascii=False), photo_path=photo_path,
        latitude=lat, longitude=lng, status="조치완료" if released else "미확인",
    )
    session.add(event)
    session.commit()
    session.refresh(event)

    # ⑧ 운전 중 음성 퀴즈 (경고를 저장한 뒤 → event_id 를 함께 기억, 최소 간격 VOICE_QUIZ_GAP_SEC)
    voice_quiz = None
    if config.QUIZ_MODE == "voice" and not released:
        now = time.time()
        with _lock:
            due = now - _last_quiz_at.get(user.id, 0) >= config.VOICE_QUIZ_GAP_SEC
            if due:
                _last_quiz_at[user.id] = now
        if due:
            voice_quiz = voice_quiz_service.make_quiz(user.id, event_id=event.id)

    return {
        **base, "is_sleep": True, "reason": reason, "stage": stage, "status": _label(stage),
        "summary": event.summary or "", "guidance": agent["guidance"], "driver_voice": agent["driver_voice"],
        "sleep_count_10min": facts["sleep_count_10min"], "voice_quiz": voice_quiz,
        "regulations": [{"title": r["title"], "source": r["source"], "content": r["content"]} for r in regulations],
        "event_id": event.id,
    }