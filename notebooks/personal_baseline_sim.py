# ═══════════════════════════════════════════════════════════════
# personal_baseline_sim.py — 개인 기준(운행 전 측정 사진) 시뮬레이션 (11/05, B)
#
# [무엇] 548 학습용 val 115명 eval CSV (사진마다 CNN 확률 · EAR) 로, 운행 전 측정 사진을 흉내 내어
#        '개인 기준' 방식들을 지금 서버 방식과 **같은 오경보에서** 비교 (사진 다시 안 돌림, 몇 초)
#   - 운행 전 측정 = 사람마다 정면(F) 뜬 눈 5장 (+ 2점 방식은 감은 눈 2장) 무작위 → 채점에서 뺌
#   - 서버 규칙: 취소 = CNN < t − 0.1 그리고 EAR ≥ EAR 기준 + 0.03 / 오경보 = 뜬 눈인데 취소 못 함
#   - 지표: 오경보 ≤ 1 · 2 · 3 · 5% 에서 반쯤 감은 사진 취소율 (감은 눈 취소 0.5% 이하인 점만), 시드마다 → 평균 ± 표준편차
#   - 반쯤 감은 사진 목표 (11/05 팀장): "폰이 의심해 서버로 온 반쯤 감은 사진은 취소하지 않는 것" — 감은 눈 취소와 따로
#
# [실행] sleep_detector_api\venv\Scripts\python.exe notebooks\personal_baseline_sim.py --seeds 0 1 2 3 4
#        (기본 CSV = D:\aihub548\result_trainval_eye_cnn_548.csv — 지금 서버 모델, 고르기용 115명)
#
# [결과 11/05, 시드 0] 뜬 눈만 개인 기준 · 2점(뜬 눈 + 감은 눈) 모두 같은 오경보에서 0.5 ~ 2%p → 효과 없음
#   (정리: D:\scratch\개인기준_시뮬레이션_1105.md · 노트북 eye_personal.ipynb 로 '사진끼리 비교' 시험)
# ═══════════════════════════════════════════════════════════════

import argparse
import csv

import numpy as np

FA_TARGETS = (0.01, 0.02, 0.03, 0.05)
M = 0.03  # 서버 CONFIRM_OPEN_MARGIN (EAR 여유)


def load(path):
    rows = [r for r in csv.DictReader(open(path, encoding="utf-8-sig")) if r["face"] == "True" and r["prob"] not in ("", "None")]
    col = lambda k, f=str: np.array([f(r[k]) for r in rows])
    return dict(person=col("person"), label=col("label"), view=col("view"), prob=col("prob", float), ear=col("ear", float))


def calibrate(d, seed, k_open=5, k_closed=0):
    """사람마다 정면 뜬 눈 k_open 장 (+ 감은 눈 k_closed 장, 정면 우선) 고르기 → (측정 표시, 측정 가능한 사람)"""
    rng = np.random.default_rng(seed)
    cal, ok = np.zeros(len(d["person"]), bool), []
    for p in np.unique(d["person"]):
        o = np.flatnonzero((d["person"] == p) & (d["label"] == "open") & (d["view"] == "F"))
        c = np.flatnonzero((d["person"] == p) & (d["label"] == "closed"))
        cf = c[d["view"][c] == "F"]
        c = cf if len(cf) >= k_closed else c
        if len(o) < k_open or len(c) < k_closed:
            continue
        cal[rng.choice(o, k_open, replace=False)] = True
        if k_closed:
            cal[rng.choice(c, k_closed, replace=False)] = True
        ok.append(p)
    return cal, ok


def best_half(cancel_fn, L, params):
    """params 를 훑어 (오경보, 감은 눈 취소, 반쯤 취소) → 목표 오경보마다 감은 눈 취소 0.5% 이하 중 반쯤 취소 최저"""
    pts = []
    for x in params:
        c = cancel_fn(x)
        pts.append((1 - c[L == "open"].mean(), c[L == "closed"].mean(), c[L == "half"].mean()))
    out = []
    for fa in FA_TARGETS:
        ok = [q for q in pts if q[0] <= fa and q[1] <= 0.005]
        out.append(min(q[2] for q in ok) if ok else np.nan)
    return out


def run_seed(d, seed):
    res = {}
    # ── 뜬 눈 5장만 (지금 앱 측정) ──
    cal, ok = calibrate(d, seed, 5, 0)
    k = ~cal & np.isin(d["person"], ok)
    P, L, PR, E = d["person"][k], d["label"][k], d["prob"][k], d["ear"][k]
    med = {p: np.median(d["ear"][cal & (d["person"] == p)]) for p in ok}
    cmax = {p: d["prob"][cal & (d["person"] == p)].max() for p in ok}
    pm, pc = np.array([med[p] for p in P]), np.array([cmax[p] for p in P])
    ts = np.arange(0.11, 0.951, 0.005)
    srv_ear = np.clip(pm * 0.7, 0.15, 0.25) + M
    res["지금 방식: 고정 EAR 0.23 · t 바꿈"] = best_half(lambda t: (PR < t - 0.1) & (E >= 0.23 + M), L, ts)
    res["서버 개인 EAR (×0.7, 0.15~0.25) · t 바꿈"] = best_half(lambda t: (PR < t - 0.1) & (E >= srv_ear), L, ts)
    cps = np.arange(0, 0.31, 0.0025)
    res["CNN 개인 (뜬 눈 5장 최대 + 여유, t 0.4)"] = best_half(lambda cp: (PR < np.minimum(0.3, pc + cp)) & (E >= 0.23 + M), L, cps)
    # ── 2점: 뜬 눈 5장 + 감은 눈 2장 ──
    cal, ok = calibrate(d, seed, 5, 2)
    k = ~cal & np.isin(d["person"], ok)
    P, L, PR, E = d["person"][k], d["label"][k], d["prob"][k], d["ear"][k]
    stat = lambda arr, lab: {p: np.median(arr[cal & (d["person"] == p) & (d["label"] == lab)]) for p in ok}
    Eo, Ec, Po, Pc = stat(d["ear"], "open"), stat(d["ear"], "closed"), stat(d["prob"], "open"), stat(d["prob"], "closed")
    eo, ec = np.array([Eo[p] for p in P]), np.array([Ec[p] for p in P])
    po, pcl = np.array([Po[p] for p in P]), np.array([Pc[p] for p in P])
    rel_e = (eo - E) / np.maximum(eo - ec, 0.02)   # 0 = 내 뜬 눈, 1 = 내 감은 눈
    rel_p = (PR - po) / np.maximum(pcl - po, 0.05)
    rs = np.linspace(0, 1, 401)
    res["(같은 사람들) 지금 방식 · t 바꿈"] = best_half(lambda x: (PR < (0.11 + 0.84 * x) - 0.1) & (E >= 0.23 + M), L, rs)
    res["2점 CNN (rel_p < r)"] = best_half(lambda x: rel_p < x, L, rs)
    res["2점 EAR + CNN (둘 다 < r)"] = best_half(lambda x: (rel_e < x) & (rel_p < x), L, rs)
    return res, len(ok)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", default=r"D:\aihub548\result_trainval_eye_cnn_548.csv")
    ap.add_argument("--seeds", type=int, nargs="+", default=[0, 1, 2, 3, 4], help="운행 전 측정 사진 추첨 시드")
    a = ap.parse_args()
    d = load(a.csv)
    all_res = []
    for s in a.seeds:
        r, n2 = run_seed(d, s)
        all_res.append(r)
    print(f"CSV {a.csv} · 사람 {len(np.unique(d['person']))}명 (2점은 감은 눈 2장 이상인 {n2}명) · 시드 {a.seeds}")
    print("같은 오경보에서 반쯤 감은 사진 취소율 (감은 눈 취소 0.5% 이하인 점만), 시드 평균 ± 표준편차 — 낮을수록 목표에 가까움")
    print(f"{'방식':<42}" + "".join(f"{'FA≤' + format(fa, '.0%'):>16}" for fa in FA_TARGETS))
    for name in all_res[0]:
        v = np.array([r[name] for r in all_res])
        cells = [("-" if np.isnan(v[:, i]).any() else f"{np.nanmean(v[:, i]):.1%} ± {np.nanstd(v[:, i]):.1%}") for i in range(len(FA_TARGETS))]
        print(f"{name:<42}" + "".join(f"{c:>16}" for c in cells))


if __name__ == "__main__":
    main()
