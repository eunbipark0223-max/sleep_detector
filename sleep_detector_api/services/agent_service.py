# ═══════════════════════════════════════════════════════════════
# services/agent_service.py — Agent 단계 · 안내문 · 보고서 · 기사 음성 보고  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0 (음성 보고는 P1)
# 수업 원본: road_hazard_api/services/agent_service.py (🟡 수정, 딥러닝 22차시)
#
# [이 파일이 하는 일]
#   - 도구: 최근 졸음 기록 조회 · 규정 검색 (Function Calling)
#   - 만드는 것: ① 단계 ② 기사 안내문 guidance ③ 관리자 보고서 report(5칸) ④ 기사 음성 보고 driver_voice
#   - 바닥 · 천장 규칙: 규칙 단계 ≤ Agent 단계 ≤ 규칙 단계 + 1 (최대 3) — 서버 코드가 한 번 더 검사
#   - driver_voice 숫자는 sleep_state 의 facts 와 같아야 함 → 다르거나 길거나 비면 템플릿 문장으로 교체
#
# [만들 것 (이름 약속 — detect.py 가 이 이름으로 부름)]
#   - generate_response(eye, analysis, regulations, facts, rule_stage, location="")
#       eye        : face_service 결과 + 앱 숫자 (reason · closed_sec · perclos · eye_open_prob · ear)
#       analysis   : llm_service.interpret_situation 결과 {"summary", "is_real"}
#       regulations: rag_service.search_regulations 결과 [{title, source, content, is_real}]
#       facts      : {"sleep_count_10min", "last_closed_sec", "drive_min"} — 숫자는 코드가 센 값
#       rule_stage : sleep_state 가 정한 규칙 단계 (바닥)
#     → {"stage", "guidance", "driver_voice", "report"{situation · stage_reason · regulation · recommended_action · location},
#        "is_real", "voice_is_real", "used_tools"}
#
# [주의]
#   - '신고할까?' → '몇 단계인가?' 로 질문만 바뀜
#   - 퀴즈 출제 · 채점은 하지 않는다 (voice_quiz_service)
#   - 실패하면 규칙 단계 + 기본 안내문 + 템플릿 음성 보고
#   - 운행 2시간 미만이면 휴게시간 규정은 '참고'로만 (B 요청 10/14 — RAG 는 근거만, 판단은 Agent)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 6장
# ═══════════════════════════════════════════════════════════════

import json
import re

import config
from services import rag_service, sleep_state

USE_REAL_AI = config.USE_REAL_AI
FALLBACK_ON_ERROR = config.FALLBACK_ON_ERROR
AGENT_TIMEOUT_SEC = 20     # 실시간 경고 경로라 오래 기다리지 않는다
MAX_TOOL_TURNS = 3         # 도구를 부르는 횟수 제한 (수업 안전장치 ①)

GUIDANCE = {
    1: "창문을 열고 환기해 주세요. 졸음이 계속되면 쉬어 가세요.",
    2: f"가까운 졸음쉼터에서 {config.REST_MIN}분 이상 쉬어 주세요.",
    3: "안전한 곳에 바로 정차해 주세요. 관리자에게 알렸습니다.",
}
ACTION = {
    1: "기록만 확인 (졸음이 반복되면 연락)",
    2: "기사에게 연락해 휴식 여부 확인",
    3: "즉시 기사에게 연락하고 정차 확인",
}
REASON_KO = {"microsleep": "미세수면", "perclos": "피로 누적"}


# ───────────────────────────────────────────────
# 숫자 · 템플릿 (AI 없이도 항상 말함)
# ───────────────────────────────────────────────
def _clamp_stage(stage, rule_stage):
    """바닥 · 천장 규칙: 규칙 단계 ≤ 단계 ≤ min(규칙 + 1, 3)"""
    lo = max(1, int(rule_stage))
    hi = min(lo + config.AGENT_MAX_STEP_UP, config.STAGE_MAX)
    try:
        s = int(stage)
    except (TypeError, ValueError):
        s = lo
    return max(lo, min(hi, s))


def _drive_text(drive_min):
    h, m = divmod(int(drive_min or 0), 60)
    return f"{h}시간 {m}분째" if h and m else (f"{h}시간째" if h else f"{m}분째")


def _template_voice(stage, facts, guidance):
    n = int(facts.get("sleep_count_10min") or 1)
    closed = float(facts.get("last_closed_sec") or 0)
    if stage == 1:
        if closed <= 0:   # 피로 누적(PERCLOS) — 한 번에 감은 초가 없음 → 없는 '1초' 를 말하지 않게 (11/02 KPI ⑥)
            return f"졸음이 감지됐습니다. 최근 눈을 자주 감고 있습니다. {guidance}"
        return f"졸음이 감지됐습니다. 약 {max(1, round(closed))}초 동안 눈을 감았습니다. {guidance}"
    if stage == 2:
        drive = f" 운행 {_drive_text(facts.get('drive_min'))}입니다." if int(facts.get("drive_min") or 0) >= 1 else ""
        return f"최근 10분 동안 {n}번 졸았습니다.{drive} {guidance}"
    return f"최근 10분 동안 {n}번 졸았습니다. 관리자에게 알렸습니다. 안전한 곳에 바로 정차해 주세요."


def _allowed_numbers(facts):
    """음성 보고에 나와도 되는 숫자: facts 의 값과 그 반올림 + 기준 숫자(10분 · 15분 · 2시간)"""
    n = int(facts.get("sleep_count_10min") or 0)
    sec = float(facts.get("last_closed_sec") or 0)
    dm = int(facts.get("drive_min") or 0)
    h, m = divmod(dm, 60)
    ok = {str(n), str(round(sec)), f"{sec:g}", f"{sec:.1f}", str(dm), str(h), str(m),
          str(config.WINDOW_MIN), str(config.REST_MIN), str(config.DRIVE_LIMIT_MIN // 60 or config.DRIVE_LIMIT_MIN)}
    return ok


_NATIVE = {"한": 1, "두": 2, "세": 3, "네": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9, "열": 10, "스무": 20}
# 한글로 쓴 숫자 + 단위만 본다 (11/02 KPI ⑥ — 아라비아 숫자만 검사해서 '세 번 졸았습니다' 가 그대로 통과했음)
#   고유어(한 · 두 · 세 …) + 번 · 회 · 시간 · 분 · 초, 한자어(일 · 이 · 삼 · 십 …) + 분 · 초 — '이번 휴식' 같은 말은 안 잡히게
_KO_COUNT = re.compile(r"(열한|열두|열세|열네|다섯|여섯|일곱|여덟|아홉|스무|[한두세네열])\s*(번|회|차례|시간|분|초)")
_KO_SINO = re.compile(r"(?<![가-힣])([일이삼사오육칠팔구십백]+)\s*(분|초)(?![가-힣])")
_IDIOMS = re.compile(r"다시\s*한\s*번|한\s*번\s*더")   # '다시 한번' · '한 번 더' 는 숫자가 아님


def _korean_numbers(s):
    """음성 보고 속 한글 숫자: '세 번' → 3, '십 분' → 10, '이 초' → 2"""
    from services.voice_quiz_service import extract_numbers
    s = _IDIOMS.sub(" ", s)
    out = []
    for word, _unit in _KO_COUNT.findall(s):
        out.append(_NATIVE[word] if word in _NATIVE else 10 + _NATIVE[word[1:]])
    for word, _unit in _KO_SINO.findall(s):
        out += extract_numbers(word)
    return out


def _check_voice(text, facts):
    """숫자가 facts 와 다르거나, 너무 길거나, 비어 있으면 None (→ 템플릿). 한글로 쓴 숫자('세 번')도 검사"""
    if not isinstance(text, str):
        return None
    s = " ".join(text.split()).strip("\"'“”‘’ ")
    if not s or not re.search(r"[가-힣]", s) or len(s) > config.DRIVER_VOICE_MAX_CHARS:
        return None
    allowed = _allowed_numbers(facts)
    if any(x not in allowed for x in re.findall(r"\d+(?:\.\d+)?", s)):
        return None
    if any(str(n) not in allowed for n in _korean_numbers(s)):
        return None
    return s


def _base_report(eye, analysis, regulations, rule_stage, location):
    reason = REASON_KO.get(eye.get("reason"), "졸음")
    return {
        "situation": analysis.get("summary") or f"{reason} 감지",
        "stage_reason": f"10분 안 졸음 횟수 기준 {rule_stage}단계",
        "regulation": regulations[0]["title"] if regulations else "",
        "recommended_action": ACTION.get(rule_stage, ACTION[1]),
        "location": location,
    }


def _normalize(raw, eye, analysis, regulations, facts, rule_stage, location):
    """AI 답 → 정해진 모양. 단계는 바닥 · 천장, 빈 칸은 기본 문장, 음성 보고는 숫자 검사."""
    raw = raw if isinstance(raw, dict) else {}
    stage = _clamp_stage(raw.get("stage", rule_stage), rule_stage)
    guidance = str(raw.get("guidance") or "").strip() or GUIDANCE[stage]

    report = _base_report(eye, analysis, regulations, stage, location)
    for k in ("situation", "stage_reason", "regulation", "recommended_action"):
        v = (raw.get("report") or {}).get(k) if isinstance(raw.get("report"), dict) else None
        if isinstance(v, str) and v.strip():
            report[k] = v.strip()[:200]
    report["location"] = location   # 위치는 AI 가 아니라 앱 값 그대로

    voice = _check_voice(raw.get("driver_voice"), facts)
    voice_is_real = voice is not None and bool(raw)
    if voice is None:
        voice = _template_voice(stage, facts, guidance)
    return {"stage": stage, "guidance": guidance, "driver_voice": voice, "report": report,
            "voice_is_real": voice_is_real}


# ───────────────────────────────────────────────
# 가짜 (규칙대로)
# ───────────────────────────────────────────────
def _mock_generate(eye, analysis, regulations, facts, rule_stage, location):
    return {}   # 빈 답 → _normalize 가 규칙 단계 · 기본 안내문 · 템플릿 음성으로 채움


# ───────────────────────────────────────────────
# 진짜 (Gemini Function Calling, 딥러닝 22차시 실습 4 방식)
# ───────────────────────────────────────────────
TOOLS = [
    {"type": "function", "function": {
        "name": "get_recent_sleeps",
        "description": "이 기사의 최근 10분 졸음 기록(횟수 · 마지막 눈 감은 시간 · 현재 단계)과 연속 운전 시간을 조회한다. 단계를 올릴지 판단할 때 쓴다.",
        "parameters": {"type": "object", "properties": {}, "required": []}}},
    {"type": "function", "function": {
        "name": "search_regulations",
        "description": "졸음운전 · 휴게시간 관련 법령과 예방 자료를 검색한다. 안내문이나 보고서에 근거가 더 필요할 때 쓴다.",
        "parameters": {"type": "object", "properties": {"query": {"type": "string", "description": "검색할 내용 (한국어)"}},
                       "required": ["query"]}}},
]

SYSTEM_PROMPT = """너는 화물 · 버스 운수회사 졸음운전 관제 Agent 다. 졸음이 확정된 기사의 경고 단계와 안내를 정한다.

단계: 1 주의 / 2 휴식 권고 / 3 긴급 (관리자 호출).
규칙:
- 규칙 단계(rule_stage)보다 낮게 정하지 않는다. 올리는 것은 1단계까지만, 최대 3.
- 단계를 올리려면 근거(짧은 간격의 반복 졸음, 높은 PERCLOS, 긴 눈 감김, 긴 운행 시간)가 있어야 한다. 필요하면 도구를 써서 확인한다.
- 숫자는 facts 에 있는 값만 쓴다. 새 숫자를 만들지 않는다.
- 연속 운전이 {limit}분 미만이면 휴게시간 규정(2시간마다 15분 휴식 등)은 단계 근거로 쓰지 말고 참고로만 언급한다.
- driver_voice 는 기사가 운전 중에 귀로 듣는 말이다. 2~3문장, {max_chars}자 이내, 존댓말, 영어 금지.
  기사가 자기 상태를 숫자로 듣게 첫 문장에 facts 의 숫자를 꼭 넣는다 (2단계 이상: "최근 10분 동안 N번 졸았습니다", 1단계: "약 N초 동안 눈을 감았습니다").

반드시 아래 JSON 하나로만 답한다:
{{"stage": 1~3, "guidance": "기사 안내 한 문장", "driver_voice": "음성 보고",
  "report": {{"situation": "", "stage_reason": "", "regulation": "근거 규정 제목", "recommended_action": "관리자가 할 일"}}}}"""

_client = None


def _get_client():
    global _client
    if _client is None:
        from openai import OpenAI
        if not config.GEMINI_API_KEY:
            raise RuntimeError("GEMINI_API_KEY 가 .env 에 없습니다")
        _client = OpenAI(api_key=config.GEMINI_API_KEY, base_url=config.GEMINI_BASE_URL,
                         timeout=AGENT_TIMEOUT_SEC, max_retries=0)   # 실패도 무료 한도에 들어감
    return _client


def _run_tool(name, args, user_id, facts):
    if name == "get_recent_sleeps":
        return {**sleep_state.facts(user_id), "drive_min": facts.get("drive_min", 0)}
    if name == "search_regulations":
        q = str((args or {}).get("query") or "졸음운전 휴게시간 규정")
        return [{"title": r["title"], "content": r["content"][:300]} for r in rag_service.search_by_text(q, k=3)]
    return {"error": f"없는 도구: {name}"}   # 안전장치 ②: 화이트리스트


def _extract_json(text):
    if not isinstance(text, str):
        return {}
    m = re.search(r"\{.*\}", text, re.S)
    if not m:
        return {}
    try:
        return json.loads(m.group(0))
    except ValueError:
        return {}


def _real_generate(eye, analysis, regulations, facts, rule_stage, location, user_id):
    user = {
        "rule_stage": rule_stage,
        "facts": facts,
        "eye": {k: eye.get(k) for k in ("reason", "closed_sec", "perclos", "eye_open_prob", "ear", "method")},
        "summary": analysis.get("summary", ""),
        "regulations": [{"title": r["title"], "content": r["content"][:300]} for r in regulations],
    }
    messages = [
        {"role": "system", "content": SYSTEM_PROMPT.format(limit=config.DRIVE_LIMIT_MIN, max_chars=config.DRIVER_VOICE_MAX_CHARS)},
        {"role": "user", "content": json.dumps(user, ensure_ascii=False)},
    ]
    used = []
    for _ in range(MAX_TOOL_TURNS + 1):
        r = _get_client().chat.completions.create(
            model=config.GEMINI_MODEL, messages=messages, tools=TOOLS, temperature=0.2)
        msg = r.choices[0].message
        if not msg.tool_calls:
            return _extract_json(msg.content), used
        messages.append({"role": "assistant", "content": msg.content or "",
                         "tool_calls": [tc.model_dump() for tc in msg.tool_calls]})
        for tc in msg.tool_calls:
            try:
                args = json.loads(tc.function.arguments or "{}")
            except ValueError:
                args = {}
            used.append(tc.function.name)
            result = _run_tool(tc.function.name, args, user_id, facts)
            messages.append({"role": "tool", "tool_call_id": tc.id, "content": json.dumps(result, ensure_ascii=False)})
    raise RuntimeError("도구 호출이 너무 많습니다")


def generate_response(eye, analysis, regulations, facts, rule_stage, location="", user_id=None):
    """졸음 확정 1건 → 단계 · 안내문 · 보고서 · 기사 음성 보고. 항상 정해진 모양으로 돌려준다."""
    eye, analysis, regulations, facts = eye or {}, analysis or {}, regulations or [], facts or {}
    raw, used, is_real = {}, [], False
    if USE_REAL_AI:
        try:
            raw, used = _real_generate(eye, analysis, regulations, facts, rule_stage, location, user_id)
            is_real = bool(raw)
            if not raw:
                print("[agent_service] JSON 이 아닌 답 → 기본 규칙 사용")
        except Exception as e:
            if not FALLBACK_ON_ERROR:
                raise
            print(f"[agent_service] Agent 실패 → 기본 규칙 사용: {type(e).__name__} {str(e)[:120]}")
    else:
        raw = _mock_generate(eye, analysis, regulations, facts, rule_stage, location)

    out = _normalize(raw, eye, analysis, regulations, facts, rule_stage, location)
    out.update({"is_real": is_real, "used_tools": used})
    if not is_real:
        out["voice_is_real"] = False
    return out
