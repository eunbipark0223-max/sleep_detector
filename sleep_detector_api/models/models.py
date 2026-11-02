# ═══════════════════════════════════════════════════════════════
# models/models.py — DB 테이블 2개 (users · sleep_events)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: road_hazard_api/models/models.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - User — 수업 그대로 (role 값 user / admin 도 그대로)
#   - Hazard → SleepEvent (테이블 sleep_events) — 졸음 경고 1건
#   -   칸: id · user_id · stage · ear · eye_closed_prob · method(ear/cnn/mlkit) · reason(microsleep/perclos/rest_overdue/no_response)
#   -       perclos · summary · guidance · report(JSON 문자열: eye · driving_quiz · rest 포함) · photo_path
#   -       latitude · longitude · status(미확인/확인/조치완료/휴식완료) · created_at
#
# [주의]
#   - 칸을 새로 추가하지 않는다. 새 정보는 report JSON 안에 넣는다 (파일 구조 3장)
#     단 하나 예외: users 에 phone · vehicle_no (기사 연락용, 팀장 결정 10/29 — 관리자가 경고를 보고 바로 전화하려고)
#   - 칸 이름은 schema/response.py 의 SleepEventResponse (D) 와 같다 — 바꾸면 앱 · 관리자 웹까지 바뀜
#   - 표는 서버가 시작할 때 자동으로 만든다 (main.py). 칸을 바꿨으면 MySQL 에서 표를 지우고 다시 시작
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

from datetime import datetime

from sqlalchemy import (
    Integer, String, Float, Text,
    ForeignKey, DateTime, Numeric, func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from database.orm import Base


class SleepEvent(Base):
    __tablename__ = "sleep_events"

    id: Mapped[int] = mapped_column(
        Integer,
        primary_key=True,
        autoincrement=True,
    )
    user_id: Mapped[int | None] = mapped_column(
        ForeignKey("users.id"),
        nullable=True,
        index=True,
    )
    stage: Mapped[int] = mapped_column(          # 1~3 단계 (수업 severity 자리)
        Integer,
        nullable=False,
        index=True,
    )
    ear: Mapped[float | None] = mapped_column(   # 서버가 계산한 EAR (수업 confidence 자리, 얼굴 없으면 null)
        Float,
        nullable=True,
    )
    eye_closed_prob: Mapped[float | None] = mapped_column(  # CNN 감김 확률 (USE_CNN 일 때)
        Float,
        nullable=True,
    )
    method: Mapped[str | None] = mapped_column(  # ear / cnn / mlkit
        String(10),
        nullable=True,
    )
    reason: Mapped[str] = mapped_column(         # microsleep / perclos / rest_overdue / no_response
        String(20),
        nullable=False,
        index=True,
    )
    perclos: Mapped[float | None] = mapped_column(  # 앱이 계산한 PERCLOS (0~1)
        Float,
        nullable=True,
    )
    summary: Mapped[str | None] = mapped_column(  # LLM 상황 요약 (수업 memo 자리)
        String(255),
        nullable=True,
    )
    guidance: Mapped[str | None] = mapped_column(  # Agent 안내문
        String(255),
        nullable=True,
    )
    report: Mapped[str | None] = mapped_column(  # Agent 관리자 보고서 JSON 문자열 (eye · driving_quiz · rest · is_real …)
        Text,
        nullable=True,
    )
    photo_path: Mapped[str | None] = mapped_column(  # 졸음 확정 사진 (uploads/events/…)
        String(255),
        nullable=True,
    )
    latitude: Mapped[float | None] = mapped_column(
        Numeric(10, 7),
        nullable=True,
    )
    longitude: Mapped[float | None] = mapped_column(
        Numeric(10, 7),
        nullable=True,
    )
    status: Mapped[str] = mapped_column(         # 미확인 / 확인 / 조치완료 / 휴식완료
        String(20),
        nullable=False,
        default="미확인",
        index=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        server_default=func.now(),
        nullable=False,
        index=True,
    )

    user: Mapped["User | None"] = relationship(
        back_populates="sleep_events",
    )


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)

    email: Mapped[str] = mapped_column(
        String(255),
        unique=True,
        index=True,
        nullable=False,
    )
    hashed_password: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )
    name: Mapped[str] = mapped_column(
        String(50),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(
        String(10),
        nullable=False,
        default="user",
    )
    provider: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="email",
    )
    firebase_uid: Mapped[str | None] = mapped_column(
        String(128),
        nullable=True,
        unique=True,
    )
    photo_url: Mapped[str | None] = mapped_column(
        String(255),
        nullable=True,
    )
    # 관리자가 졸음 경고를 보고 기사에게 바로 연락할 때 쓴다 (기사가 프로필 화면에서 직접 입력, 선택).
    # 🔴 이미 만들어진 DB 에는 create_all 이 칸을 추가해 주지 않는다 → 각자 MySQL 에서 한 번만:
    #    ALTER TABLE users ADD COLUMN phone VARCHAR(20) NULL, ADD COLUMN vehicle_no VARCHAR(20) NULL;
    phone: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
    )
    vehicle_no: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime,
        server_default=func.now(),
        nullable=False,
    )

    sleep_events: Mapped[list["SleepEvent"]] = relationship(
        back_populates="user",
    )
