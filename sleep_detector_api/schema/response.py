# ═══════════════════════════════════════════════════════════════
# schema/response.py — 서버가 돌려주는 JSON 모양 (Pydantic)
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0
# 수업 원본: road_hazard_api/schema/response.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - HazardResponse → SleepEventResponse (경고 1건, 운행 기록 · 관리자 목록에서 씀)
#   - 로그인 · 내 정보 응답은 수업 그대로
#
# [주의]
#   - 경고 1건의 칸은 models.py 의 SleepEvent 칸 그대로 (칸을 새로 만들지 않음 — 새 정보는 report JSON 안에)
#   - DB 의 report 는 JSON 문자열 → 응답에서는 객체로 풀어서 내려보냄 (앱 sleep_event.dart · 관리자 웹이 바로 읽게)
#   - /detect · /drive/ping · /quiz/answer 응답은 각 router 가 직접 만든다 (앱 sleep_response.dart · drive_status.dart 와 맞춤)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import json
import os
from datetime import datetime
from typing import Any, Optional

from pydantic import BaseModel, ConfigDict, field_validator

STAGE_LABELS = {0: "정상", 1: "주의", 2: "휴식 권고", 3: "긴급"}


# ── 로그인 · 내 정보 (수업 그대로) ────────────────────────────
class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    email: str
    name: str
    role: str  # user / admin


class LoginResponse(BaseModel):
    success: bool = True
    access_token: str
    token_type: str = "bearer"
    user: UserResponse


# ── 경고 1건 (GET /events/my 의 한 줄) ────────────────────────
class SleepEventResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    user_id: int
    stage: int
    stage_label: str = ""
    status: str                              # 미확인 / 확인 / 조치완료 / 휴식완료
    reason: str                              # microsleep / perclos / rest_overdue / no_response
    ear: Optional[float] = None
    eye_closed_prob: Optional[float] = None
    method: Optional[str] = None             # ear / cnn / mlkit
    perclos: Optional[float] = None
    summary: str = ""
    guidance: str = ""
    report: dict[str, Any] = {}              # situation · stage_reason · regulation · recommended_action · location · eye · driving_quiz · rest
    photo_url: Optional[str] = None          # /uploads/events/xxx.jpg
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    created_at: datetime

    @field_validator("report", mode="before")
    @classmethod
    def _report_to_dict(cls, value):
        if isinstance(value, str):
            try:
                value = json.loads(value)
            except ValueError:
                return {}
        return value if isinstance(value, dict) else {}

    @field_validator("summary", "guidance", mode="before")
    @classmethod
    def _none_to_empty(cls, value):
        return "" if value is None else value

    @classmethod
    def from_event(cls, event) -> "SleepEventResponse":
        """DB 줄(SleepEvent) → 응답. photo_path 는 서버 안 경로라 내보내지 않고 photo_url 만 만든다."""
        data = cls.model_validate(event)
        data.stage_label = STAGE_LABELS.get(event.stage, "")
        data.photo_url = f"/uploads/events/{os.path.basename(event.photo_path)}" if event.photo_path else None
        return data


# ── 관리자 목록의 한 줄 (경고 + 기사 + 도로명 주소) ──────────────
class AdminEventResponse(SleepEventResponse):
    user_name: str = ""
    user_email: str = ""
    address: str = ""                        # 카카오 도로명 주소 (실패하면 빈 값)
    urgent: bool = False                     # 3단계 또는 음성 응답 없음 → 빨간 줄


class AdminUserResponse(UserResponse):
    event_count: int = 0
    last_event_at: Optional[datetime] = None


# ── 통계 (P2) ─────────────────────────────────────────────────
class StageStat(BaseModel):
    stage: int
    label: str
    count: int


class HourStat(BaseModel):
    hour: int
    count: int
