# ═══════════════════════════════════════════════════════════════
# services/chat_service.py — 규정 도우미 FAQ · 답변
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2
#
# [이 파일이 하는 일]
#   - 인사말을 졸음운전 · 휴게 규정 내용으로
#   - 질문 → rag_service.search_by_text 로 규정 근거 → Gemini 가 근거 안에서만 답변
#   - 근거에 없는 질문은 "제공된 자료에서 확인되지 않습니다" (노션 「RAG 전체 흐름 테스트」 채팅 시험 프롬프트를 운전자용으로)
#     → (11/18 팀장) 기사에게는 이 말 대신 NOT_FOUND_ANSWER 안내 + 근거 카드 숨김 (관계없는 법령 카드가 붙어 헷갈렸음)
#       주제는 맞는데 자료에 없는 대상(택시 등)이면 "택시 규정은 제가 가진 자료에 없어요 …" (_not_found_answer, 11/18)
#   - "버스는요?" 같은 이어지는 질문은 직전 사용자 질문을 붙여서 검색
#   - (11/18) 일상어 질문 — 검색어에만 법령 낱말을 덧붙임 (QUERY_WORDS 사전, AI 추가 호출 X). AI 에는 원래 질문 그대로
#   - (11/18) 검색 결과에 법령이 하나도 없으면 법령만 한 번 더 찾아 맨 앞에 (일반 자료 1개와 바꿈)
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
#   - (11/18 팀장) 기다리는 시간은 CHAT_TIMEOUT_SEC(20초) — llm_service 기본 5초는 경고 보고서용이라 법령 원문이 긴 질문이 늘 시간 초과였음
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 · 노션 「RAG 전체 흐름 테스트」
# ═══════════════════════════════════════════════════════════════

import re

from services import llm_service, rag_service

HELLO = "안녕하세요, 졸음 가드 규정 도우미예요. 졸음운전 · 연속 운전 휴게시간 규정을 물어보세요."
NO_AI_ANSWER = "지금은 AI 답변을 만들 수 없어요. 질문과 관련된 규정 원문을 아래에 보여 드릴게요."
NOT_FOUND_ANSWER = "저는 규정 도우미예요. 졸음운전 · 휴게시간 규정을 물어봐 주세요."  # (11/18 팀장) 자료에 없는 질문 — 근거 카드 없이
# (11/18) 주제는 맞는데 자료에 없는 질문 ('택시도 2시간마다 쉬어야 해?') 에 위 안내는 어색함 — 규정을 물었는데 규정을 물어보라는 셈
#   → 자료에 없는 대상이면 그 대상을 밝혀 안내, 주제는 맞는데 대상이 없으면 IN_TOPIC_NOT_FOUND. 둘 다 카드는 숨김 (팀장 확인)
SCOPE_HINT = "화물차 · 시외버스 · 전세버스 규정은 물어봐 주세요."
OUT_OF_SCOPE_TARGETS = ("택시", "오토바이", "이륜차", "자전거", "킥보드", "승용차", "자가용", "렌터카", "대리운전")  # knowledge/ 에 휴식 규정 없음
TOPIC_WORDS = ("운전", "쉬", "휴게", "휴식", "졸", "피곤", "과로", "기사", "버스", "화물", "트럭", "처벌", "벌금", "규정", "법")
IN_TOPIC_NOT_FOUND = f"물어보신 내용은 제가 가진 자료에 없어요. {SCOPE_HINT}"
# SYSTEM_PROMPT 가 자료에 없을 때 쓰라고 한 말 "만" 답했을 때 — "…는 확인되지 않습니다. 다만 …" 처럼 쓸 내용이 붙은 답은 그대로 둔다
NOT_FOUND_ONLY = re.compile(r"^[^.]*확인되지\s*않(?:습니다|아요)[.\s]*(\[[\d,\s]+\][.\s]*)*$")   # 한 문장짜리 '…확인되지 않습니다 [1, 2]' 까지 (11/18 해요체 '않아요' 로 와도)
CHAT_TIMEOUT_SEC = 20  # (11/18 팀장) 규정 도우미만 — 경고 보고서용 llm_service 5초와 따로
HISTORY_TURNS = 6      # 이전 대화는 최근 6개만 (무료 한도 · 응답 속도)
ANSWER_MAX_CHARS = 600

SYSTEM_PROMPT = (
    "너는 화물차 · 버스 운전자를 돕는 졸음운전 · 휴게시간 규정 안내 도우미다. "
    "아래 [근거]에 있는 내용만 사용해 한국어로 2~5문장으로 답하라. "
    # 11/18 팀장: 답 끝맺음이 '~한다' · '~합니다' 로 섞여 나옴 → 앱의 다른 문장(음성 · 안내)과 같은 해요체로
    #   자료에 없을 때 쓰는 문장은 아래 NOT_FOUND_ONLY 가 알아보도록 그대로 둠
    "모든 문장은 기사에게 말하듯 해요체(~해요, ~해야 해요, ~할 수 있어요)로 끝내라. "
    "단, 자료에 없을 때 쓰는 '제공된 자료에서 확인되지 않습니다'는 그대로 써라. "
    "각 근거에는 유형(법령 / 일반 자료)이 표시되어 있다. 의무 · 금지 · 허용 여부는 법령 근거로만 답하고, 일반 자료는 권고나 통계로만 인용하라. "
    "법령과 일반 자료의 내용이 다르면 법령을 따르고, 법령의 적용 대상(화물, 시외버스, 시내버스 등)을 함께 밝혀라. "
    "답에 쓴 근거는 문장 끝에만 [출처 번호]로 표시하고, '[1]에 따르면'처럼 문장 앞에는 쓰지 마라. 숫자는 근거에 적힌 그대로 쓰고, 통계는 집계 기간을 함께 적어라. "
    # 11/04: 아래 '다른 대상' 규칙 때문에 "졸음운전 사고 처벌은?" 을 '과로'(제154조 제3호) 근거로 못 잇고 5/5 거절 → 한 문장 추가
    #        (팀장 확인: '해당한다' 는 단정 X → 관련 근거로 안내 + 적용은 사안에 따라 다름)
    "졸음운전에 관한 처벌이나 의무를 물으면, 과로로 정상적으로 운전하지 못할 우려가 있는 상태의 운전을 다루는 법령을 "
    "관련 근거로 안내하되, 실제 적용 여부는 사안에 따라 다르다고 함께 말하라. "
    # 11/18: 예전 '근거가 질문의 대상과 다른 대상이면 적용하지 마라' 때문에 '밤새 운전' ↔ '2시간 연속 운전' 을 다른 이야기로 보고 거절
    #        → 가까운 규정은 적용 대상을 밝혀 안내, 전혀 관계없는 질문만 거절 (팀장 요청)
    "질문과 가까운 규정이 [근거]에 있으면, 그 규정의 적용 대상(화물, 시외버스 등)을 밝히고 안내하라. "
    # 11/18 2차: '근거에 나오지 않는 대상(택시)' 규칙이 모든 운전자 대상인 도로교통법에도 걸려
    #           '택시 기사인데 졸음운전하면 처벌 받아?' 를 3/3 거절 → 휴게시간 규정(운수사업법)에만 걸리게 (팀장 요청)
    #           1차 문장('택시 등 모든 운전자에게 적용된다고 안내하라')은 택시 휴게 질문에 지시문을 그대로 읊고,
    #           '회사 가는 길에 너무 졸려' 에도 '택시 등 모든 운전자에게 적용' 을 붙임 → 아래처럼 '거절하지 마라' 로만
    #           2번째 문장은 '고속버스' 까지 자료에 없는 대상으로 보고 2/3 거절 → 고속 · 관광버스가 어디에 속하는지 적음
    #           '택시 기사인데 졸음운전하면 처벌 받아?' 에 '택시 휴게시간 규정은 확인되지 않습니다' 를 앞에 붙임 → 휴게시간을 물을 때만
    "운수사업법(화물자동차 · 여객자동차)의 휴게시간 규정은 근거에 나온 대상(화물, 시내 · 시외 · 전세버스 등)에만 적용된다. "
    "고속버스는 시외버스, 관광버스는 전세버스에 속한다. "
    "휴게시간을 묻는데 그 대상이 근거의 휴게시간 규정 대상이 아니면(예: 택시) '제공된 자료에서 확인되지 않습니다'라고만 답하라. "
    "처벌이나 금지를 묻는 질문에는 휴게시간 규정이 없다는 말 없이 도로교통법 근거로 답하라. "
    "도로교통법은 모든 운전자에게 적용되므로, 질문한 대상이 도로교통법 근거에 따로 적혀 있지 않다는 이유로 거절하지 마라. "
    "근거와 전혀 관계없는 질문에만 '제공된 자료에서 확인되지 않습니다'라고 답하라."
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
            r = llm_service._get_client().with_options(timeout=CHAT_TIMEOUT_SEC).chat.completions.create(
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


FOLLOW_UP_MAX_CHARS = 8   # 공백 · 문장부호 빼고 이 글자 수 이하면 이어지는 질문으로 봄 ('버스는요' 4 · '그럼택시는' 5)
FOLLOW_UP_STARTS = ("그럼", "그러면", "그건", "그거", "그것", "그리고", "그때", "그 경우", "거기", "이때", "이 경우")


def _is_follow_up(message):
    """'버스는요?' · '그럼 택시는?' 처럼 앞 질문 없이는 뜻이 안 되는 질문인지.
    11/09: 모든 질문에 직전 질문을 붙였더니 '졸음운전으로 사고 나면 처벌은?' 이 앞의 '화물차 휴게' 질문에 끌려가
    휴게 조문만 찾고 '확인되지 않습니다' 로 답함 → 짧거나 '그럼 · 그건' 으로 시작할 때만 붙임"""
    text = str(message or "").strip()
    return len(re.sub(r"[^0-9A-Za-z가-힣]", "", text)) <= FOLLOW_UP_MAX_CHARS or text.startswith(FOLLOW_UP_STARTS)


def _search_query(message, history):
    """'버스는요?' 같은 이어지는 질문은 그것만으로 검색이 안 됨 → 직전 사용자 질문을 붙여서 검색.
    혼자서도 뜻이 되는 질문은 그대로 검색 (_is_follow_up)."""
    if not _is_follow_up(message):
        return message
    last = next((str(h.get("text") or "").strip() for h in reversed(history or []) if h.get("role") == "user"), "")
    return f"{last} {message}" if last else message


# 일상어 → 법령 낱말 (11/18 팀장 점검: '버스 기사인데 2시간 넘게 운전하면 어떻게 해야 해?' 가
#   법령 낱말이 없고 '어떻게' 만 있어 rag_service._route 가 일반 자료로만 검색 → 뉴스 기사 3개 → 거절)
#   법령은 '운수종사자 · 휴게시간 · 연속운전', 기사는 '버스 기사 · 쉬어야 · 2시간 넘게' — 낱말이 안 겹침
#   덧붙인 말은 검색에만 쓰고 AI 에는 원래 질문을 줌. 숫자는 넣지 않음 (_check 의 숫자 검사가 질문 숫자를 허용하므로)
#   (낱말들, 덧붙일 말, 같이 나와야 하는 낱말 — 비어 있으면 조건 없음)
#   11/18 2차: '회사 가는 길에 너무 졸려' 에 '회사' 가 걸려 버스 '출근 전 8시간 휴식' 규정이 붙음
#              → 사장 · 회사는 '쉬' · '시간' 과 같이 나올 때만 (예: '회사가 쉬는 시간 줘야 해?')
QUERY_WORDS = [
    (("버스 기사", "버스기사", "버스 운전", "고속버스", "관광버스"), "여객자동차 운수종사자 시외버스 전세버스", ()),
    (("화물차", "트럭", "화물 기사", "화물기사", "용달"), "화물자동차 운수종사자", ()),
    (("쉬어", "쉬는", "쉬지", "쉴 ", "쉬면"), "휴게시간 휴식시간", ()),
    (("넘게", "계속", "밤새", "내리 ", "달렸"), "연속 운전", ()),
    (("피곤", "지쳐", "밤새"), "과로", ()),
    (("사장", "회사"), "운송사업자 보장", ("쉬", "시간")),
]


def _expand(query):
    """검색어에 법령 낱말 덧붙이기 (사전에 걸린 것만, 같은 말은 한 번)"""
    extra = [words for keys, words, also in QUERY_WORDS
             if any(k in query for k in keys) and (not also or any(w in query for w in also))]
    return " ".join([query, *dict.fromkeys(extra)])


def _is_law(source):
    return bool(LAW_TITLE.search(source["title"]))


def _law_first(sources, search_query):
    """검색 결과에 법령이 하나도 없으면 법령만 한 번 더 찾아 맨 앞에 (개수는 그대로 — 마지막 일반 자료와 바꿈).
    의무 · 금지는 법령으로만 답하라는 지시문 때문에, 법령 없이 뉴스만 있으면 AI 가 거절함"""
    if not sources or any(_is_law(s) for s in sources) or not all(s["is_real"] for s in sources):
        return sources  # 이미 법령이 있거나, 검색 실패로 대표 규정(가짜)이 온 경우
    law = [s for s in rag_service.search_by_text(search_query, k=1, doc_type="law") if s["is_real"] and _is_law(s)]
    return (law + sources[: len(sources) - len(law)]) if law else sources


def _not_found_answer(query):
    """AI 가 '확인되지 않습니다' 만 답했을 때 기사에게 보여 줄 말. query = 검색에 쓴 질문 (이어지는 질문이면 직전 질문 포함)"""
    target = next((t for t in OUT_OF_SCOPE_TARGETS if t in query), None)
    if target:
        return f"{target} 규정은 제가 가진 자료에 없어요. {SCOPE_HINT}"
    if any(w in query for w in TOPIC_WORDS):
        return IN_TOPIC_NOT_FOUND
    return NOT_FOUND_ANSWER


def answer(message, history=None):
    query = _search_query(message, history)
    search_query = _expand(query)
    sources = _law_first(rag_service.search_by_text(search_query), search_query)
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
    if NOT_FOUND_ONLY.match(text.strip()):
        # (11/18 팀장) 자료에 없는 질문 — '확인되지 않습니다' 대신 안내, 관계없는 근거 카드는 숨김
        return {"answer": _not_found_answer(query), "sources": [], "is_real": True}
    return {"answer": text, "sources": sources, "is_real": True}


if __name__ == "__main__":
    # 직접 확인: (sleep_detector_api 폴더에서) python -m services.chat_service "질문"
    import sys
    q = " ".join(sys.argv[1:]) or "화물차는 몇 시간 운전하면 쉬어야 하나요?"
    r = answer(q)
    print(r["answer"], f"(is_real={r['is_real']})")
    for n, s in enumerate(r["sources"], 1):
        print(f"  [{n}] {s['title']}")
