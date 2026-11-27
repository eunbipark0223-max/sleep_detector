# ═══════════════════════════════════════════════════════════════
# tools/stt_wandb.py — STT 시험 결과(CSV) → 시험별 요약 → W&B (stt-kpi5)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1 (실험 기록, KPI ⑤ 음성 퀴즈 인식률)   |   서버 코드가 아니라 PC 에서 돌리는 도구
#
# [하는 일]
#   - 앱 시험 도구(lib/tools/stt_test_main.dart)가 모은 CSV 를 tools/stt_score.py 와 같은 코드로 채점
#   - 시험(--run) 하나 = W&B run 하나: 통과율(전체 · 따라 말하기 · 덧셈) · 무응답 · 걸린 시간 ·
#     유사도 기준별 통과율(0.6 ~ 0.9) · 파일(회차)별 통과율 · 틀린 문제 표(들은 글자)
#   - 시험이 2개 이상이면 '00_비교' run 을 하나 더 만들어 막대그래프로 나란히 (이름은 --compare-name)
#
# [실행] (sleep_detector_api 폴더)
#   1. (처음 1번) venv\Scripts\pip install wandb   ← 시험 도구 전용, requirements.txt 에는 넣지 않음
#                 venv\Scripts\wandb login          ← 키는 직접 입력 (파일 · 코드에 적지 않음)
#   2. 표만 확인:  venv\Scripts\python -X utf8 tools/stt_wandb.py --dry  --run <이름> <CSV ...>  [--run ...]
#   3. 올리기:     venv\Scripts\python -X utf8 tools/stt_wandb.py        --run <이름> <CSV ...>  [--run ...]
#   예) --run 1119_20q_quiet "D:/STT시험_1119/STT시험_1119/1회_quiet.csv" ... "5회_quiet.csv"
#       --run 1119_100s_noise "D:/STT시험_1119/STT시험_1119/최종_noise_100문장.csv"
#
# [주의]
#   - 올리는 것은 숫자 · 글자(문제 · 들은 글자)뿐 — 녹음은 원래 없음. CSV 파일 자체 · 경로는 올리지 않음 (파일 이름만)
#   - 채점은 '지금' 채점 코드(REPEAT_MIN_SCORE 등)로 다시 함 → 예전 시험(11/02 이전)을 넣으면 그날 발표한 숫자와
#     다를 수 있음. W&B config 의 '채점' 칸에 지금 기준을 같이 적어 둠
#   - 결과 CSV 는 GitHub 에 올리지 않는다 (드라이브에만)
# ═══════════════════════════════════════════════════════════════
import argparse
import csv
import os
import statistics
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, TOOLS)

from stt_score import GOAL, REPEAT_MIN_SCORE, SCORE_GRID, judge  # noqa: E402  (서버 폴더를 sys.path 에 넣음)
import config  # noqa: E402

PROJECT = "stt-kpi5"
TYPE_KO = {"repeat": "따라 말하기", "add": "덧셈"}


def load(paths):
    rows = []
    for p in paths:
        with open(p, encoding="utf-8-sig", newline="") as f:
            for r in csv.DictReader(f):
                if r.get("type") in ("repeat", "add"):
                    r["file"] = os.path.basename(p)
                    rows.append(r)
    for r in rows:
        r["passed"], r["score"] = judge(r)
    return rows


def rate(g):
    return round(sum(r["passed"] for r in g) / len(g), 4) if g else None


def ms(rows, key):
    v = [int(r[key]) for r in rows if str(r.get(key, "")).lstrip("-").isdigit() and int(r[key]) >= 0]
    return round(statistics.median(v) / 1000, 2) if v else None


def summarize(name, rows):
    rep = [r for r in rows if r["type"] == "repeat"]
    add = [r for r in rows if r["type"] == "add"]
    s = {
        "문제 수": len(rows),
        "통과율/전체": rate(rows),
        "통과율/따라 말하기": rate(rep),
        "통과율/덧셈": rate(add),
        "무응답/전체": sum(r["status"] == "no_speech" for r in rows),
        "무응답/따라 말하기": sum(r["status"] == "no_speech" for r in rep),
        "무응답/덧셈": sum(r["status"] == "no_speech" for r in add),
        "오류": sum(r["status"].startswith("error") for r in rows),
        "시간/첫 글자까지 중간값(초)": ms(rows, "ms_first"),
        "시간/듣기 끝까지 중간값(초)": ms(rows, "ms_total"),
        "목표 90% 통과": bool(rows) and rate(rows) >= GOAL,
    }
    for t in SCORE_GRID:
        s[f"기준별/따라 말하기 ≥{t}"] = round(sum(r["score"] >= t for r in rep) / len(rep), 4) if rep else None
    by_file = []
    for f in dict.fromkeys(r["file"] for r in rows):
        g = [r for r in rows if r["file"] == f]
        by_file.append([f, sorted({r["cond"] for r in g}).__str__(), len(g), rate(g),
                        rate([r for r in g if r["type"] == "repeat"]), rate([r for r in g if r["type"] == "add"]),
                        sum(r["status"] == "no_speech" for r in g)])
    wrong = [[r["file"], r["cond"], TYPE_KO[r["type"]], r["display"], r["heard"], r["status"],
              None if r["score"] is None else round(r["score"], 2)] for r in rows if not r["passed"]]
    meta = {"시험": name, "사람": sorted({r["person"] for r in rows}), "환경": sorted({r["cond"] for r in rows}),
            "파일": [b[0] for b in by_file],
            "채점": f"지금 코드 — 따라 말하기 유사도 ≥ {REPEAT_MIN_SCORE} · 덧셈 숫자 일치",
            "LISTEN_SEC": config.LISTEN_SEC, "VOICE_QUIZ_TYPES": list(getattr(config, "VOICE_QUIZ_TYPES", ()))}
    return s, by_file, wrong, meta


FILE_COLS = ["파일", "환경", "문제 수", "전체", "따라 말하기", "덧셈", "무응답"]
WRONG_COLS = ["파일", "환경", "유형", "문제", "들은 글자", "상태", "유사도"]


def fmt(v):
    return "-" if v is None else (f"{v:.0%}" if isinstance(v, float) and v <= 1 else str(v))


def show(name, s, by_file, wrong, meta):
    print(f"\n━━ {name} ━━  환경 {meta['환경']} · 사람 {meta['사람']} · {meta['채점']}")
    for k, v in s.items():
        print(f"  {k:28s} {fmt(v)}")
    print("  · 파일(회차)별")
    for b in by_file:
        print("    " + " · ".join(f"{c} {fmt(v)}" for c, v in zip(FILE_COLS, b)))
    print(f"  · 틀린 문제 {len(wrong)}개")
    for w in wrong:
        print(f"    [{w[1]} {w[2]}] {w[3]} → '{w[4]}' ({w[5]}){'' if w[6] is None else f' 유사도 {w[6]}'}")


def upload(results, compare_name="00_비교"):
    import wandb  # 시험 도구 전용 — 없으면 '처음 1번' 안내대로 설치

    for name, (s, by_file, wrong, meta) in results.items():
        run = wandb.init(project=PROJECT, name=name, group="stt", job_type="kpi5", config=meta,
                         reinit="finish_previous", settings=wandb.Settings(console="off"))
        grid = wandb.Table(columns=["기준", "통과율"],
                           data=[[t, s[f"기준별/따라 말하기 ≥{t}"]] for t in SCORE_GRID if s[f"기준별/따라 말하기 ≥{t}"] is not None])
        log = {"파일(회차)별": wandb.Table(columns=FILE_COLS, data=by_file),
               "틀린 문제": wandb.Table(columns=WRONG_COLS, data=wrong)}
        if grid.data:
            log["따라 말하기 기준별 통과율"] = wandb.plot.line(grid, "기준", "통과율", title=f"{name} — 유사도 기준별 통과율")
        run.log(log)
        run.summary.update({k: v for k, v in s.items() if v is not None})
        run.finish()

    if len(results) > 1:
        run = wandb.init(project=PROJECT, name=compare_name, group="stt", job_type="compare",
                         reinit="finish_previous", settings=wandb.Settings(console="off"))
        cols = ["시험", "통과율/전체", "통과율/따라 말하기", "통과율/덧셈", f"기준별/따라 말하기 ≥{REPEAT_MIN_SCORE}"]
        t = wandb.Table(columns=cols, data=[[n] + [r[0].get(c) for c in cols[1:]] for n, r in results.items()])
        log = {"시험 비교": t}
        for c in cols[1:4]:
            sub = wandb.Table(columns=["시험", c], data=[[n, r[0][c]] for n, r in results.items() if r[0][c] is not None])
            if sub.data:
                log[f"비교 — {c}"] = wandb.plot.bar(sub, "시험", c, title=c)
        run.log(log)
        run.finish()
    print(f"\n✅ W&B 프로젝트 '{PROJECT}' 에 {len(results)}개 시험" + (f" + {compare_name}" if len(results) > 1 else "") + " 올림")


def main():
    ap = argparse.ArgumentParser(description="STT 시험 CSV → W&B (stt-kpi5)")
    ap.add_argument("--run", nargs="+", action="append", required=True, metavar=("이름", "CSV"),
                    help="시험 이름 다음에 그 시험의 CSV 파일들 (여러 번 쓸 수 있음)")
    ap.add_argument("--dry", action="store_true", help="W&B 에 올리지 않고 표만 보기")
    ap.add_argument("--compare-name", default="00_비교", help="비교 run 이름 (여러 번 올릴 때 겹치지 않게, 예: 00_비교_1029)")
    a = ap.parse_args()

    results = {}
    for spec in a.run:
        if len(spec) < 2:
            sys.exit(f"--run {spec[0]} 다음에 CSV 파일을 하나 이상 적어 주세요")
        name, paths = spec[0], spec[1:]
        missing = [p for p in paths if not os.path.exists(p)]
        if missing:
            sys.exit(f"파일이 없어요: {missing}")
        rows = load(paths)
        if not rows:
            sys.exit(f"{name}: 채점할 줄이 없어요 (type 칸이 repeat / add 인 줄)")
        results[name] = summarize(name, rows)
        show(name, *results[name])

    if a.dry:
        print("\n(--dry) W&B 에 올리지 않음")
    else:
        upload(results, a.compare_name)


if __name__ == "__main__":
    main()
