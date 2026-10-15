# ═══════════════════════════════════════════════════════════════
# database/orm.py — SQLAlchemy Base · 세션 (get_db)
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/database/orm.py (🟢 그대로 복사)
#
# [이 파일이 하는 일]
#   - 수업 파일을 그대로 복사해서 쓴다
#   - DB 이름만 sleep_detector 로 (.env)
#
# [쓰는 곳]
#   - Base — models/models.py 의 User · SleepEvent 가 상속, main.py 가 Base.metadata.create_all(engine) 으로 표를 만든다
#   - get_db — 라우터가 db: Session = Depends(get_db) 로 받는다 (요청이 끝나면 세션을 닫음)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
from sqlalchemy.orm import DeclarativeBase

from database.db_connection import SessionLocal, engine  # noqa: F401  (engine 은 main.py 가 여기서도 가져다 쓸 수 있게)


class Base(DeclarativeBase):
    """모든 DB 표(User · SleepEvent)가 상속받는 기본 클래스"""


def get_db():
    """요청마다 DB 세션을 하나 만들어 주고, 끝나면 반드시 닫는다 (FastAPI Depends 용)."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
