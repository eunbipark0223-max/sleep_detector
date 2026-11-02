# ═══════════════════════════════════════════════════════════════
# tools/stt_score.py — STT 시험 채점 (KPI ⑤ 음성 퀴즈 인식률 · 퀴즈 부품 A / B 결정)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1   |   서버 코드가 아니라 PC 에서 돌리는 시험 도구
#
# [하는 일]
#   - 앱 시험 도구(lib/tools/stt_test_main.dart)가 모은 stt_test.csv 를 서버와 같은 코드로 채점
#       따라 말하기: voice_quiz_service.repeat_score ≥ REPEAT_MIN_SCORE (0.8)
#       덧셈      : voice_quiz_service.parse_answer_number == 정답
#   - 유형 × 환경 · 사람별 통과율, 무응답 · 오류 수, 걸린 시간, 따라 말하기 유사도 기준별 통과율
#   - 판정: 깨어 있는 사람 통과율 90% 이상이면 음성 퀴즈(부품 A) 유지 (기획안 KPI ⑤)
#
# [실행] (sleep_detector_api 폴더)
#   adb pull /sdcard/Android/data/com.example.sleep_detector_app/files/stt_test.csv
#   venv\Scripts\python tools/stt_score.py stt_test.csv
#   → 끝 줄 판정 · 틀린 문제 목록 (들은 글자 그대로 — 채점 규칙을 고칠지 볼 때)
#
# [주의]
#   - 인식 글자만 있고 녹음은 없음. 결과 CSV 는 GitHub 에 올리지 않는다 (드라이브에만)
#   - 사람이 깨어 있을 때 재는 것 (졸린 사람이 실패하는 건 정상 — 그래서 단계가 오름)
# ═══════════════════════════════════════════════════════════════
import csv
import os
import statistics
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)

from services.voice_quiz_service import REPEAT_MIN_SCORE, parse_answer_number, repeat_score  # noqa: E402

GOAL = 0.90                       # KPI ⑤ 목표
SCORE_GRID = (0.6, 0.7, 0.8, 0.9)  # 따라 말하기 유사도 기준 후보


def judge(row):
    heard = row.get("heard", "")
    if row["type"] == "repeat":
        score = repeat_score(row["expected"], heard)
        return score >= REPEAT_MIN_SCORE, score
    got = parse_answer_number(heard)
    return got is not None and str(got) == str(row["expected"]).strip(), None


def pct(ok, n):
    return f"{ok}/{n} ({ok / n:.0%})" if n else "-"


def main(paths):
    rows = []
    for p in paths:
        with open(p, encoding="utf-8-sig", newline="") as f:
            rows += [r for r in csv.DictReader(f) if r.get("type") in ("repeat", "add")]
    if not rows:
        sys.exit("채점할 줄이 없어요 (stt_test.csv 의 type 칸이 repeat / add 인 줄)")
    for r in rows:
        r["passed"], r["score"] = judge(r)

    print(f"STT 시험 {len(rows)}문제 · 사람 {sorted({r['person'] for r in rows})} · 환경 {sorted({r['cond'] for r in rows})}\n")

    print("■ 유형 × 환경 통과율")
    for cond in sorted({r["cond"] for r in rows}):
        for t, name in (("repeat", "따라 말하기"), ("add", "덧셈")):
            g = [r for r in rows if r["cond"] == cond and r["type"] == t]
            if g:
                ns = sum(r["status"] == "no_speech" for r in g)
                er = sum(r["status"].startswith("error") for r in g)
                print(f"  {cond:6s} {name:6s} {pct(sum(r['passed'] for r in g), len(g)):14s} 무응답 {ns} · 오류 {er}")

    print("\n■ 사람별 통과율")
    for p in sorted({r["person"] for r in rows}):
        g = [r for r in rows if r["person"] == p]
        print(f"  {p}  {pct(sum(r['passed'] for r in g), len(g))}")

    rep = [r for r in rows if r["type"] == "repeat"]
    if rep:
        print("\n■ 따라 말하기 유사도 기준별 통과율 (지금 기준", REPEAT_MIN_SCORE, ")")
        for s in SCORE_GRID:
            print(f"  ≥ {s}: {pct(sum(r['score'] >= s for r in rep), len(rep))}")

    times = [int(r["ms_total"]) for r in rows if r.get("ms_total", "").lstrip("-").isdigit()]
    firsts = [int(r["ms_first"]) for r in rows if r.get("ms_first", "").isdigit() and int(r["ms_first"]) >= 0]
    if times:
        print(f"\n■ 걸린 시간: 듣기 끝까지 중간값 {statistics.median(times) / 1000:.1f}초 · 최대 {max(times) / 1000:.1f}초"
              + (f" / 첫 글자까지 중간값 {statistics.median(firsts) / 1000:.1f}초" if firsts else ""))

    wrong = [r for r in rows if not r["passed"]]
    if wrong:
        print("\n■ 틀린 문제 (들은 글자 그대로)")
        for r in wrong:
            extra = f" 유사도 {r['score']:.2f}" if r["score"] is not None else ""
            print(f"  [{r['person']} {r['cond']} {r['type']}] {r['display']} → '{r['heard']}' ({r['status']}){extra}")

    ok = sum(r["passed"] for r in rows)
    rate = ok / len(rows)
    print(f"\n결과: 전체 {pct(ok, len(rows))} → "
          + ("✅ 90% 이상 — 음성 퀴즈(부품 A) 유지" if rate >= GOAL
             else "⚠️ 90% 미만 — 틀린 문제를 보고 채점 규칙 · 듣기 시간 조정, 그래도 안 되면 화면 퀴즈(부품 B, config.QUIZ_MODE = 'screen')"))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("사용법: venv\\Scripts\\python tools/stt_score.py stt_test.csv [더 있는 CSV ...]")
    main(sys.argv[1:])
