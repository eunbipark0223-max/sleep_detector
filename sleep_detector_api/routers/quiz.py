# ═══════════════════════════════════════════════════════════════
# routers/quiz.py — 운전 중 음성 퀴즈 채점 API
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1
#
# [이 파일이 하는 일]
#   - POST /quiz/answer — VoiceQuizAnswer 를 받아 voice_quiz_service 로 채점
#   -   정답 → 단계 그대로  /  1번 실패 → 응답에 next_quiz (같은 유형 새 문제)
#   -   2번 실패 → 단계 +1 (최대 3) · 관리자 알림 · reason = no_response 경고 1줄 저장
#   - POST /quiz/no-response-photo — (11/26 팀장) 2번째 퀴즈가 끝난 순간 앱이 찍은 사진을 그 no_response 경고에 붙임
#       (11/26 시연 폰에서 2번 확인 — 새 사진 저장 · 관리자 웹 '2번째 퀴즈가 끝난 뒤 사진')
#   - 채점 결과는 그 경고의 report.driving_quiz 에 덧붙임
#   - 응답: success · passed · next_quiz · stage_up · stage · status · message (기획안 9-6) · no_response_event_id (2번 실패일 때만)
#
# [주의]
#   - 없는 quiz_id 면 404 → 앱은 퀴즈만 끝냄
#   - 통과해도 단계를 내리지 않는다 (기획안 8-1)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

# [연결 약속 — 다른 사람 파일의 이름]
#   - voice_quiz_service (B): get_quiz(quiz_id) → 문제 정보(정답 빼고, user_id · type · attempt · event_id) / 없으면 None
#                             check_answer(quiz_id, answer_text) → passed (없으면 KeyError) · make_quiz(user_id, qtype, event_id)
#   - sleep_state (A): get_stage · set_stage(올리기만)
#   - 실패 횟수는 퀴즈의 attempt(1 · 2번째)로 센다 — 경고마다 새로 시작 (지난 경고의 실패가 이어지지 않게)

import json
import os
from datetime import datetime, timedelta

from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy import select
from sqlalchemy.orm import Session

import config
from auth.jwt import get_current_user
from database.db_connection import get_session
from models.models import SleepEvent, User
from schema.request import VoiceQuizAnswer
from services import sleep_state, voice_quiz_service

router = APIRouter(tags=["운전 중 음성 퀴즈"])

# 통과 음성은 지금 단계의 안내와 같은 방향으로 (1단계는 쉼터로 안 가도 됨, 3단계는 정차 안내 뒤에 '운행하세요' 가 나오면 안 됨)
MSG_PASS = {
    1: "확인했어요. 안전 운행하세요.",
    2: "확인했어요. 쉼터까지 조심히 가세요.",
    3: "확인했어요. 안전한 곳에 정차해 주세요.",
}
MSG_PASS_DEFAULT = MSG_PASS[1]  # 퀴즈 중에 해제되어 0단계인 경우
MSG_RETRY = "한 번 더 물어볼게요."
MSG_NO_RESPONSE = "응답이 없어 관리자에게 알렸어요. 안전한 곳에 정차해 주세요."


def _label(stage):
    return config.STAGE_LABELS.get(int(stage), "")


def _append_quiz_record(session: Session, event_id, user_id, record):
    """채점 결과를 그 경고의 report.driving_quiz 에 덧붙인다."""
    event = session.get(SleepEvent, event_id) if event_id else None
    if event is None or event.user_id != user_id:
        return
    report = json.loads(event.report) if event.report else {}
    report.setdefault("driving_quiz", []).append(record)
    event.report = json.dumps(report, ensure_ascii=False)


@router.post("/quiz/answer")
def quiz_answer_handler(
    body: VoiceQuizAnswer,
    session: Session = Depends(get_session),
    user: User = Depends(get_current_user),
):
    quiz = voice_quiz_service.get_quiz(body.quiz_id)
    if quiz is None or quiz.get("user_id") != user.id:          # 없는 문제 · 남의 문제
        raise HTTPException(status.HTTP_404_NOT_FOUND, "없는 퀴즈입니다 (이미 채점했거나 서버가 다시 시작됨)")
    try:
        passed = bool(voice_quiz_service.check_answer(body.quiz_id, body.answer_text or ""))
    except KeyError:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "없는 퀴즈입니다 (이미 채점했거나 서버가 다시 시작됨)")

    attempt = int(quiz.get("attempt") or 1)
    event_id = quiz.get("event_id")
    _append_quiz_record(session, event_id, user.id, {
        "type": quiz.get("type"), "asked": quiz.get("display"), "heard": body.answer_text or "",
        "passed": passed, "answer_sec": body.answer_sec, "attempt": attempt,
    })

    stage = int(sleep_state.get_stage(user.id))
    no_response = None
    next_quiz, stage_up, message = None, False, MSG_PASS.get(stage, MSG_PASS_DEFAULT)

    if not passed and attempt < config.VOICE_QUIZ_MAX_TRIES:     # 1번 실패 → 같은 유형 새 문제
        next_quiz = voice_quiz_service.make_quiz(user.id, qtype=quiz.get("type"), event_id=event_id)
        message = MSG_RETRY
    elif not passed:                                             # 2번 실패 → 단계 +1 · 관리자 알림
        new_stage = int(sleep_state.set_stage(user.id, stage + 1))
        stage_up, stage = new_stage > stage, new_stage
        message = MSG_NO_RESPONSE
        # (11/26 팀장) 사진은 2번째 퀴즈가 끝난 순간 앱이 찍어 /quiz/no-response-photo 로 따로 보냄 (3단계 응답이 늦지 않게)
        #   그 사진이 오기 전 · 못 왔을 때는 아래처럼 (11/23 팀장) 퀴즈를 내게 만든 2단계 경고의 사진 — 같은 파일을 가리키기만
        #   30일 자동 삭제(photo_cleanup)는 파일이 이미 없어도 photo_path 만 비우므로 두 경고가 같은 파일을 써도 괜찮음
        src = session.get(SleepEvent, event_id) if event_id else None
        src_photo = src.photo_path if src is not None and src.user_id == user.id else None
        if not src_photo:   # (11/25 팀장) 그 경고에 사진이 없으면 같은 기사의 최근 15분 안 경고 사진 (관리자 웹에 늘 사진)
            src_photo = session.scalar(
                select(SleepEvent.photo_path)
                .where(SleepEvent.user_id == user.id, SleepEvent.photo_path.is_not(None),
                       SleepEvent.created_at >= datetime.now() - timedelta(minutes=15))
                .order_by(SleepEvent.created_at.desc()).limit(1))
        no_response = SleepEvent(
            user_id=user.id, stage=stage, reason="no_response", method="mlkit", status="미확인", photo_path=src_photo,
            summary=f"운전 중 음성 퀴즈에 {config.VOICE_QUIZ_MAX_TRIES}번 답하지 못했습니다.",
            guidance=MSG_NO_RESPONSE,
            report=json.dumps({"situation": "운전 중 음성 퀴즈 응답 없음", "stage_reason": "퀴즈 2번 실패로 한 단계 올림",
                               "recommended_action": "즉시 기사에게 연락해 상태 확인", "from_event_id": event_id},
                              ensure_ascii=False),
        )
        session.add(no_response)
    session.commit()

    return {"success": True, "passed": passed, "next_quiz": next_quiz, "stage_up": stage_up,
            "stage": stage, "status": _label(stage), "message": message,
            "no_response_event_id": no_response.id if no_response is not None else None}


@router.post("/quiz/no-response-photo")
async def no_response_photo_handler(
    event_id: int = Form(...),
    file: UploadFile = File(...),
    session: Session = Depends(get_session),
    user: User = Depends(get_current_user),
):
    """(11/26 팀장) 2번째 퀴즈가 끝난 순간의 사진 1장 → 그 '퀴즈 응답 없음' 경고의 사진으로 바꾼다 (경고마다 한 번만, 본인 것만)."""
    from routers.detect import _save_upload   # 사진 확인 · 저장은 /detect 와 같은 코드
    event = session.get(SleepEvent, event_id)
    if event is None or event.user_id != user.id or event.reason != "no_response":
        raise HTTPException(status.HTTP_404_NOT_FOUND, "없는 경고입니다")
    if json.loads(event.report or "{}").get("photo_at") == "after_quiz":
        raise HTTPException(status.HTTP_409_CONFLICT, "이미 사진이 있습니다")
    path = await _save_upload(file, config.UPLOAD_EVENT_DIR, f"u{user.id}q")
    try:
        session.refresh(event)                # 사진을 받는 사이 [깨어 있어요] 기록이 들어왔을 수 있음
        report = json.loads(event.report or "{}")
        report["photo_at"] = "after_quiz"
        event.report = json.dumps(report, ensure_ascii=False)
        event.photo_path = f"uploads/events/{os.path.basename(path)}"   # 2단계 경고의 사진 파일은 그 경고 것이라 지우지 않음
        session.commit()
    except Exception:
        os.remove(path)
        raise
    return {"success": True, "event_id": event.id}
