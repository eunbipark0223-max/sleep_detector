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


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("사용법: python tools/eye_replay.py <logcat 기록 파일>")
    main(sys.argv[1])
