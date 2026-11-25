# ═══════════════════════════════════════════════════════════════
# main.py — 서버 시작 파일 (FastAPI 앱 만들기 · 라우터 등록)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
#
# [이 파일이 하는 일]
#   - FastAPI 앱을 만들고 routers/ 의 라우터를 등록한다 (user · detect · event · admin · chat · quiz)
#   - 서버 시작 때 DB 테이블 자동 생성
#   - 서버 시작 때 눈 판정 모델 미리 읽기 · 30일 지난 졸음 사진 정리 (그 뒤 24시간마다)
#   - GET /health — 서버 상태 + CNN 이 실제로 쓰이는지 (mode · 모델 · 읽힘 · 판정 방식별 건수) · RAG 색인 준비 (rag_ready)
#   - 서버 시작 때 RAG 색인을 백그라운드로 미리 읽기 (첫 경고가 색인 때문에 멈추지 않게, 문서 · 모델이 바뀌었으면 약 70초)
#   - static/ (관리자 웹) 을 정적 파일로 연결 (졸음 확정 사진 uploads/events/ 는 공개하지 않고 GET /events/{id}/photo 로만, 11/10)
#   - 실행: python main.py  →  http://127.0.0.1:8000/docs
#
# [주의]
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
    ("rest_area", "B"),  # /rest-areas/road-distance  졸음쉼터 도로 거리 (카카오 길찾기)
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

    # (11/17 C) 사번 가입 — users.emp_no 칸 붙이기 · 시연용 사번 넣기 (이미 있으면 그대로)
    try:
        from services import employee_service
        employee_service.ensure_schema(engine)
    except Exception as e:
        print(f"⚠️ 사번 표 준비 실패(앱은 계속 실행): {type(e).__name__}: {e}")

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
    # (11/25) 임시 사진 폴더는 요청 하나 동안만 쓰는 곳 — 서버가 꺼졌을 때 남은 사진(얼굴)은 켤 때 지움
    for name in os.listdir(config.UPLOAD_TMP_DIR):
        if name != ".gitkeep":
            try:
                os.remove(os.path.join(config.UPLOAD_TMP_DIR, name))
            except OSError:
                pass

    print(f"ℹ️  DEMO_MODE={config.DEMO_MODE}  USE_REAL_AI={config.USE_REAL_AI}  USE_CNN={config.USE_CNN}  "
          f"GEMINI_MODEL={config.GEMINI_MODEL}")

    # (11/19) 메일 — 켜졌는지 한눈에. 꺼져 있으면 인증번호가 응답(demo_code)에 실리니 배포 서버에서는 꼭 켜져 있어야 함
    if config.MAIL_ENABLED:
        print(f"✅ 메일: 구글 SMTP 켜짐 ({config.SMTP_HOST}:{config.SMTP_PORT}, 하루 {config.MAIL_DAILY_LIMIT}통 상한)")
    elif config.SMTP_USER or config.SMTP_PASSWORD:
        print("⚠️ 메일: SMTP_USER · SMTP_PASSWORD 중 하나만 있어서 꺼짐 — 둘 다 넣어야 켜짐 (지금은 시연용: 인증번호를 응답으로 줌)")
    else:
        print("ℹ️  메일: 꺼짐 — 시연용 (이메일 인증번호를 응답 demo_code 로 줌). 켜려면 .env 에 SMTP_USER · SMTP_PASSWORD")

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


# (11/25 팀장) 관리자 웹 화면(HTML)은 브라우저가 저장해 두지 않고 매번 새로 받게 — 예전 화면 · 예전 로고가 계속 보이던 문제
#   그림 · js 는 그대로 저장해도 됨 (바꿀 때는 HTML 에서 주소 끝 ?v= 를 올림)
@app.middleware("http")
async def no_cache_admin_html(request, call_next):
    response = await call_next(request)
    path = request.url.path
    if path.startswith("/static/") and path.endswith(".html"):
        response.headers["Cache-Control"] = "no-cache, must-revalidate"
    return response


app.mount("/static", StaticFiles(directory=os.path.join(config.BASE_DIR, "static")), name="static")
# 졸음 사진(uploads/events/)은 얼굴 사진이라 폴더를 공개하지 않는다 → GET /events/{id}/photo (로그인 + 본인 또는 관리자, routers/event.py)


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
