# ═══════════════════════════════════════════════════════════════
# services/llm_service.py — LLM 졸음 상황 요약
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P0
# 수업 원본: road_hazard_api/services/llm_service.py (🟡 수정, 딥러닝 20차시)
#
# [이 파일이 하는 일]
#   - 입력: 사진 + 눈 뜸 확률 · 감김 시간 · PERCLOS · EAR · 졸음 종류
#   - 출력: 관리자가 읽을 한두 문장 (사진과 숫자만 근거, 추측 금지)
#   - Gemini — 수업의 OpenAI 호환 방식 그대로, 주소와 모델 이름만 .env 값으로
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - interpret_situation(image_path, eye) → {"summary": str, "model": str, "is_real": bool}
#       eye = {"reason", "closed_sec", "perclos", "eye_open_prob", "ear", "sleep_count_10min"} (없는 칸은 빼도 됨)
#       is_real = False 면 AI 가 아닌 템플릿 문장 (관리자 웹 · 로그에서 진짜 / 가짜 구분용)
#
# [주의]
#   - 실패하면 기본 문장 (FALLBACK_ON_ERROR) — 숫자로 만든 템플릿이라 내용은 항상 맞음
#   - 요약 속 숫자가 입력과 다르면 템플릿으로 교체 ("프롬프트는 부탁, 코드는 보증")
#   - 무료 등급은 모델마다 하루 20회 정도 → 재시도 없이 주 모델 1회 + 대체 모델 1회만
#   - 기본 모델 gemini-3.5-flash-lite (10.14 확정 — 3.8-flash 는 503 · 1분 넘는 응답 반복)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 · 노션 「핵심 경로 테스트」
# ═══════════════════════════════════════════════════════════════

import base64
import mimetypes
import os
import re
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
GEMINI_MODEL = _cfg("GEMINI_MODEL", "gemini-3.5-flash-lite")
LLM_FALLBACK_MODEL = _cfg("LLM_FALLBACK_MODEL", "gemini-3.1-flash-lite")  # 10.13 정상 응답 확인
LLM_TIMEOUT_SEC = 15       # 실시간 경고 경로라 오래 기다리지 않는다
SUMMARY_MAX_CHARS = 120    # 관리자 웹 한 줄 카드

REASON_KO = {"microsleep": "미세수면", "perclos": "피로 누적"}
ORDINAL_KO = {1: "첫", 2: "두", 3: "세", 4: "네", 5: "다섯"}

SYSTEM_PROMPT = """너는 화물 · 버스 운수회사 졸음운전 관제 시스템의 상황 요약 담당이다.
운전자 얼굴 사진 1장과 판정 숫자를 받아, 관리자가 한눈에 읽을 한국어 한두 문장으로 요약한다.

규칙:
- 사진에 보이는 것과 주어진 숫자만 근거로 한다. 원인 · 건강 상태 · 감정은 추측하지 않는다.
- 숫자는 관리자에게 필요한 것만 자연스럽게 쓴다 (눈 감은 시간, 10분 안 몇 번째 졸음). 확률 · EAR 은 쓰지 않아도 된다.
- 주어진 숫자를 바꾸거나 새 숫자를 만들지 않는다. 시간은 "약 2초"처럼 반올림해도 된다.
- 영어 용어를 쓰지 않는다 (microsleep → 미세수면, PERCLOS → 눈 감은 비율).
- 사진에서 눈이 잘 안 보이면 숫자만으로 요약한다.
- 요약 문장만 출력한다. 따옴표 · 머리말 · 사족 금지.

예시)
입력: 졸음 종류 미세수면, 연속 감김 2.1초, 최근 30초 눈 감은 비율 33%, 10분 안 2번째 졸음
출력: 운전자가 약 2초간 눈을 감은 미세수면 상태로 보입니다. 10분 안에 두 번째 졸음입니다."""


# ───────────────────────────────────────────────
# 입력 정리 · 템플릿 (가짜 / 실패 시)
# ───────────────────────────────────────────────
def _num(eye, key):
    try:
        return float(eye[key]) if eye.get(key) is not None else None
    except (TypeError, ValueError):
        return None


def _facts_text(eye):
    """LLM 에게 줄 숫자 한 줄. 없는 칸은 뺀다."""
    parts = []
    if eye.get("reason") in REASON_KO:
        parts.append(f"졸음 종류 {REASON_KO[eye['reason']]}")
    if (v := _num(eye, "closed_sec")) is not None:
        parts.append(f"연속 감김 {v:g}초")
    if (v := _num(eye, "perclos")) is not None:
        parts.append(f"최근 30초 눈 감은 비율 {round(v * 100)}%")
    if (v := _num(eye, "eye_open_prob")) is not None:
        parts.append(f"눈 뜸 확률 {v:g}")
    if (v := _num(eye, "ear")) is not None:
        parts.append(f"EAR {v:g}")
    if (v := _num(eye, "sleep_count_10min")) is not None:
        parts.append(f"10분 안 {int(v)}번째 졸음")
    return ", ".join(parts) or "판정 숫자 없음"


def _template(eye):
    """AI 없이 숫자로 만드는 기본 문장 (기획안 6-1 출력 예 모양)."""
    closed, perclos, count = _num(eye, "closed_sec"), _num(eye, "perclos"), _num(eye, "sleep_count_10min")
    if eye.get("reason") == "perclos" and perclos is not None:
        first = f"최근 30초 중 {round(perclos * 100)}% 동안 눈을 감아 피로가 누적된 상태로 보입니다."
    elif closed is not None:
        first = f"운전자가 약 {max(1, round(closed))}초간 눈을 감은 미세수면 상태로 보입니다."
    else:
        first = "운전자의 졸음이 감지되었습니다."
    if count:
        n = int(count)
        first += f" 10분 안에 {ORDINAL_KO[n]} 번째 졸음입니다." if n in ORDINAL_KO else f" 10분 안에 {n}번째 졸음입니다."
    return first


def _allowed_numbers(eye):
    """요약에 나와도 되는 숫자들 (입력값과 그 반올림, 10분 · 30초 같은 기준 숫자)."""
    ok = {"10", "30"}
    for key in ("closed_sec", "perclos", "eye_open_prob", "ear", "sleep_count_10min"):
        v = _num(eye, key)
        if v is None:
            continue
        for x in (v, v * 100) if key == "perclos" else (v,):
            ok |= {f"{x:g}", str(round(x)), f"{x:.1f}", f"{x:.2f}"}
    return ok


# ───────────────────────────────────────────────
# 진짜 (Gemini)
# ───────────────────────────────────────────────
_client = None


def _get_client():
    global _client
    if _client is None:
        from openai import OpenAI
        if not GEMINI_API_KEY:
            raise RuntimeError("GEMINI_API_KEY 가 .env 에 없습니다")
        # max_retries=0: 실패한 호출도 무료 한도에 포함됨 → 재시도는 아래에서 대체 모델로 1번만
        _client = OpenAI(api_key=GEMINI_API_KEY, base_url=GEMINI_BASE_URL, timeout=LLM_TIMEOUT_SEC, max_retries=0)
    return _client


def _image_part(image_path):
    if not image_path or not Path(image_path).is_file():
        return None
    mime = mimetypes.guess_type(str(image_path))[0] or "image/jpeg"
    data = base64.b64encode(Path(image_path).read_bytes()).decode()
    return {"type": "image_url", "image_url": {"url": f"data:{mime};base64,{data}"}}


def _real_interpret(image_path, eye):
    content = [{"type": "text", "text": f"입력: {_facts_text(eye)}"}]
    image = _image_part(image_path)
    if image:
        content.append(image)
    messages = [{"role": "system", "content": SYSTEM_PROMPT}, {"role": "user", "content": content}]

    errors = []
    for model in dict.fromkeys([GEMINI_MODEL, LLM_FALLBACK_MODEL]):  # 같은 이름이면 1번만
        try:
            r = _get_client().chat.completions.create(
                model=model, messages=messages, temperature=0.2, reasoning_effort="low")
            return r.choices[0].message.content, model
        except Exception as e:
            errors.append(f"{model}: {type(e).__name__} {str(e)[:120]}")
    raise RuntimeError(" / ".join(errors))


def _normalize(text, eye):
    """코드펜스 · 따옴표 · 머리말 제거 → 길이 제한 → 숫자 검사. 통과 못 하면 None."""
    if not isinstance(text, str):
        return None
    s = re.sub(r"```[a-z]*", "", text).strip()
    s = re.sub(r"^(요약|출력)\s*[:：]\s*", "", s)
    s = " ".join(s.split()).strip("\"'“”‘’ ")
    if not s or not re.search(r"[가-힣]", s):
        return None
    if len(s) > SUMMARY_MAX_CHARS:  # 문장 끝에서 자르기
        cut = s[:SUMMARY_MAX_CHARS]
        end = max(cut.rfind("다."), cut.rfind("요."))
        s = cut[: end + 2] if end > 0 else cut.rstrip() + "…"
    allowed = _allowed_numbers(eye)
    if any(n not in allowed for n in re.findall(r"\d+(?:\.\d+)?", s)):
        return None
    return s


def interpret_situation(image_path, eye):
    """졸음 확정 사진 + 판정 숫자 → 관리자용 상황 요약.

    image_path : 졸음 의심 사진 경로 (없거나 못 읽으면 숫자만으로 요약)
    eye        : 판정 숫자 dict (기획안 9-1 · 9-4 의 칸 이름)
    """
    eye = eye or {}
    if not USE_REAL_AI:
        return {"summary": _template(eye), "model": "mock", "is_real": False}
    try:
        raw, model = _real_interpret(image_path, eye)
    except Exception as e:
        if not FALLBACK_ON_ERROR:
            raise
        print(f"[llm_service] 요약 실패 → 기본 문장 사용: {e}")
        return {"summary": _template(eye), "model": "fallback", "is_real": False}
    summary = _normalize(raw, eye)
    if summary is None:
        print(f"[llm_service] 요약 검사 불통과 → 기본 문장 사용: {str(raw)[:80]!r}")
        return {"summary": _template(eye), "model": f"{model}(rejected)", "is_real": False}
    return {"summary": summary, "model": model, "is_real": True}


if __name__ == "__main__":
    # 직접 확인: (sleep_detector_api 폴더에서) python -m services.llm_service [사진 경로]
    import sys
    sample = {"reason": "microsleep", "closed_sec": 2.1, "perclos": 0.33, "eye_open_prob": 0.08, "ear": 0.16,
              "sleep_count_10min": 2}
    print(interpret_situation(sys.argv[1] if len(sys.argv) > 1 else None, sample))
