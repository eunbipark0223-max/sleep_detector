# ═══════════════════════════════════════════════════════════════
# database/db_connection.py — MySQL 연결 (.env 의 DB_* 값 사용, DB 이름 sleep_detector)
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/database/db_connection.py (🟢 그대로 복사)
#
# [이 파일이 하는 일]
#   - 수업 파일을 그대로 복사해서 쓴다
#   - DB 이름만 sleep_detector 로 (.env)
#
# [읽는 값 — .env.example 참고] DB_HOST · DB_PORT · DB_USER · DB_PASSWORD · DB_NAME(sleep_detector)
#   MySQL 에 빈 DB sleep_detector (utf8mb4) 를 미리 만들어 둔다. 표(users · sleep_events)는 서버가 시작할 때 자동으로 만든다
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import os
from urllib.parse import quote_plus

from dotenv import load_dotenv
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

load_dotenv()  # sleep_detector_api/.env 읽기

DB_HOST = os.getenv("DB_HOST", "localhost")
DB_PORT = os.getenv("DB_PORT", "3306")
DB_USER = os.getenv("DB_USER", "root")
DB_PASSWORD = os.getenv("DB_PASSWORD", "")
DB_NAME = os.getenv("DB_NAME", "sleep_detector")

# 비밀번호에 @ : / 같은 글자가 있어도 주소가 깨지지 않게 quote_plus
DATABASE_URL = (
    f"mysql+pymysql://{quote_plus(DB_USER)}:{quote_plus(DB_PASSWORD)}"
    f"@{DB_HOST}:{DB_PORT}/{DB_NAME}?charset=utf8mb4"
)

# pool_pre_ping — 오래 놀던 연결이 끊겨 있어도 쓰기 전에 확인해서 다시 연결 (발표 중 'MySQL has gone away' 방지)
engine = create_engine(DATABASE_URL, pool_pre_ping=True, echo=os.getenv("DB_ECHO", "false").lower() == "true")

# autocommit · autoflush 를 꺼서 commit() 을 코드가 직접 부른다 (event.py 의 db.commit())
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
