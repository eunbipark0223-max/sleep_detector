# ═══════════════════════════════════════════════════════════════
# schema/request.py — 앱이 보내는 JSON 모양 (Pydantic)
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0
# 수업 원본: road_hazard_api/schema/request.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - 로그인 · 회원가입 · 채팅 · StatusUpdate — 수업 그대로 (StatusUpdate 설명만 졸음용 상태로)
#   - VoiceQuizAnswer — quiz_id · answer_text(STT 글자, 무응답이면 '') · answer_sec(무응답이면 null)
#   - DrivePing — perclos (기록용)
#
# [주의]
#   - 수업용 DirectReport · ReportSubmit 은 지운다
#   - /detect 는 사진 업로드라 JSON 이 아니라 Form 으로 받음 (detect.py)
#
# [연결 약속 — 수업 파일이 이 저장소에 없어서 D 가 정한 것. user.py · chat.py 가 이 이름으로 부르는지 확인]
#   - SignupRequest(email · password · name) · LoginRequest(email · password) · GoogleLoginRequest(email · name · firebase_uid) · ChatRequest(message · history)
#   - 10.14 팀장: 수업 앱이 보내는 모양에 맞춰 GoogleLoginRequest · 비밀번호 규칙 · ChatRequest.history 를 수업 그대로 되돌림
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import re
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr, Field, field_validator

# 경고 처리 상태 (sleep_events.status) — 미확인 → 확인 → 조치완료(3단계 해제) / 휴식완료(2단계 휴식 뒤 자동)
EventStatus = Literal["미확인", "확인", "조치완료", "휴식완료"]


# ── 로그인 · 회원가입 (수업 그대로 — 앱 auth_service.dart 가 이 모양으로 보냄, 10.14 팀장 확인) ──
class SignupRequest(BaseModel):
    email   : EmailStr = Field(..., description="사용자 이메일 주소")
    password: str      = Field(..., min_length=8, description="비밀번호(평문 입력)")
    name    : str      = Field(..., min_length=1, max_length=50, description="이름")

    @field_validator("password")
    def validate_password(cls, value):  # 수업 규칙 그대로 (앱이 422 메시지를 화면에 보여 줌)
        if not re.search(r"[A-Z]", value):
            raise ValueError("비밀번호에는 대문자가 최소 1개 포함되어야 합니다.")
        if not re.search(r"[a-z]", value):
            raise ValueError("비밀번호에는 소문자가 최소 1개 포함되어야 합니다.")
        if not re.search(r"[0-9]", value):
            raise ValueError("비밀번호에는 숫자가 최소 1개 포함되어야 합니다.")
        if not re.search(r"[!@#$%^&*(),.?\":{}|<>]", value):
            raise ValueError("비밀번호에는 특수문자가 최소 1개 포함되어야 합니다.")
        return value


class LoginRequest(BaseModel):
    email   : EmailStr = Field(..., description="사용자 이메일 주소")
    password: str      = Field(..., min_length=8, description="비밀번호(평문 입력)")


class GoogleLoginRequest(BaseModel):
    # 수업 앱은 Firebase 로그인 뒤 email · name · firebase_uid 를 보낸다 (id_token 아님)
    email       : EmailStr = Field(..., description="구글 계정 이메일")
    name        : str      = Field(..., min_length=1, max_length=50,  description="이름")
    firebase_uid: str      = Field(..., min_length=1, max_length=128, description="Firebase UID")


# ── 채팅 (수업 그대로) ────────────────────────────────────────
class ChatMessage(BaseModel):
    role: str = Field(..., description="'user' 또는 'bot'")
    text: str = Field(..., max_length=2000, description="메시지 내용")


class ChatRequest(BaseModel):
    message: str = Field(..., min_length=1, max_length=500, description="사용자 질문")
    history: list[ChatMessage] | None = Field(None, description="이전 대화 (선택)")


# ── 경고 처리 상태 변경 (수업 StatusUpdate 를 졸음용 상태로) ─────
class StatusUpdate(BaseModel):
    status: EventStatus


# ── 운전 중 음성 퀴즈 답 (POST /quiz/answer) ──────────────────
class VoiceQuizAnswer(BaseModel):
    quiz_id: str
    answer_text: str = ""                # STT 로 알아들은 글자. 무응답이면 ''
    answer_sec: Optional[float] = None   # 질문이 끝나고 답하기까지 걸린 초. 무응답이면 null


# ── 30초마다 보내는 ping (POST /drive/ping, 사진 없음) ────────
class DrivePing(BaseModel):
    perclos: Optional[float] = None      # 기록용. 단계 판단에는 쓰지 않음
