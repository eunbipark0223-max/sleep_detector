# ═══════════════════════════════════════════════════════════════
# services/rag_service.py — RAG 졸음운전 · 휴게시간 규정 검색
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P0
# 수업 원본: road_hazard_api/services/rag_service.py (🟡 수정, 딥러닝 21차시)
#
# [이 파일이 하는 일]
#   - [처음 1번] knowledge/*.txt → 호 단위로 자르기 → Gemini 임베딩 → Chroma(chroma_db/)
#   - [졸음마다] search_regulations(): 도로교통법 제45조 1개 고정 + 휴게 규정 2개 검색 → 제목 · 출처 · 내용
#   - [채팅 · Agent 도구] search_by_text(): 질문 단어로 법령 / 일반 자료를 골라 검색
#   - 결과를 쓰는 곳: Agent 보고서 regulation · 앱 [규정 보기] · 휴게 알림 안내문 · 규정 도우미
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - search_regulations(summary="", vehicle=None, k=3) → [{title, source, content, is_real}]  (vehicle 없으면 화물 · 여객 둘 다)
#   - search_by_text(query, k=4)                        → [{title, source, content, is_real}]
#       is_real = False 면 검색 결과가 아닌 대표 규정(가짜 / 실패) — 팀장이 보고서 is_real.rag 로 저장
#
# [주의]
#   - 임베딩: gemini-embedding-2 (3072차원), OpenAI 호환 주소로 호출 (11/04 001 → 2 교체)
#       · 001 과 벡터 공간이 달라 색인을 다시 만들어야 함 (모델 이름이 지문에 들어 있어 저절로 다시 만듦)
#       · 2 는 task_type 을 못 써서 공식 문서대로 글 앞에 작업 표시를 붙임 (_GeminiEmbeddings)
#   - 핵심 경로는 법령만 검색 — 일반 자료(보도자료)가 섞이면 법령이 밀려남 (노션 「문제 1」)
#   - knowledge/ 문서를 바꾸면 다음 검색 때 색인이 저절로 다시 만들어짐 (chroma_db/ 지워도 됨)
#   - 실패하면 대표 규정 3개 (mock)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 · 노션 「RAG 전체 흐름 테스트」
# ═══════════════════════════════════════════════════════════════

import hashlib
import os
import re
import shutil
import threading
import time
from pathlib import Path

from dotenv import load_dotenv

import config

BASE_DIR = Path(__file__).resolve().parent.parent
load_dotenv(BASE_DIR / ".env")


def _cfg(name, default=None):
    """config.py 값 → 없으면 .env 값 → 없으면 기본값."""
    value = getattr(config, name, None)
    if value is None:
        value = os.getenv(name)
    return default if value in (None, "") else value


USE_REAL_AI = _cfg("USE_REAL_AI", True)
FALLBACK_ON_ERROR = _cfg("FALLBACK_ON_ERROR", True)
GEMINI_API_KEY = _cfg("GEMINI_API_KEY")
GEMINI_BASE_URL = _cfg("GEMINI_BASE_URL", "https://generativelanguage.googleapis.com/v1beta/openai/")
GEMINI_EMBEDDING_MODEL = _cfg("GEMINI_EMBEDDING_MODEL", "gemini-embedding-2")
# gemini-embedding-2 는 task_type 대신 글 앞에 작업을 적는다 (ai.google.dev/gemini-api/docs/embeddings)
USE_TASK_PREFIX = GEMINI_EMBEDDING_MODEL.startswith("gemini-embedding-2")
QUERY_PREFIX = "task: search result | query: "
TITLED = re.compile(r"\[([^\]]+)\] ")  # page_content = "[제목] 내용"
KNOWLEDGE_DIR = Path(_cfg("KNOWLEDGE_DIR", BASE_DIR / "knowledge"))
CHROMA_DIR = BASE_DIR / "chroma_db"
COLLECTION = "sleep_regulations"
EMBED_BATCH = 90       # 색인 만들 때 한 번에 임베딩할 문단 수 (무료 한도 분당 100 아래)
EMBED_WAIT_SEC = 61
CHUNKER_VERSION = "v4"  # 자르는 규칙을 바꾸면 올린다 → 색인 다시 만들기 (v4: 벌칙 · 처벌 조문 topic "penalty")

CORE_QUERY = "졸음운전 휴게시간 휴식 규정"

# 질문 단어로 법령 / 일반 자료를 고른다 (노션 「문제 1」, 12개 질의 중 12개가 정답 유형을 놓치지 않음)
LAW_WORDS = ("규정", "법", "조항", "의무", "위반", "허용", "금지", "되나", "근거", "보장",
             # 11/02: 규정을 묻는 낱말 — '연장 운행하면 쉬는 시간은 어떻게 돼?' 가 '어떻게' 때문에 일반 자료로만 가서 법령을 못 찾았음
             "쉬는 시간", "휴게시간", "휴식시간", "연장", "처벌", "벌금", "벌칙", "과태료", "정해져")
GUIDE_WORDS = ("통계", "치사율", "예방", "방법", "주기", "어떻게", "찾", "요령", "건수")

# 차종 → 함께 검색할 vehicle 값 ("all" = 모든 운전자에게 적용)
VEHICLE_SCOPE = {
    "freight": ["freight", "all"],
    "bus_intercity": ["bus_intercity", "bus", "all"],
    "bus_city": ["bus_city", "bus", "all"],
}


# ───────────────────────────────────────────────
# 문서 읽기 · 자르기 (노션 「문제 3」의 chunk_v3)
# ───────────────────────────────────────────────
HISTORY_ONLY = re.compile(r"\[[^\]]*\d{4}\. \d+\. \d+\.[^\]]*\]")  # [본조신설 2018. 2. 12.]
INLINE_HISTORY = re.compile(r"\s*<(?:개정|신설|삭제)[^>]*>")       # <개정 2025. 12. 30.>
MEMO = ("[이 자료에 없는 내용]", "[다른 자료와의 수치 비교 메모]")
SUB_ITEM = re.compile(r"(?:[가-하]\.|\d+\))\s")                   # 목 "가." · 세목 "1)"
NEW_PARA = re.compile(r"(?:[①-⑳]|제\d+조)")
ITEM = re.compile(r"(\d+(?:의\d+)?)\.\s")                         # 호 "23." · "11의2."
PARA = re.compile(r"[①-⑳]")
ARTICLE = re.compile(r"제\d+조(?:의\d+)?(?:\([^)]*\))?")
SECTION = re.compile(r"\[([^\]]+)\]")


def _read_docs():
    """첫 줄 머리말(4칸)을 읽는다. 조항 칸에 '해당 없음' 이 있으면 일반 자료."""
    docs = []
    for path in sorted(KNOWLEDGE_DIR.glob("*.txt")):
        header, _, body = path.read_text(encoding="utf-8").strip().partition("\n")
        fields = [p.split(":", 1)[1].strip() for p in header.split("|")]
        if len(fields) != 4:
            print(f"[rag_service] 머리말 형식이 달라 건너뜀: {path.name}")
            continue
        is_law = "해당 없음" not in fields[1]
        docs.append({
            "file": path.stem,
            "name": fields[0],
            "article": fields[1] if is_law else "",
            "date": fields[2].split(" [")[0],
            "url": fields[3],
            "doc_type": "law" if is_law else "guide",
            "summary": "원문 전재가 아니라" in body[:300],  # 일반 자료 중 요약본 (도로교통공단 — 원문 이용 조건 미확인)
            "paras": [p.strip() for p in re.split(r"\n\s*\n", body) if p.strip()],
        })
    return docs


def _chunk(docs):
    """호 단위(목 · 세목은 앞의 호에 붙임), 연혁 · 메모 제외, '다음 각 호' 머리는 parent 로 보관."""
    out = []
    for d in docs:
        mine, parent = [], ""
        for p in d["paras"]:
            if len(p) < 15 and not SUB_ITEM.match(p):
                continue
            if p[0] in "(※" or p.startswith(MEMO) or HISTORY_ONLY.fullmatch(p):
                continue
            p = INLINE_HISTORY.sub("", p)
            if SUB_ITEM.match(p) and mine:
                mine[-1]["text"] += "\n" + p
                continue
            if d["doc_type"] == "law" and "다음 각 호" in p and not ITEM.match(p):
                parent = p
                continue
            if NEW_PARA.match(p):
                parent = ""
            mine.append({"doc": d, "text": p, "parent": parent})
        out += mine
    return [_with_meta(c) for c in out]


def _with_meta(c):
    d, text, parent = c["doc"], c["text"], c["parent"]
    whole = f"{parent}\n{text}"
    if d["doc_type"] == "law":
        if "벌칙" in d["article"] or "처벌" in d["article"]:
            topic = "penalty"  # 도로교통법 제154조 제3호도 '과로' 를 담고 있어서, 졸음 근거(drowsy = 제45조) 고정에 섞이지 않게 먼저 가름
        elif "휴대용 전화" in text or "영상표시장치" in text:
            topic = "phone"
        elif "휴게시간" in text or "휴식" in whole:  # '휴게' 만 보면 제21조 제3호 '화물자동차 휴게소'(밤샘주차) 까지 휴게 규정이 됨
            topic = "rest"
        elif "과로" in text:
            topic = "drowsy"
        else:
            topic = "other"
        if d["file"].startswith("law_freight"):
            vehicle = "freight"
        elif "노선 여객자동차" in whole:  # 제44조의6 ④ — 노선버스 · 전세버스 전체
            vehicle = "bus"
        elif "시외버스" in whole:
            vehicle = "bus_intercity"
        elif "시내버스" in whole or "마을버스" in whole:
            vehicle = "bus_city"
        elif "여객자동차" in whole or "전세버스" in whole:
            vehicle = "bus"
        else:
            vehicle = "all"
        title = _law_title(d, text, parent)
        source = f"국가법령정보센터, 시행 {d['date']} ({d['url']})"
        content = f"{parent}\n{text}" if parent else text
    else:
        topic, vehicle = "guide", "all"
        section = SECTION.match(text)
        title = f"{d['name']} — {section.group(1)}" if section else d["name"]
        source = f"{d['date']} 발행 자료{' 요약' if d['summary'] else ''} ({d['url']})"
        content = text
    return {
        "page_content": f"[{title}] {content}",  # 긴 표지 유지 (노션 「문제 3」 5-3)
        "metadata": {"file": d["file"], "law": d["name"], "doc_type": d["doc_type"], "topic": topic,
                     "vehicle": vehicle, "title": title, "source": source, "content": content},
    }


def _law_title(d, text, parent):
    """호 단위 제목: '화물자동차 운수사업법 시행규칙 제22조(운수종사자의 준수사항) 제6호'."""
    m = ARTICLE.search(d["article"]) or ARTICLE.search(text)
    title = f"{d['name']} {m.group(0) if m else d['article']}"
    para = PARA.search((parent or text)[:80])
    if para:
        title += f" 제{ord(para.group(0)) - ord('①') + 1}항"
    item = ITEM.match(text)
    if item:
        num, _, sub = item.group(1).partition("의")
        title += f" 제{num}호" + (f"의{sub}" if sub else "")  # "11의2." → 제11호의2
    return title


# ───────────────────────────────────────────────
# 색인 (Chroma) — 처음 검색할 때 1번 만들고 chroma_db/ 에 저장
# ───────────────────────────────────────────────
_store = None
_lock = threading.Lock()


def _fingerprint():
    h = hashlib.sha1(f"{CHUNKER_VERSION}|{GEMINI_EMBEDDING_MODEL}|prefix={USE_TASK_PREFIX}".encode())
    for path in sorted(KNOWLEDGE_DIR.glob("*.txt")):
        h.update(path.name.encode() + path.read_bytes())
    return h.hexdigest()


def _doc_text(text):
    """문서 쪽 형식: 'title: {제목} | text: {내용}' (제목이 없으면 title: none)."""
    m = TITLED.match(text)
    if m:
        return f"title: {m.group(1)} | text: {text[m.end():]}"
    return f"title: none | text: {text}"


def _embeddings():
    from langchain_core.embeddings import Embeddings
    from langchain_openai import OpenAIEmbeddings
    if not GEMINI_API_KEY:
        raise RuntimeError("GEMINI_API_KEY 가 .env 에 없습니다")

    class _GeminiEmbeddings(Embeddings):
        """검색어 / 문서에 다른 작업 표시를 붙여 OpenAIEmbeddings 로 넘김 (gemini-embedding-2 일 때만)."""

        def __init__(self, inner):
            self.inner = inner

        def embed_documents(self, texts):
            return self.inner.embed_documents([_doc_text(t) for t in texts])

        def embed_query(self, text):
            return self.inner.embed_query(QUERY_PREFIX + text)

    inner = OpenAIEmbeddings(
        model=GEMINI_EMBEDDING_MODEL,
        openai_api_key=GEMINI_API_KEY,
        openai_api_base=GEMINI_BASE_URL,
        check_embedding_ctx_length=False,  # 🔴 True 면 OpenAI 토큰 번호를 보내서 Gemini 가 못 알아들음
        chunk_size=100,
        request_timeout=15,
        max_retries=1,  # 실패한 호출도 무료 한도에 포함됨 (노션 「RAG 전체 흐름 테스트」)
    )
    return _GeminiEmbeddings(inner) if USE_TASK_PREFIX else inner


def build_index(force=False):
    """knowledge/ → Chroma. 문서가 그대로면 저장된 색인을 다시 쓴다 (임베딩 호출 없음)."""
    global _store
    from chromadb.config import Settings
    from langchain_chroma import Chroma
    from langchain_core.documents import Document

    with _lock:
        if _store is not None and not force:
            return _store
        fp = _fingerprint()
        fp_file = CHROMA_DIR / "fingerprint.txt"
        if force or not fp_file.exists() or fp_file.read_text() != fp:
            shutil.rmtree(CHROMA_DIR, ignore_errors=True)
            chunks = _chunk(_read_docs())
            if not chunks:
                raise RuntimeError(f"{KNOWLEDGE_DIR} 에 규정 문서(.txt)가 없습니다")
            docs = [Document(page_content=c["page_content"], metadata=c["metadata"]) for c in chunks]
            store = Chroma.from_documents(
                docs[:EMBED_BATCH],
                _embeddings(),
                collection_name=COLLECTION,
                persist_directory=str(CHROMA_DIR),
                collection_metadata={"hnsw:space": "cosine"},
                client_settings=Settings(anonymized_telemetry=False, is_persistent=True),
            )
            # Gemini 임베딩 무료 한도 = 분당 100개 → 문단이 100개를 넘으면 나눠서, 사이에 1분 쉼 (첫 색인 때만)
            for i in range(EMBED_BATCH, len(docs), EMBED_BATCH):
                print(f"[rag_service] 임베딩 무료 한도 때문에 1분 쉬고 이어서 ({i}/{len(docs)})")
                time.sleep(EMBED_WAIT_SEC)
                store.add_documents(docs[i:i + EMBED_BATCH])
            fp_file.write_text(fp)
            print(f"[rag_service] 색인 새로 만듦: 문단 {len(chunks)}개")
        else:
            store = Chroma(
                collection_name=COLLECTION,
                embedding_function=_embeddings(),
                persist_directory=str(CHROMA_DIR),
                client_settings=Settings(anonymized_telemetry=False, is_persistent=True),
            )
        _store = store
        return _store


def _to_item(meta):
    return {"title": meta["title"], "source": meta["source"], "content": meta["content"], "is_real": True}


def _pick(hits, k, per_key="file", cap=1, taken=()):
    """점수 순으로 고르되 같은 key 는 cap 개까지만 (근거가 한 조문으로만 채워지지 않게, 노션 「문제 2」)."""
    out, count = [], {}
    for doc, _ in hits:
        m = doc.metadata
        if m["title"] in taken or any(m["title"] == o["title"] for o in out):
            continue
        key = m[per_key]
        if count.get(key, 0) >= cap:
            continue
        count[key] = count.get(key, 0) + 1
        out.append(m)
        if len(out) == k:
            break
    return out


# ───────────────────────────────────────────────
# /detect 핵심 경로: 제45조 고정 + 휴게 규정
# ───────────────────────────────────────────────
def _real_search_regulations(summary, vehicle, k):
    store = build_index()
    pinned = store.get(where={"$and": [{"doc_type": "law"}, {"topic": "drowsy"}]}, include=["metadatas"])["metadatas"]
    result = pinned[:1]

    conds = [{"doc_type": "law"}, {"topic": "rest"}]
    if vehicle in VEHICLE_SCOPE:
        conds.append({"vehicle": {"$in": VEHICLE_SCOPE[vehicle]}})
    query = f"{CORE_QUERY} {summary}".strip()
    hits = store.similarity_search_with_score(query, k=10, filter={"$and": conds})

    need = k - len(result)
    rest = _pick(hits, need, per_key="law", cap=1)  # 차종을 모르면 화물 1 + 버스 1
    if len(rest) < need:
        rest += _pick(hits, need - len(rest), per_key="file", cap=1, taken={m["title"] for m in rest})
    return [_to_item(m) for m in result + rest]


def _mock(k):
    return [{**m, "is_real": False} for m in MOCK_REGULATIONS[:k]]


def _mock_search_regulations(summary="", vehicle=None, k=3):
    return _mock(k)


def search_regulations(summary="", vehicle=None, k=3):
    """졸음 확정 때 Agent 에게 줄 규정. 1번째는 항상 도로교통법 제45조(졸음운전의 법적 근거).

    summary : LLM 상황 요약 (검색어에 붙이면 '2시간 연속운전' 조문이 더 잘 모임 — 노션 「핵심 경로 테스트」)
    vehicle : "freight" / "bus_intercity" / "bus_city" / None(차종 정보 없음 → 화물 · 여객 규정을 하나씩, 팀장 확인 10.14)
    """
    if not USE_REAL_AI:
        return _mock_search_regulations(summary, vehicle, k)
    try:
        return _normalize(_real_search_regulations(summary, vehicle, k))
    except Exception as e:
        if not FALLBACK_ON_ERROR:
            raise
        print(f"[rag_service] 규정 검색 실패 → 대표 규정 사용: {e}")
        return _mock_search_regulations(summary, vehicle, k)


# ───────────────────────────────────────────────
# 채팅 · Agent 도구: 질문으로 검색
# ───────────────────────────────────────────────
def _route(query):
    # 11/05: '방법' 의 '법' 이 LAW_WORDS 의 "법" 에 걸려 '예방 방법' · '쉼터 이용 방법' 이 both 로 가던 것 고침
    #        ('방법' 은 GUIDE_WORDS 에서만 셈, 다른 법령 낱말이 있으면 그대로 both)
    law = any(w in query.replace("방법", "") for w in LAW_WORDS)
    guide = any(w in query for w in GUIDE_WORDS)
    if law and not guide:
        return "law"
    if guide and not law:
        return "guide"
    return "both"


def _real_search_by_text(query, k):
    store = build_index()
    route = _route(query)
    if route == "both":  # 애매하면 법령 (k-1) + 일반 자료 1 (노션 「문제 1」 권장 구성)
        law = store.similarity_search_with_score(query, k=10, filter={"doc_type": "law"})
        guide = store.similarity_search_with_score(query, k=4, filter={"doc_type": "guide"})
        picked = _pick(law, k - 1, cap=2) + _pick(guide, 1, cap=2)
    else:
        hits = store.similarity_search_with_score(query, k=10, filter={"doc_type": route})
        picked = _pick(hits, k, cap=2)
    return [_to_item(m) for m in picked]


def _mock_search_by_text(query, k=4):
    return _mock(k)


def search_by_text(query, k=4):
    """질문 → 관련 규정 k개. 답을 만드는 일(생성)은 chat_service / agent_service 몫."""
    if not USE_REAL_AI:
        return _mock_search_by_text(query, k)
    try:
        return _normalize(_real_search_by_text(query, k))
    except Exception as e:
        if not FALLBACK_ON_ERROR:
            raise
        print(f"[rag_service] 검색 실패 → 대표 규정 사용: {e}")
        return _mock_search_by_text(query, k)


def _normalize(items):
    """계약 보증: title · source · content 는 항상 문자열, is_real 은 항상 bool, 빈 것은 버림."""
    out = []
    for it in items or []:
        item = {key: str(it.get(key) or "").strip() for key in ("title", "source", "content")}
        item["is_real"] = it.get("is_real") is True
        if item["content"]:
            out.append(item)
    return out or _mock(3)


# ───────────────────────────────────────────────
# 대표 규정 3개 (가짜 / 실패 시) — 원문 그대로, 확인일 2026. 10. 13.
# ───────────────────────────────────────────────
MOCK_REGULATIONS = [
    {
        "title": "도로교통법 제45조(과로한 때 등의 운전 금지) 제1항",
        "source": "국가법령정보센터, 시행 2026. 10. 13.",
        "content": "자동차등(개인형 이동장치는 제외한다. 이하 이 조에서 같다) 또는 노면전차의 운전자는 제44조에 따른 "
                   "술에 취한 상태 외에 과로, 질병 또는 약물의 영향과 그 밖의 사유로 정상적으로 운전하지 못할 우려가 "
                   "있는 상태에서 자동차등 또는 노면전차를 운전하여서는 아니 된다.",
    },
    {
        "title": "화물자동차 운수사업법 시행규칙 제22조(운수종사자의 준수사항) 제6호",
        "source": "국가법령정보센터, 시행 2026. 6. 30.",
        "content": "휴게시간 없이 2시간 연속운전한 후에는 15분 이상의 휴게시간을 가질 것. 다만, 제21조제23호 각 목의 "
                   "어느 하나에 해당하는 경우에는 1시간까지 연장운행을 할 수 있으며 운행 후 30분 이상의 휴게시간을 "
                   "가져야 한다.",
    },
    {
        "title": "여객자동차 운수사업법 시행규칙 제44조의6(운수종사자의 휴식시간 보장) 제3항 제2호",
        "source": "국가법령정보센터, 시행 2026. 9. 15.",
        "content": "운수종사자가 휴식시간 없이 2시간 연속 운전한 경우에는 휴게소 등에서 15분 이상의 휴식시간을 보장할 것. "
                   "다만, 천재지변, 교통사고, 차량고장 또는 극심한 교통정체 등의 사유로 휴게소 진입이 불가능한 경우 등 "
                   "연장운행이 필요한 경우에는 1시간까지 연장운행을 하게 할 수 있으며, 운행 후 30분 이상의 휴식시간을 "
                   "보장할 것",
    },
]


if __name__ == "__main__":
    # 직접 확인: (sleep_detector_api 폴더에서) python -m services.rag_service
    for r in search_regulations("운전자가 약 2초간 눈을 감은 미세수면 상태로 보입니다. 10분 안에 두 번째 졸음입니다."):
        print("-", r["title"])
    for q in ("핸즈프리 장치는 운전 중에 써도 되나", "졸음 예방을 위한 환기 주기", "시내버스 1회 운행 종료 후 휴식시간"):
        print(q)
        for r in search_by_text(q):
            print("   -", r["title"])
