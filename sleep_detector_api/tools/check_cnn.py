# ═══════════════════════════════════════════════════════════════
# tools/check_cnn.py — CNN 이 서버 판정에 제대로 연결됐는지 · 폴백이 맞게 도는지 시험
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1   |   서버 코드가 아니라 PC 에서 돌리는 시험 도구
#
# [왜] KPI ③(tools/kpi3_scenarios.py)은 눈 판정을 가짜로 돌려서 CNN 이 고장 나도 12/12 가 나온다.
#      모델을 바꿀 때마다 이 도구로 "진짜 모델이 진짜 판정에 쓰이는지" 를 확인한다
#
# [하는 일]
#   A. 설정 : USE_REAL_AI · USE_CNN · 모델 파일 · (--t) config 기준값이 고른 값과 같은지
#   B. 모델 : 실제로 읽히는지, 빈 입력에 0~1 확률이 나오는지, CPU 시간
#   C. 사진 : --closed / --open 사진을 서버 판정(check_eyes) 그대로 → method = cnn 인지, 감음 · 뜸이 맞는지
#   D. 폴백 : 모델 없음 · 깨짐 · 추론 오류 · 눈 작음 · MediaPipe 오류를 일부러 일으켜 → 의도한 대로 넘어가는지, 원래대로 돌아오는지
#             + 사진에 진짜 얼굴이 없을 때 취소
#   E. 서버 : 켜져 있는 서버의 /health 가 같은 모델을 쓰는지 (옛 코드로 돌고 있으면 실패)
#
# [실행] (sleep_detector_api 폴더, 서버 venv — torch 필요)
#   venv\Scripts\python tools\check_cnn.py --closed 감은눈.jpg --open 뜬눈.jpg
#   venv\Scripts\python tools\check_cnn.py --closed 감은눈폴더 --open 뜬눈폴더
#   venv\Scripts\python tools\check_cnn.py --closed 감은눈.jpg --open 뜬눈.jpg --t 0.45          ← config 기준값 확인
#   venv\Scripts\python tools\check_cnn.py --closed 감은눈.jpg --model eye_cnn12_k085_100_s0.pt  ← config 를 바꾸기 전 새 모델 미리 시험 (ml_models/ 안)
#   사진 없이도 돌지만 C · D 는 건너뜀 → 마지막에 '일부만 확인' 으로 표시 (모델 교체 판단에는 사진을 꼭 넣기)
#
# [규칙] 사진은 저장소에 넣지 않는다 (경로만 받음, 화면에는 숫자와 파일 이름만). 파일을 바꾸지 않는다 (폴백은 메모리에서만 흉내)
#   실패가 하나라도 있으면 종료 코드 1
#
# 자세한 내용: services/face_service.py · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import argparse
import contextlib
import glob
import io
import json
import os
import shutil
import sys
import tempfile
import time
import urllib.error
import urllib.request

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)
os.chdir(BASE)
sys.stdout.reconfigure(encoding="utf-8")

import config  # noqa: E402

PHOTO_EXTS = (".jpg", ".jpeg", ".png", ".webp")
_fails = []


def check(name, ok, detail=""):
    print(f"  {'✅' if ok else '❌'} {name}" + (f"  — {detail}" if detail else ""))
    if not ok:
        _fails.append(name)
    return ok


def photos_of(items):
    """파일 · 폴더 경로 → 사진 파일 목록"""
    out = []
    for p in items or []:
        if os.path.isdir(p):
            out += sorted(f for f in glob.glob(os.path.join(p, "*")) if f.lower().endswith(PHOTO_EXTS))
        else:
            out.append(p)
    return out


def judge(fs, path, reason="microsleep"):
    """서버 판정 그대로 + 그동안 나온 [face_service] 로그"""
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        r = fs.check_eyes(path, None, reason)
    return r, [ln for ln in buf.getvalue().splitlines() if "[face_service]" in ln]


def part_a(fs, args):
    print("■ A. 설정")
    check("USE_REAL_AI = True (가짜 판정이 아님)", fs.USE_REAL_AI is True, f"{fs.USE_REAL_AI}")
    check("USE_CNN = True", fs.USE_CNN is True, f"{fs.USE_CNN}")
    check("모델 파일이 있음", os.path.isfile(fs.CNN_MODEL_PATH), os.path.basename(fs.CNN_MODEL_PATH))
    print(f"  ℹ️  기준: CNN 감음 ≥ {fs.CNN_CLOSED_PROB} · 확실히 뜸 < {round(fs.CNN_CLOSED_PROB - fs.CNN_OPEN_MARGIN, 3)} · "
          f"EAR 감음 < {fs.EAR_THRESHOLD} · EAR 확실히 뜸 ≥ {round(fs.EAR_THRESHOLD + fs.CONFIRM_OPEN_MARGIN, 3)}")
    if args.t is not None:
        check(f"config 기준값 = 고른 t ({args.t})", abs(fs.CNN_CLOSED_PROB - args.t) < 1e-9, f"config {fs.CNN_CLOSED_PROB}")


def part_b(fs):
    print("\n■ B. 모델")
    import numpy as np
    import torch
    t0 = time.perf_counter()
    with contextlib.redirect_stdout(io.StringIO()) as buf:
        model = fs._get_cnn()
    if not check("모델이 읽힘", model is not None, buf.getvalue().strip()[:120]):
        return False
    print(f"  ℹ️  읽는 시간 {time.perf_counter() - t0:.1f}초")
    x = np.zeros((2, fs.CNN_INPUT_SIZE, fs.CNN_INPUT_SIZE), dtype=np.float32)
    t0 = time.perf_counter()
    with torch.no_grad():
        p = torch.sigmoid(model(torch.from_numpy(x)[:, None].expand(-1, 3, -1, -1)).squeeze(1))
    ms = (time.perf_counter() - t0) * 1000
    check("확률이 0~1 로 나옴", bool(((p >= 0) & (p <= 1)).all()), f"{[round(float(v), 3) for v in p]}")
    print(f"  ℹ️  두 눈 1번 추론 {ms:.0f}ms (CPU)")
    return True


def part_c(fs, closed, opened):
    print("\n■ C. 사진 (서버 판정 그대로)")
    if not closed and not opened:
        print("  ⚠️ 사진 없음 → 건너뜀 (--closed · --open)")
        return
    thr = fs.CNN_CLOSED_PROB
    for label, paths in (("감은 눈", closed), ("뜬 눈", opened)):
        if not paths:
            print(f"  ⚠️ {label} 사진 없음 → {'감음' if label == '감은 눈' else '뜸'} 쪽은 확인 못 함")
            continue
        wrong = not_cnn = 0
        for p in paths:
            r, _ = judge(fs, p)
            prob = r["eye_closed_prob"]
            is_cnn = r["method"] == "cnn" and prob is not None
            good = is_cnn and (prob >= thr if label == "감은 눈" else prob < thr)
            not_cnn += not is_cnn
            wrong += is_cnn and not good
            mark = "✅" if good else "❌"
            print(f"    {mark} {os.path.basename(p)[-40:]}: method={r['method']} cnn={prob} ear={r['ear']} "
                  f"{'취소' if not r['is_sleep'] else '확정'}")
        check(f"{label} {len(paths)}장 모두 method = cnn", not_cnn == 0, f"cnn 아님 {not_cnn}장")
        check(f"{label} {len(paths)}장 CNN 판정이 맞음", wrong == 0, f"틀림 {wrong}장")


def part_d(fs, photo):
    print("\n■ D. 폴백 (메모리에서만 흉내 — 파일은 안 바꿈)")
    if not photo:
        print("  ⚠️ 얼굴 사진 없음 → 건너뜀")
        return
    import services.eye_preprocess as ep
    good_path, good_prob, good_crop, good_det = fs.CNN_MODEL_PATH, fs._cnn_closed_prob, ep.crop_eye, fs._get_detector
    tmp = tempfile.mkdtemp(prefix="check_cnn_")

    def reset_cnn():
        fs._cnn, fs._cnn_failed, fs._cnn_error = None, False, None

    def boom(*_a, **_k):
        raise RuntimeError("시험용 오류")

    def expect(name, method, sleep, need_log, after_log=True):
        r, logs = judge(fs, photo)
        ok = r["method"] == method and r["is_sleep"] is sleep and (bool(logs) == need_log or not after_log)
        check(name, ok, f"method={r['method']} 졸음={r['is_sleep']} 로그={'있음' if logs else '없음'}")

    try:
        reset_cnn()
        fs.CNN_MODEL_PATH = os.path.join(tmp, "없음.pt")
        expect("모델 파일 없음 → EAR + 로그", "ear", True, True)
        check("  /health 에 실패 표시", fs.cnn_status()["loaded"] is False and fs.cnn_status()["error"] is not None,
              f"error={fs.cnn_status()['error']}")
        reset_cnn()
        bad = os.path.join(tmp, "깨짐.pt")
        with open(bad, "wb") as f:
            f.write(b"broken")
        fs.CNN_MODEL_PATH = bad
        expect("모델 파일 깨짐 → EAR + 로그", "ear", True, True)
        fs.CNN_MODEL_PATH = good_path
        reset_cnn()

        fs._cnn_closed_prob = boom
        expect("CNN 추론 오류 → EAR + 로그", "ear", True, True)
        fs._cnn_closed_prob = good_prob

        # 눈이 너무 작음 — 로그 없이 EAR 로 넘어감 (지금 동작. 건수는 /health judged.ear 로 보임)
        ep.crop_eye = lambda *_a, **_k: None
        expect("눈이 너무 작음 → EAR", "ear", True, False)
        ep.crop_eye = good_crop

        fs._get_detector = boom
        expect("MediaPipe 오류 → 앱 판단대로 확정 + 로그", "mlkit", True, True)
        fs._get_detector = good_det

        r, _ = judge(fs, photo)
        check("오류를 치운 뒤 다시 CNN", r["method"] == "cnn", f"method={r['method']} cnn={r['eye_closed_prob']}")

        # 진짜 얼굴이 없는 사진 (회색 빈 사진, 임시 폴더) → 취소 (손 가리기 · 폰 돌아감)
        import cv2
        import numpy as np
        blank = os.path.join(tmp, "blank.jpg")
        cv2.imencode(".jpg", np.full((640, 480, 3), 128, np.uint8))[1].tofile(blank)
        nf, _ = judge(fs, blank)
        check("사진에 얼굴 없음 → 취소", nf["face_found"] is False and nf["is_sleep"] is False,
              f"method={nf['method']} 졸음={nf['is_sleep']}")
    finally:
        fs.CNN_MODEL_PATH, fs._cnn_closed_prob, ep.crop_eye, fs._get_detector = good_path, good_prob, good_crop, good_det
        shutil.rmtree(tmp, ignore_errors=True)


def part_e(fs, url):
    print("\n■ E. 켜져 있는 서버")
    try:
        with urllib.request.urlopen(f"{url}/health", timeout=5) as res:
            h = json.load(res)
    except (urllib.error.URLError, OSError, ValueError):
        print(f"  ⚠️ {url} 응답 없음 → 건너뜀 (서버가 꺼져 있으면 정상)")
        return
    eye = h.get("eye")
    if not check("/health 에 눈 판정 상태가 있음", bool(eye), "없으면 서버가 옛 코드 — 껐다 켜기"):
        return
    print(f"  ℹ️  {eye} · 판정 건수 {h.get('judged')}")
    check("서버가 가짜 판정이 아님", eye["mode"] == "real", eye["mode"])
    check("서버 모델 = 지금 시험한 모델", eye["model"] == os.path.basename(fs.CNN_MODEL_PATH), eye["model"])
    check("서버 기준값 = config", eye["closed_prob"] == fs.CNN_CLOSED_PROB, f"{eye['closed_prob']}")
    check("서버에 모델이 읽혀 있음", eye["loaded"] is True, f"error={eye['error']}")


def main():
    ap = argparse.ArgumentParser(description="CNN 연결 · 폴백 시험")
    ap.add_argument("--closed", nargs="*", default=[], help="감은 눈 얼굴 사진 (파일 · 폴더)")
    ap.add_argument("--open", nargs="*", default=[], help="뜬 눈 얼굴 사진 (파일 · 폴더)")
    ap.add_argument("--t", type=float, default=None, help="고른 기준값 — config.CNN_CLOSED_PROB 와 같은지 확인")
    ap.add_argument("--model", default="", help="config 대신 시험할 모델 (ml_models/ 안의 파일 이름). 이때 E 는 건너뜀")
    ap.add_argument("--server", default="http://127.0.0.1:8000", help="/health 를 볼 서버 주소")
    args = ap.parse_args()

    with contextlib.redirect_stdout(io.StringIO()):
        from services import face_service as fs
    if args.model:
        fs.CNN_MODEL_PATH = args.model if os.path.isabs(args.model) else os.path.join(BASE, "ml_models", args.model)
    print(f"CNN 연결 시험 — 모델 {os.path.basename(fs.CNN_MODEL_PATH)}{' (--model, config 아님)' if args.model else ''}\n")

    closed, opened = photos_of(args.closed), photos_of(args.open)
    part_a(fs, args)
    loaded = fs.USE_REAL_AI and part_b(fs)
    if loaded:
        part_c(fs, closed, opened)
        part_d(fs, (closed or opened or [None])[0])
    if not args.model:
        part_e(fs, args.server)

    partial = not (closed and opened)
    print("\n" + "=" * 50)
    if _fails:
        print(f"❌ 실패 {len(_fails)}개: " + " · ".join(_fails))
    elif partial:
        print("🟡 실패 없음, 다만 일부만 확인 (감은 눈 · 뜬 눈 사진을 모두 넣어야 전체 확인)")
    else:
        print("✅ 모두 통과")
    return 1 if _fails else 0


if __name__ == "__main__":
    sys.exit(main())
