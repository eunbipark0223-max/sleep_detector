# ═══════════════════════════════════════════════════════════════
# routers/chat.py — 규정 도우미 채팅 API
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2
# 수업 원본: road_hazard_api/routers/chat.py (🟢 그대로 복사)
#
# [이 파일이 하는 일]
#   - GET /chat/hello · POST /chat — chat_service 를 부름
#
# [연결 약속 — 앱 chat_screen.dart · api_service.dart(sendChat) · mock_server.py 와 같은 모양]
#   - GET  /chat/hello → {"message"}
#   - POST /chat (로그인 필요, ChatRequest: message · history) → {"success", "answer", "sources", "is_real"}
#       sources = [{title, source, content, is_real}] (rag_service 결과 그대로)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
from fastapi import APIRouter, Depends
from fastapi.concurrency import run_in_threadpool

from auth.jwt import get_current_user
from models.models import User
from schema.request import ChatRequest
from services import chat_service

router = APIRouter(prefix="/chat", tags=["chat"])


@router.get("/hello")
def chat_hello():
    """채팅 화면 첫 인사말."""
    return {"message": chat_service.hello()}


@router.post("")
async def chat(body: ChatRequest, user: User = Depends(get_current_user)):
    """질문 → 규정 근거(RAG) → 근거 안에서만 답변. AI 가 안 되면 규정 원문만 보여 줌."""
    history = [h.model_dump() for h in body.history or []]
    result = await run_in_threadpool(chat_service.answer, body.message, history)
    return {"success": True, **result}
