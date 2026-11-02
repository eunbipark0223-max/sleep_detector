# ═══════════════════════════════════════════════════════════════
# tools/kpi6_voice.py — KPI ⑥ 기사 음성 보고 숫자 정확도
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1 (KPI ⑥)   |   서버 코드가 아니라 PC 에서 돌리는 시험 도구
#
# [하는 일]
#   A. 숫자 검사 시험 (AI 없음): agent_service._check_voice 가 틀린 숫자(아라비아 · 한글)는 거절하고,
#      맞는 숫자 · 보통 말('이번 휴식', '다시 한번')은 통과시키는지 — 기대값과 비교
#   B. 실제 Gemini 시험 (--real): 1 · 2 · 3단계 상황 8가지로 Agent 가 만든 음성 보고(driver_voice)를 받아
#      ① LLM 이 쓴 숫자가 기록(facts)과 맞는가 ② 틀리면 템플릿으로 바뀌었는가 ③ 꼭 넣을 숫자를 넣었는가
#   목표 (기획안 KPI ⑥): 기사가 듣는 최종 음성 보고의 숫자 틀림 0건
#
# [실행] (sleep_detector_api 폴더)
#   venv\Scripts\python tools/kpi6_voice.py           ← A 만 (무료)
#   venv\Scripts\python tools/kpi6_voice.py --real    ← A + B (Gemini 를 8~24번 부름, .env 키 필요)
#
# 자세한 내용: 「파이널 프로젝트 최종 기획안 10.13」 6-6 · 10장 KPI ⑥
# ═══════════════════════════════════════════════════════════════
import io
import os
import re
import sys
from contextlib import redirect_stdout

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)
os.chdir(BASE)

with redirect_stdout(io.StringIO()):
    from services import agent_service as ag  # noqa: E402

FACTS = {"sleep_count_10min": 2, "last_closed_sec": 2.1, "drive_min": 75}

# (문장, 통과해야 하나) — FACTS 기준: 2번 · 2.1초 · 운행 75분(1시간 15분)
CHECK_CASES = [
    ("최근 10분 동안 2번 졸았습니다.", True),
    ("최근 10분 동안 3번 졸았습니다.", False),
    ("최근 10분 동안 세 번 졸았습니다.", False),          # 한글 숫자 (11/02 전엔 통과하던 빈틈)
    ("최근 십 분 동안 두 번 졸았습니다.", True),
    ("약 다섯 초 동안 눈을 감았습니다.", False),
    ("약 이 초 동안 눈을 감았습니다.", True),
    ("약 2초 동안 눈을 감았습니다.", True),
    ("운행 1시간 15분째입니다.", True),
    ("운행 한 시간 십오 분째입니다.", True),
    ("운행 3시간째입니다.", False),
    ("이번 휴식은 꼭 지켜 주세요.", True),                 # '이번' 을 숫자 2 로 읽지 않기
    ("다시 한번 말씀드립니다. 최근 10분 동안 2번 졸았습니다.", True),
    ("한 번 더 졸면 관리자에게 알립니다.", True),
    ("15분 이상 쉬어 가세요.", True),                      # 규정 숫자 (REST_MIN)
    ("최근 10분 동안 두 번 졸았습니다. 열다섯 번째 경고입니다.", False),
]

# (이름, 규칙 단계, facts, 졸음 종류)
SCENARIOS = [
    ("1단계 · 짧게 감음", 1, {"sleep_count_10min": 1, "last_closed_sec": 1.8, "drive_min": 12}, "microsleep"),
    ("1단계 · 운행 1시간 35분", 1, {"sleep_count_10min": 1, "last_closed_sec": 2.4, "drive_min": 95}, "microsleep"),
    ("1단계 · 피로 누적(PERCLOS)", 1, {"sleep_count_10min": 1, "last_closed_sec": 0, "drive_min": 50}, "perclos"),
    ("2단계 · 10분 안 2번", 2, {"sleep_count_10min": 2, "last_closed_sec": 2.1, "drive_min": 40}, "microsleep"),
    ("2단계 · 운행 2시간 10분", 2, {"sleep_count_10min": 2, "last_closed_sec": 3.0, "drive_min": 130}, "microsleep"),
    ("2단계 · 출발 직후", 2, {"sleep_count_10min": 2, "last_closed_sec": 1.6, "drive_min": 0}, "microsleep"),
    ("3단계 · 10분 안 3번", 3, {"sleep_count_10min": 3, "last_closed_sec": 2.6, "drive_min": 75}, "microsleep"),
    ("3단계 · 10분 안 4번", 3, {"sleep_count_10min": 4, "last_closed_sec": 1.9, "drive_min": 200}, "microsleep"),
]
REGULATIONS = [{"title": "화물자동차 운수사업법 시행규칙 제22조", "source": "law.go.kr",
                "content": "운수종사자는 2시간 연속 운전 후 15분 이상 휴식"}]


def numbers_in(text):
    """문장 속 숫자 전부 (아라비아 + 한글 숫자+단위)"""
    return [x for x in re.findall(r"\d+(?:\.\d+)?", text)] + [str(n) for n in ag._korean_numbers(text)]


def part_a():
    print("■ A. 숫자 검사 시험 (AI 없음)")
    bad = 0
    for text, want in CHECK_CASES:
        got = ag._check_voice(text, FACTS) is not None
        bad += got != want
        print(f"  {'✅' if got == want else '❌'} {'통과' if got else '거절'}  {text}")
    print(f"  → {len(CHECK_CASES) - bad}/{len(CHECK_CASES)} 기대와 같음\n")
    return bad == 0


def must_number(stage, facts):
    """첫 문장에 꼭 들어가야 하는 숫자 (프롬프트 규칙): 1단계 = 감은 초, 2단계 이상 = 10분 안 졸음 횟수"""
    if stage >= 2:
        return str(int(facts["sleep_count_10min"]))
    sec = float(facts["last_closed_sec"] or 0)
    return str(round(sec)) if sec else None


def part_b():
    print("■ B. 실제 Gemini 음성 보고")
    ag.USE_REAL_AI = True
    rows = []
    for name, rule, facts, reason in SCENARIOS:
        eye = {"reason": reason, "closed_sec": facts["last_closed_sec"] or None, "perclos": 0.2, "eye_open_prob": 0.05,
               "ear": 0.15, "method": "cnn"}
        analysis = {"summary": f"{'미세수면' if reason == 'microsleep' else '피로 누적'} 의심, 눈 감김 약 {facts['last_closed_sec']}초"}
        try:
            with redirect_stdout(io.StringIO()):
                raw, _used = ag._real_generate(eye, analysis, REGULATIONS, facts, rule, "", None)
            llm = str((raw or {}).get("driver_voice") or "")
        except Exception as e:
            llm = ""
            print(f"  ⚠️ {name}: Gemini 실패 {type(e).__name__} {str(e)[:80]}")
        out = ag._normalize(raw if llm else {}, eye, analysis, REGULATIONS, facts, rule, "")
        final = out["driver_voice"]
        allowed = ag._allowed_numbers(facts)
        llm_wrong = [n for n in numbers_in(llm) if n not in allowed] if llm else []
        final_wrong = [n for n in numbers_in(final) if n not in allowed]
        need = must_number(out["stage"], facts)
        rows.append(dict(name=name, llm=llm, final=final, real=out["voice_is_real"], llm_wrong=llm_wrong,
                         final_wrong=final_wrong, has_need=(need is None or need in numbers_in(final))))
        print(f"  [{name}] 단계 {out['stage']}")
        print(f"     LLM  : {llm or '(없음)'}" + (f"   ← 틀린 숫자 {llm_wrong}" if llm_wrong else ""))
        print(f"     최종 : {final}   ({'LLM 문장' if out['voice_is_real'] else '템플릿'})"
              + ("" if not final_wrong else f"   ❌ 틀린 숫자 {final_wrong}"))
    n = len(rows)
    made = sum(bool(r["llm"]) for r in rows)
    print(f"\n  LLM 이 문장을 만듦 {made}/{n} · LLM 문장 그대로 씀 {sum(r['real'] for r in rows)}/{n}"
          f" · 템플릿으로 바꿈 {n - sum(r['real'] for r in rows)}/{n}")
    print(f"  LLM 이 틀린 숫자를 씀 {sum(bool(r['llm_wrong']) for r in rows)}건 (→ 모두 템플릿으로 바뀌어야 함)")
    print(f"  꼭 넣을 숫자(횟수 · 초)를 넣음 {sum(r['has_need'] for r in rows)}/{n}")
    wrong = sum(bool(r["final_wrong"]) for r in rows)
    print(f"  ★ 기사가 듣는 최종 음성 보고의 숫자 틀림: {wrong}건 " + ("✅ 목표 달성" if wrong == 0 else "❌"))
    return wrong == 0


if __name__ == "__main__":
    ok = part_a()
    if "--real" in sys.argv:
        ok = part_b() and ok
    else:
        print("(실제 Gemini 시험은 --real)")
    sys.exit(0 if ok else 1)
