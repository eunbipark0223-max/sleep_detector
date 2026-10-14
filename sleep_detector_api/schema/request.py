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
#   - SignupRequest(email · password · name) · LoginRequest(email · password) · GoogleLoginRequest(id_token) · ChatRequest(message)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
from typing import Literal, Optional

from pydantic import BaseModel, EmailStr

# 경고 처리 상태 (sleep_events.status) — 미확인 → 확인 → 조치완료(3단계 해제) / 휴식완료(2단계 휴식 뒤 자동)
EventStatus = Literal["미확인", "확인", "조치완료", "휴식완료"]


# ── 로그인 · 회원가입 (수업 그대로) ───────────────────────────
class SignupRequest(BaseModel):
    email: EmailStr
    password: str
    name: str


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class GoogleLoginRequest(BaseModel):
    id_token: str  # 앱이 Firebase 에서 받은 구글 토큰


# ── 채팅 (수업 그대로) ────────────────────────────────────────
class ChatRequest(BaseModel):
    message: str


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
