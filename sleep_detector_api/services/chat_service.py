# ═══════════════════════════════════════════════════════════════
# services/chat_service.py — 규정 도우미 FAQ · 답변
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2
# 수업 원본: road_hazard_api/services/chat_service.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - 인사말을 졸음운전 · 휴게 규정 내용으로
#   - 질문 → rag_service.search_by_text 로 규정 근거 → Gemini 가 근거 안에서만 답변
#   - 근거에 없는 질문은 "제공된 자료에서 확인되지 않습니다" (노션 「RAG 전체 흐름 테스트」 채팅 시험 프롬프트를 운전자용으로)
#   - "버스는요?" 같은 이어지는 질문은 직전 사용자 질문을 붙여서 검색
#
# [만들 것 (이름 약속 — routers/chat.py 가 이 이름으로 부름)]
#   - hello() → str
#   - answer(message, history=None) → {"answer": str, "sources": [{title, source, content, is_real}], "is_real": bool}
#       history = [{"role": "user"|"bot", "text": str}, ...] (앱이 보내는 이전 대화, 없어도 됨)
#       is_real = False 면 AI 답이 아니라 기본 문장 (규정 원문은 sources 로 그대로 보여 줌)
#
# [주의]
#   - 답 속 숫자가 질문 · 근거에 없으면 기본 문장으로 교체 ("프롬프트는 부탁, 코드는 보증" — llm_service 와 같은 원칙)
#   - 출처 번호는 문장 끝에만 — 문장 앞 "[1]에 따르면" 은 코드가 지움 (끝에 [1] 이 또 붙어서 두 번 나옴)
#   - 무료 한도 때문에 재시도 없이 주 모델 1회 + 대체 모델 1회 (llm_service 의 클라이언트 · 모델 설정을 같이 씀)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 · 노션 「RAG 전체 흐름 테스트」
# ═══════════════════════════════════════════════════════════════

import re

from services import llm_service, rag_service

HELLO = "안녕하세요, 졸음 가드 규정 도우미예요. 졸음운전 · 연속 운전 휴게시간 규정을 물어보세요."
NO_AI_ANSWER = "지금은 AI 답변을 만들 수 없어요. 질문과 관련된 규정 원문을 아래에 보여 드릴게요."
HISTORY_TURNS = 6      # 이전 대화는 최근 6개만 (무료 한도 · 응답 속도)
ANSWER_MAX_CHARS = 600

SYSTEM_PROMPT = (
    "너는 화물차 · 버스 운전자를 돕는 졸음운전 · 휴게시간 규정 안내 도우미다. "
    "아래 [근거]에 있는 내용만 사용해 한국어로 2~5문장으로 답하라. "
    "각 근거에는 유형(법령 / 일반 자료)이 표시되어 있다. 의무 · 금지 · 허용 여부는 법령 근거로만 답하고, 일반 자료는 권고나 통계로만 인용하라. "
    "법령과 일반 자료의 내용이 다르면 법령을 따르고, 법령의 적용 대상(화물, 시외버스, 시내버스 등)을 함께 밝혀라. "
    "답에 쓴 근거는 문장 끝에만 [출처 번호]로 표시하고, '[1]에 따르면'처럼 문장 앞에는 쓰지 마라. 숫자는 근거에 적힌 그대로 쓰고, 통계는 집계 기간을 함께 적어라. "
    "근거가 질문의 대상과 다른 대상에 관한 것이면 그 근거를 대신 적용하지 마라. "
    "질문이 묻는 규정이나 통계가 [근거]에 없으면 '제공된 자료에서 확인되지 않습니다'라고만 답하라."
)

LAW_TITLE = re.compile(r"제\d+조")  # rag_service 의 법령 제목은 "…법 제45조(…)" 모양, 일반 자료는 조 번호 없음
LEAD_CITE = re.compile(r"\[\d+\]\s*(?:에|에서)\s*(?:따르면|의하면)\s*,?\s*")  # 문장 앞 "[1]에 따르면" (끝에 [1] 이 또 붙음)


def hello():
    return HELLO


def _context(sources):
    lines = []
    for n, s in enumerate(sources, 1):
        kind = "법령" if LAW_TITLE.search(s["title"]) else "일반 자료"
        lines.append(f"[{n}] ({kind} | {s['title']}) {s['content']}")
    return "\n".join(lines)


def _messages(message, history, sources):
    msgs = [{"role": "system", "content": SYSTEM_PROMPT}]
    for h in (history or [])[-HISTORY_TURNS:]:
        text = str(h.get("text") or "").strip()
        if text:
            msgs.append({"role": "assistant" if h.get("role") == "bot" else "user", "content": text})
    msgs.append({"role": "user", "content": f"[근거]\n{_context(sources)}\n\n[질문]\n{message}"})
    return msgs


def _real_answer(messages):
    errors = []
    for model in dict.fromkeys([llm_service.GEMINI_MODEL, llm_service.LLM_FALLBACK_MODEL]):  # 같은 이름이면 1번만
        try:
            r = llm_service._get_client().chat.completions.create(
                model=model, messages=messages, temperature=0.2, reasoning_effort="low")
            return r.choices[0].message.content
        except Exception as e:
            errors.append(f"{model}: {type(e).__name__} {str(e)[:120]}")
    raise RuntimeError(" / ".join(errors))


def _numbers(text):
    return set(re.findall(r"\d+(?:\.\d+)?", text))


def _check(text, question, sources):
    """정리 → 길이 제한 → 숫자 검사. 통과 못 하면 None. question = 검색에 쓴 질문 (직전 질문 포함)"""
    if not isinstance(text, str) or not re.search(r"[가-힣]", text):
        return None
    s = LEAD_CITE.sub("", text).strip()
    if len(s) > ANSWER_MAX_CHARS:
        cut = s[:ANSWER_MAX_CHARS]
        end = max(cut.rfind("다."), cut.rfind("요."))
        s = cut[: end + 2] if end > 0 else cut.rstrip() + "…"
    allowed = _numbers(question) | _numbers(_context(sources)) | {str(n) for n in range(1, len(sources) + 1)}
    if _numbers(s) - allowed:
        return None
    return s


def _search_query(message, history):
    """'버스는요?' 같은 이어지는 질문은 그것만으로 검색이 안 됨 → 직전 사용자 질문을 붙여서 검색."""
    last = next((str(h.get("text") or "").strip() for h in reversed(history or []) if h.get("role") == "user"), "")
    return f"{last} {message}" if last else message


def answer(message, history=None):
    query = _search_query(message, history)
    sources = rag_service.search_by_text(query)
    if not llm_service.USE_REAL_AI:
        return {"answer": NO_AI_ANSWER, "sources": sources, "is_real": False}
    try:
        raw = _real_answer(_messages(message, history, sources))
    except Exception as e:
        if not llm_service.FALLBACK_ON_ERROR:
            raise
        print(f"[chat_service] 답변 실패 → 기본 문장 사용: {e}")
        return {"answer": NO_AI_ANSWER, "sources": sources, "is_real": False}
    text = _check(raw, query, sources)
    if text is None:
        print(f"[chat_service] 답변 검사 불통과 → 기본 문장 사용: {str(raw)[:80]!r}")
        return {"answer": NO_AI_ANSWER, "sources": sources, "is_real": False}
    return {"answer": text, "sources": sources, "is_real": True}


if __name__ == "__main__":
    # 직접 확인: (sleep_detector_api 폴더에서) python -m services.chat_service "질문"
    import sys
    q = " ".join(sys.argv[1:]) or "화물차는 몇 시간 운전하면 쉬어야 하나요?"
    r = answer(q)
    print(r["answer"], f"(is_real={r['is_real']})")
    for n, s in enumerate(r["sources"], 1):
        print(f"  [{n}] {s['title']}")
