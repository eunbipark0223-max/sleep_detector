# ═══════════════════════════════════════════════════════════════
# main.py — 서버 시작 파일 (FastAPI 앱 만들기 · 라우터 등록)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: road_hazard_api/main.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - FastAPI 앱을 만들고 routers/ 의 라우터를 등록한다 (user · detect · event · admin · chat · quiz)
#   - 서버 시작 때 DB 테이블 자동 생성 (수업 코드 그대로)
#   - static/ (관리자 웹) 과 uploads/events/ (졸음 확정 사진) 를 정적 파일로 연결
#   - 실행: python main.py  →  http://127.0.0.1:8000/docs
#
# [주의]
#   - hazard 라우터는 event 로 이름이 바뀜 (수업 /hazards → /events)
#   - 라우터는 "있는 것만" 등록한다 — 아직 비어 있거나 오류가 난 파일은 건너뛰고 터미널에 ⚠️ 로 알려 줌
#     (팀원 파일이 하나 덜 돼도 서버 전체가 멈추지 않게. 다 만들어지면 ⚠️ 가 사라진다)
#   - 시연 폰(실기기)에서 접속하려면 .env 에 SERVER_HOST=0.0.0.0 → 앱은 PC 의 IP:8000 으로 접속
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import importlib
import os
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse
from fastapi.staticfiles import StaticFiles
from starlette.middleware.sessions import SessionMiddleware

import config
from database.db_connection import engine
from database.orm import Base

# 등록할 라우터 (파일 이름, 담당) — 순서대로 /docs 에 보인다
ROUTERS = [
    ("user", "-"),       # /users/*  로그인 · 회원가입
    ("detect", "팀장"),   # /detect · /drive/*
    ("quiz", "팀장"),     # /quiz/answer
    ("event", "D"),      # /events/*
    ("admin", "D"),      # /admin/*
    ("chat", "B"),       # /chat
]


def _include_routers(app: FastAPI):
    for name, owner in ROUTERS:
        try:
            module = importlib.import_module(f"routers.{name}")
            app.include_router(module.router)
            print(f"✅ 라우터 등록: {name}")
        except Exception as e:  # 아직 비어 있는 파일 · import 오류
            print(f"⚠️ 라우터 건너뜀: {name} (담당 {owner}) — {type(e).__name__}: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):   # ← app: FastAPI 매개변수 필수!
    try:
        import models.models  # noqa: F401  (표 모양을 Base 에 알려 줘야 create_all 이 만든다)
        Base.metadata.create_all(bind=engine)
        print("✅ DB 테이블 자동 생성 완료")
    except Exception as e:
        print(f"⚠️ DB 초기화 실패(앱은 계속 실행): {type(e).__name__}: {e}")

    for d in (config.UPLOAD_TMP_DIR, config.UPLOAD_EVENT_DIR):
        os.makedirs(d, exist_ok=True)

    print(f"ℹ️  DEMO_MODE={config.DEMO_MODE}  USE_REAL_AI={config.USE_REAL_AI}  USE_CNN={config.USE_CNN}  "
          f"GEMINI_MODEL={config.GEMINI_MODEL}")

    yield

    print("서버 종료")


app = FastAPI(
    title      = "졸음 가드 API",
    description= "AI 졸음 감지 · 능동형 안전 알림 (앱 ML Kit → 서버 EAR/CNN 확인 → LLM → RAG → Agent)",
    version    = "1.0.0",
    lifespan   = lifespan,
)

_include_routers(app)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.add_middleware(
    SessionMiddleware,
    secret_key=os.getenv("SECRET_KEY") or "sleep-detector-session-secret",
)

os.makedirs(config.UPLOAD_EVENT_DIR, exist_ok=True)
app.mount("/static", StaticFiles(directory=os.path.join(config.BASE_DIR, "static")), name="static")
app.mount("/uploads/events", StaticFiles(directory=config.UPLOAD_EVENT_DIR), name="events")  # 관리자 웹 · 앱 사진


@app.get("/", tags=["기본"])
def root():
    return {"message": "졸음 가드 API", "docs": "/docs", "admin": "/admin"}


@app.get("/health", tags=["기본"])
def health():
    return {"status": "ok", "demo_mode": config.DEMO_MODE}


@app.get("/admin", tags=["기본"])
def admin_page():
    return RedirectResponse(url="/static/admin_login.html")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=os.getenv("SERVER_HOST") or "127.0.0.1", port=8000, reload=True)
