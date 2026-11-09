# ═══════════════════════════════════════════════════════════════
# tools/eye_replay.py — 시연 폰 거치 시험 기록으로 기준값 후보별 경고 횟수 계산
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P1 (기준값 확정 1.5초 · 15%)   |   서버 코드가 아니라 PC 에서 돌리는 도구
#
# [하는 일]
#   - 앱 tools/eye_live_main.dart 의 프레임 기록 [eye_frame] 을 읽어 eye_monitor 판정을 그대로 다시 계산
#   - 연속 감김 시간 · PERCLOS 기준을 바꿔 가며 경고 횟수를 표로 → 다시 찍지 않고 후보를 비교
#   - 지금 기준 계산 결과를 앱이 실제로 낸 경고와 맞춰 봄 (다르면 계산이 틀린 것 → 표를 믿지 말 것)
#   - 경고마다 가까운 동작 표시 [eye_mark] 를 붙임
#
# [실행] (sleep_detector_api 폴더, 파이썬만 있으면 됨)
#   시험 중:  adb logcat -s flutter -v raw > D:\kpi_raw\phone_log\mount1.txt
#   시험 뒤:  python tools/eye_replay.py D:\kpi_raw\phone_log\mount1.txt
#   🆕 상태별 표 (11/09 팀장 측정 요청):  python tools/eye_replay.py states <기록 파일> [<기록 파일> ...] [--csv 프레임.csv]
#       사람 · 상태 (① 뜸 ② 실눈 ③ 감음 ④ 시선만 아래 ⑤ 숙이고 뜸) 마다 눈 뜸 확률 중간값 · 0.4 / 0.5 미만 비율 ·
#       숙인 정도 · 경고 원인별 개수 + '0 쉼' 구간 (운전 자세) 경고 · fps · 의심 사진 JPG 변환 시간
#       --csv: 프레임마다 한 줄 (시간 · 사람 · 상태 · 확률 · 고개 각도 · 0.4 미만) — 드라이브에만
#
# [주의]
#   - 판정은 lib/services/eye_monitor.dart 와 같아야 함 — 그쪽 규칙을 바꾸면 여기도 바꾼다
#   - 고개 숙임 여부는 앱이 계산한 값을 그대로 씀 (평소 각도는 다시 계산하지 않음)
#   - 기록에는 숫자 · 글자만 있음 (얼굴 사진 없음). GitHub 에 올리지 않고 드라이브에만
# ═══════════════════════════════════════════════════════════════
import re
import sys

EYE_CLOSED_PROB = 0.4      # config.dart
SMILE_OPEN_PROB = 0.8      # config.dart — 웃음 확률이 이 이상이면 감김으로 세지 않음
SMILE_GRID = [0.7, 0.8, 0.9]
PERCLOS_WINDOW_SEC = 30
HEAD_DOWN_SEC = 3.0
HEAD_UP_RESET_SEC = 0.5
CLOSED_SEC_GRID = [1.0, 1.5, 2.0, 2.5]
PERCLOS_GRID = [0.10, 0.15, 0.20, 0.25]
NOW_CLOSED_SEC, NOW_PERCLOS = 1.5, 0.15
MARK_NEAR_SEC = 5.0        # 경고 전후 이 시간 안의 동작 표시를 붙임


def read_log(path):
    """→ frames [(초, 확률 또는 None, 숙임 bool, 웃음 확률 또는 None)], marks [(초, 글)], 앱이 낸 경고 [(초, reason)]"""
    frames, marks, alarms = [], [], []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = re.search(r"\[eye_frame\] (\d+),([\d.]*),([01])(?:,([\d.]+))?", line)
            if m:
                frames.append((int(m[1]) / 1000, float(m[2]) if m[2] else None, m[3] == "1",
                               float(m[4]) if m[4] else None))
                continue
            m = re.search(r"\[eye_mark\] (\d+),(.+)", line)
            if m:
                marks.append((int(m[1]) / 1000, m[2].strip()))
                continue
            m = re.search(r"\[eye_live\] ([\d.]+)s \S+ (microsleep|perclos) ", line)
            if m:
                alarms.append((float(m[1]), m[2]))
    return frames, marks, alarms


def replay(frames, closed_sec=NOW_CLOSED_SEC, perclos_thr=NOW_PERCLOS, closed_prob=EYE_CLOSED_PROB, cooldown=True,
           smile_open=SMILE_OPEN_PROB):
    """eye_monitor.processFrame · _judge · _checkHeadDown 과 같은 순서로 판정 → 경고 [(초, 이유)]"""
    out, history = [], []
    closed_start = window_start = last_suspect = head_start = head_up_since = None
    micro_trig = perclos_trig = head_trig = False

    def head_up(t):
        nonlocal head_start, head_up_since, head_trig
        if head_start is None:
            return
        if head_up_since is None:
            head_up_since = t
        if t - head_up_since >= HEAD_UP_RESET_SEC:
            head_start, head_up_since, head_trig = None, None, False

    def check_head(t):
        nonlocal head_start, head_up_since, head_trig, micro_trig, perclos_trig, last_suspect
        head_up_since = None
        if head_start is None:
            head_start = t
        if t - head_start < HEAD_DOWN_SEC or head_trig or micro_trig:
            return
        head_trig = micro_trig = perclos_trig = True
        last_suspect = t
        out.append((t, "head"))

    for t, prob, down, *rest in frames:
        smile = rest[0] if rest else None   # 웃음 기록이 없는 옛 기록은 규칙 없이 계산
        if prob is None:                # 얼굴 없음 · 눈 확률 없음
            if down:
                check_head(t)
            else:
                head_up(t)
            continue
        closed = prob < closed_prob and not (smile is not None and smile >= smile_open)
        history = [r for r in history if r[0] >= t - PERCLOS_WINDOW_SEC]
        if not history:
            window_start = t
        history.append((t, closed))
        perclos = sum(c for _, c in history) / len(history)

        if closed:
            if closed_start is None:
                closed_start = t
            if t - closed_start >= closed_sec and not micro_trig:
                micro_trig = perclos_trig = True
                if down:
                    head_trig = True
                last_suspect = t
                out.append((t, "microsleep"))
        else:
            closed_start, micro_trig = None, False

        full = t - window_start >= PERCLOS_WINDOW_SEC
        cooling = cooldown and last_suspect is not None and int(t - last_suspect) < PERCLOS_WINDOW_SEC
        if full and perclos >= perclos_thr:
            if not perclos_trig and not micro_trig and not cooling:
                perclos_trig = True
                last_suspect = t
                out.append((t, "perclos"))
        elif perclos < perclos_thr:
            perclos_trig = False

        if down:
            check_head(t)
        else:
            head_up(t)
    return out


def near_mark(t, marks):
    near = [(abs(mt - t), label) for mt, label in marks if abs(mt - t) <= MARK_NEAR_SEC]
    return min(near)[1] if near else "-"


def main(path):
    frames, marks, alarms = read_log(path)
    if not frames:
        sys.exit("[eye_frame] 기록이 없습니다 — tools/eye_live_main.dart 최신판으로 시험했는지 확인")
    minutes = (frames[-1][0] - frames[0][0]) / 60
    unknown = sum(f[1] is None for f in frames)
    print(f"기록 {minutes:.1f}분 · 프레임 {len(frames)}장 ({len(frames) / (minutes * 60):.1f}fps) · "
          f"얼굴 · 눈 없음 {unknown}장 · 동작 표시 {len(marks)}개")

    now = replay(frames)
    calc_kinds = ["microsleep" if r == "head" else r for _, r in now]    # 앱은 고개 숙임도 microsleep 으로 보냄
    app_kinds = [r for _, r in alarms]
    if alarms:
        result = "일치" if app_kinds == calc_kinds else "⚠️ 불일치 (아래 표를 믿지 말고 원인부터 확인)"
        print(f"\n■ 검증: 지금 기준 계산 {len(now)}번 / 앱이 실제로 낸 경고 {len(alarms)}번 → {result}")
    else:
        print(f"\n■ 검증: 앱 경고 기록 없음 (계산 {len(now)}번) — 맞춰 볼 수 없음")

    print("\n■ 지금 기준 경고 목록 (1.5초 · 15%)")
    for t, r in now:
        print(f"  {t:7.1f}초  {r:10s}  가까운 동작: {near_mark(t, marks)}")

    print("\n■ 기준별 경고 횟수 (행: 연속 감김 초, 칸: PERCLOS 기준) — 괄호는 10분당")
    print("        " + "".join(f"{p:>12.0%}" for p in PERCLOS_GRID))
    for c in CLOSED_SEC_GRID:
        cells = []
        for p in PERCLOS_GRID:
            n = len(replay(frames, c, p))
            cells.append(f"{n:>5d} ({n / minutes * 10:4.0f})")
        print(f"{c:>6.1f}초 " + "".join(f"{x:>12s}" for x in cells))
    if any(f[3] is not None for f in frames):
        print("\n■ 웃음 기준별 경고 횟수 (감김 프레임 중 웃음으로 뺀 장수)")
        for s in SMILE_GRID + [9.0]:
            cut = sum(f[1] is not None and f[1] < EYE_CLOSED_PROB and f[3] is not None and f[3] >= s for f in frames)
            name = "규칙 없음" if s > 1 else f"{s:.1f}"
            print(f"  {name}: 경고 {len(replay(frames, smile_open=s))}번 · 뺀 프레임 {cut}장")
    nc = replay(frames, cooldown=False)
    print(f"\n참고: 30초 재경고 막기를 뺐다면 {len(nc)}번 (PERCLOS {sum(r == 'perclos' for _, r in nc)}번)")


STATE_NAMES = {0: "0 쉼", 1: "① 정면 뜸", 2: "② 실눈", 3: "③ 감음", 4: "④ 시선만 아래", 5: "⑤ 숙이고 뜸"}
CAUSE_NAMES = {"eye": "눈 감김", "head": "고개 숙임", "head_resend": "숙임 재전송", "perclos": "PERCLOS"}


def read_states(path):
    """11/09 시험 앱 기록 → 프레임 [dict], 경고 [dict]. 사람 · 상태가 없는 옛 기록은 빈 목록"""
    frames, alarms = [], []
    num = r"(-?[\d.]*)"
    fr = re.compile(r"\[eye_frame\] (\d+),([\d.]*),([01]),([\d.]*)," + num + "," + num + r",(\w+),(\d)")
    al = re.compile(r"\[eye_alarm\] (\d+),(\w+),(\w+),(\d+),(\d+),(\w+),(\d)")
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = fr.search(line)
            if m:
                g = m.groups()
                frames.append({"t": int(g[0]) / 1000, "prob": float(g[1]) if g[1] else None, "down": g[2] == "1",
                               "smile": float(g[3]) if g[3] else None, "x": float(g[4]) if g[4] else None,
                               "base": float(g[5]) if g[5] else None, "person": g[6], "state": int(g[7])})
                continue
            m = al.search(line)
            if m:
                alarms.append({"t": int(m[1]) / 1000, "reason": m[2], "cause": m[3], "photos": int(m[4]),
                               "jpg_ms": int(m[5]), "person": m[6], "state": int(m[7])})
    return frames, alarms


def _median(xs):
    xs = sorted(xs)
    if not xs:
        return None
    n = len(xs)
    return xs[n // 2] if n % 2 else (xs[n // 2 - 1] + xs[n // 2]) / 2


def _pct(a, b):
    return f"{a / b * 100:5.1f}%" if b else "    -"


def _fmt(v, nd=2):
    return "-" if v is None else f"{v:.{nd}f}"


def _causes(al):
    return " · ".join(f"{CAUSE_NAMES.get(c, c)} {sum(a['cause'] == c for a in al)}"
                      for c in CAUSE_NAMES if any(a["cause"] == c for a in al)) or "없음"


def states_main(paths, csv_path=None):
    frames, alarms = [], []
    for p in paths:
        fr, al = read_states(p)
        if not fr:
            print(f"⚠️ {p}: 사람 · 상태가 있는 [eye_frame] 이 없음 (11/09 이후 시험 앱으로 찍은 기록인지 확인)")
        frames += [dict(f, file=p) for f in fr]
        alarms += [dict(a, file=p) for a in al]
    if not frames:
        sys.exit(1)

    # fps — 파일마다 (기록 앞뒤 시간 / 프레임 수, 얼굴 없음 프레임 포함)
    print("■ 분석한 프레임 수 (fps)")
    for p in paths:
        ts = [f["t"] for f in frames if f["file"] == p]
        if len(ts) > 1 and ts[-1] > ts[0]:
            print(f"  {p}: {len(ts)}장 / {ts[-1] - ts[0]:.0f}초 = {len(ts) / (ts[-1] - ts[0]):.1f}fps")

    people = sorted({f["person"] for f in frames})
    print("\n■ 상태별 ML Kit 값 (확률 · 비율은 얼굴 · 눈 확률이 있는 프레임만, '앱 감김' = 웃음 규칙까지 넣은 앱 판정)")
    print(f"  {'사람':4s} {'상태':12s} {'프레임':>6s} {'모름':>6s} {'확률 중간':>8s} {'0.4 미만':>8s} {'0.5 미만':>8s} "
          f"{'앱 감김':>7s} {'숙인 정도 중간':>12s} {'숙임 판정':>8s}  경고")
    for person in people:
        for st in range(1, 6):
            fs = [f for f in frames if f["person"] == person and f["state"] == st]
            if not fs:
                continue
            known = [f for f in fs if f["prob"] is not None]
            probs = [f["prob"] for f in known]
            app_closed = sum(f["prob"] < EYE_CLOSED_PROB and not (f["smile"] is not None and f["smile"] >= SMILE_OPEN_PROB)
                             for f in known)
            drops = [f["base"] - f["x"] for f in known if f["x"] is not None and f["base"] is not None]
            al = [a for a in alarms if a["person"] == person and a["state"] == st]
            print(f"  {person:4s} {STATE_NAMES[st]:12s} {len(fs):6d} {_pct(len(fs) - len(known), len(fs)):>6s} "
                  f"{_fmt(_median(probs), 3):>8s} {_pct(sum(p < 0.4 for p in probs), len(probs)):>8s} "
                  f"{_pct(sum(p < 0.5 for p in probs), len(probs)):>8s} {_pct(app_closed, len(known)):>7s} "
                  f"{_fmt(_median(drops), 1):>11s}° {_pct(sum(f['down'] for f in fs), len(fs)):>8s}  {_causes(al)}")
    print("  (숙인 정도 = 평소 각도 − 지금 각도, 6° 이상이면 숙임. 평소 각도를 아직 못 낸 프레임은 빠짐)")

    rest = [f for f in frames if f["state"] == 0]
    if rest:
        print("\n■ '0 쉼' 구간 (운전 자세 · 자세 바꾸는 중 포함) 경고")
        for person in people:
            ts = [f["t"] for f in rest if f["person"] == person]
            if not ts:
                continue
            # 상태 0 인 연속 프레임 사이 시간만 더함 (2초 넘게 비면 다른 구간)
            sec, prev = 0.0, None
            for t in ts:
                if prev is not None and t - prev < 2:
                    sec += t - prev
                prev = t
            al = [a for a in alarms if a["person"] == person and a["state"] == 0]
            print(f"  {person}: {sec / 60:.1f}분 · 경고 {len(al)}번 ({_causes(al)})")
        print("  (서버 확정 · 취소는 시험 앱으로 안 나옴 → 본 앱 + 서버 [detect] 줄로 따로 셈)")

    if alarms:
        print("\n■ 의심 사진 (원인별 장수 · JPG 변환 시간 — 화면 쪽에서 돌아서 경고가 그만큼 늦어짐)")
        for c in CAUSE_NAMES:
            al = [a for a in alarms if a["cause"] == c]
            if al:
                print(f"  {CAUSE_NAMES[c]}: {len(al)}번 · 사진 {sorted({a['photos'] for a in al})}장 · "
                      f"변환 중간 {_fmt(_median([a['jpg_ms'] for a in al if a['photos'] > 0]), 0)}ms")
        ms = [a["jpg_ms"] for a in alarms if a["photos"] > 0]
        if ms:
            print(f"  전체 변환 최대 {max(ms)}ms")

    if csv_path:
        import csv
        with open(csv_path, "w", newline="", encoding="utf-8-sig") as f:
            w = csv.writer(f)
            w.writerow(["file", "time_s", "person", "state", "eye_open_prob", "under_0.4", "under_0.5", "smile",
                        "head_x", "head_base", "head_drop", "head_down"])
            for r in frames:
                drop = r["base"] - r["x"] if r["x"] is not None and r["base"] is not None else None
                w.writerow([r["file"], f"{r['t']:.3f}", r["person"], r["state"], _fmt(r["prob"], 3),
                            "" if r["prob"] is None else int(r["prob"] < 0.4),
                            "" if r["prob"] is None else int(r["prob"] < 0.5), _fmt(r["smile"], 3),
                            _fmt(r["x"], 1), _fmt(r["base"], 1), _fmt(drop, 1), int(r["down"])])
        print(f"\n프레임 CSV: {csv_path} (얼굴 사진 없음, 숫자만 — 드라이브에만 올림)")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args and args[0] == "states":
        args = args[1:]
        csv_out = None
        if "--csv" in args:
            i = args.index("--csv")
            csv_out = args[i + 1]
            args = args[:i] + args[i + 2:]
        if not args:
            sys.exit("사용법: python tools/eye_replay.py states <기록 파일> [...] [--csv 프레임.csv]")
        states_main(args, csv_out)
    elif len(args) == 1:
        main(args[0])
    else:
        sys.exit("사용법: python tools/eye_replay.py <기록 파일>  /  python tools/eye_replay.py states <기록 파일> ...")
