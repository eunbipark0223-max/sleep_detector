# ═══════════════════════════════════════════════════════════════
# main.py — 서버 시작 파일 (FastAPI 앱 만들기 · 라우터 등록)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: road_hazard_api/main.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - FastAPI 앱을 만들고 routers/ 의 라우터를 등록한다 (user · detect · event · admin · chat · quiz)
#   - 서버 시작 때 DB 테이블 자동 생성 (수업 코드 그대로)
#   - 서버 시작 때 눈 판정 모델 미리 읽기 · 30일 지난 졸음 사진 정리 (그 뒤 24시간마다)
#   - GET /health — 서버 상태 + CNN 이 실제로 쓰이는지 (mode · 모델 · 읽힘 · 판정 방식별 건수) · RAG 색인 준비 (rag_ready)
#   - 서버 시작 때 RAG 색인을 백그라운드로 미리 읽기 (첫 경고가 색인 때문에 멈추지 않게, 문서 · 모델이 바뀌었으면 약 70초)
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
import asyncio
import importlib
import os
import threading
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


def _warm_up_eye_models():
    """서버를 켤 때 눈 판정 모델(MediaPipe · CNN)을 미리 읽어 둔다.

    처음 쓸 때 읽으면 시연의 '첫 졸음 경고'만 늦어진다 (11/02). 실패해도 서버는 그대로 켜지고,
    CNN 이 없으면 face_service 가 EAR 만 쓴다 (torch · 모델 파일은 A · B · 팀장 PC 에만).
    """
    if not getattr(config, "USE_REAL_AI", True):
        return
    import time
    t0 = time.perf_counter()
    try:
        from services import face_service
        face_service._get_detector()
        cnn = face_service._get_cnn() if config.USE_CNN else None
        state = "CNN + EAR" if cnn is not None else "EAR 만 (CNN 없음)"
        print(f"✅ 눈 판정 모델 미리 읽음: {state} ({time.perf_counter() - t0:.1f}초)")
    except Exception as e:
        print(f"⚠️ 눈 판정 모델 미리 읽기 실패 (첫 판정 때 다시 읽음): {type(e).__name__}: {e}")


def _warm_up_rag():
    """서버를 켤 때 RAG 색인을 미리 읽는다 (백그라운드 — 서버 시작을 막지 않음).

    처음 쓸 때 만들면 첫 졸음 경고가 멈춘다 (11/05 첫 처리 85초, 색인 추정). 실패해도 서버는 그대로이고 첫 검색 때 다시 시도.
    """
    import time
    t0 = time.perf_counter()
    try:
        from services import rag_service
        if not rag_service.USE_REAL_AI:
            return
        rag_service.build_index()
        print(f"✅ RAG 색인 준비 완료 ({time.perf_counter() - t0:.1f}초)")
    except Exception as e:
        print(f"⚠️ RAG 색인 미리 읽기 실패 (첫 검색 때 다시 시도): {type(e).__name__}: {e}")


@asynccontextmanager
async def lifespan(app: FastAPI):   # ← app: FastAPI 매개변수 필수!
    try:
        import models.models  # noqa: F401  (표 모양을 Base 에 알려 줘야 create_all 이 만든다)
        Base.metadata.create_all(bind=engine)
        print("✅ DB 테이블 자동 생성 완료")
    except Exception as e:
        print(f"⚠️ DB 초기화 실패(앱은 계속 실행): {type(e).__name__}: {e}")

    # 서버를 다시 켜도 3단계 · 2단계가 풀리지 않게 DB 경고로 단계를 되살린다 (단계는 메모리에만 있어서 재시작하면 0 이 됐음)
    try:
        from database.db_connection import SessionLocal
        from services import sleep_state
        with SessionLocal() as db:
            restored = sleep_state.restore_all(db)
        if restored:
            print("✅ 단계 되살림: " + ", ".join(f"기사 {u} → {s}단계" for u, s in sorted(restored.items())))
    except Exception as e:
        print(f"⚠️ 단계 되살리기 실패(서버는 계속 켜짐): {type(e).__name__}: {e}")

    for d in (config.UPLOAD_TMP_DIR, config.UPLOAD_EVENT_DIR):
        os.makedirs(d, exist_ok=True)

    print(f"ℹ️  DEMO_MODE={config.DEMO_MODE}  USE_REAL_AI={config.USE_REAL_AI}  USE_CNN={config.USE_CNN}  "
          f"GEMINI_MODEL={config.GEMINI_MODEL}")

    _warm_up_eye_models()
    threading.Thread(target=_warm_up_rag, name="rag-warm-up", daemon=True).start()

    # 졸음 확정 사진 30일 자동 삭제 (D, services/photo_cleanup.py) — 시작 때 한 번 + 24시간마다
    from services import photo_cleanup
    cleanup_task = asyncio.create_task(photo_cleanup.daily_loop())

    yield

    cleanup_task.cancel()
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
    """서버 상태 + 눈 판정 상태. eye.mode 가 real · eye.loaded 가 true · judged 가 cnn 위주면 CNN 이 쓰이는 중"""
    out = {"status": "ok", "demo_mode": config.DEMO_MODE, "eye": None, "judged": None}
    try:                                     # 라우터가 건너뛰어져도 /health 는 응답한다 (_include_routers)
        from routers import detect
        from services import face_service
        out["eye"], out["judged"] = face_service.cnn_status(), detect.method_counts()
        out["rag_ready"] = detect.rag_service._store is not None
    except Exception as e:
        out["eye_error"] = type(e).__name__
    return out


@app.get("/admin", tags=["기본"])
def admin_page():
    return RedirectResponse(url="/static/admin_login.html")


if __name__ == "__main__":
    import uvicorn
    uvicorn.run("main:app", host=os.getenv("SERVER_HOST") or "127.0.0.1", port=8000, reload=True)
