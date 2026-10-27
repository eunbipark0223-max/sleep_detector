# ═══════════════════════════════════════════════════════════════
# notebooks/aihub_crop.py — AI-Hub 173 받기 + 눈 자르기 (PC 에서, eye_cnn.ipynb 3번 구간 준비)
# ═══════════════════════════════════════════════════════════════
# 담당: B (CNN 학습)  |  우선: P2 (CNN)
#
# [왜 PC 에서]
#   AI-Hub 는 해외 IP 다운로드를 막는다 → Colab 에서 aihubshell 이 HTTP 502 ("해외에서의 데이터 다운로드를 제한")
#   → 한국 PC 에서 받고 · 자르고, 자른 눈 사진(.npz)만 본인 구글 드라이브에 올려 Colab 에서 학습
#
# [하는 일]
#   download : filekey 6개를 AI-Hub API 로 받기 (aihubshell 과 같은 주소 · 헤더, 이어받기 됨) → tar 풀기 → .part 합치기
#   crop     : zip 풀기 → 라벨 JSON (Leye · Reye 의 Opened) → 얼굴 사진 → MediaPipe 눈 점 → crop_eye → 흑백 96×96
#              → eye_npz/crops_*.npz + summary.json   (서버 face_service.py 와 같은 MediaPipe · 눈 점 · crop_eye)
#
# [실행] 서버 venv (mediapipe 1.1.0 · opencv) 로:
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub_crop.py download
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub_crop.py crop --limit 300   (시험: 얼굴 찾는 비율 · 상자 안 비율 확인)
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub_crop.py crop
#   → D:\aihub173\eye_npz\ 폴더 통째로 구글 드라이브 sleep_detector/aihub_eye/ 에 올린다
#
# [규칙]
#   - API 키는 notebooks/.env 의 AIHUB_API_KEY (.gitignore 에 있음). 키는 출력하지 않는다
#   - 🔴 AI-Hub 원본 · 자른 눈 사진은 저장소 밖(D:\aihub173)과 본인 드라이브에만. GitHub · 단톡 · 공유 드라이브 X
#   - 출처: AI-Hub 「졸음운전 예방을 위한 운전자 상태 정보 영상」 (dataSetSn=173)
# ═══════════════════════════════════════════════════════════════

import argparse
import collections
import glob
import hashlib
import json
import os
import random
import re
import sys
import tarfile
import time
import urllib.error
import urllib.request
import zipfile
from multiprocessing import Pool

import cv2
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "sleep_detector_api", "services"))
from eye_preprocess import crop_eye  # noqa: E402  서버와 같은 파일

ROOT = r"D:\aihub173"  # 저장소 밖
ENV_PATH = os.path.join(HERE, ".env")
DOWN_URL = "https://api.aihub.or.kr/down/0.6/173.do"  # aihubshell v0.6 과 같은 주소
FILEKEYS = {
    45009: "Validation 라벨 실제도로", 45012: "Validation 원천 실제도로",
    45010: "Validation 라벨 통제", 45013: "Validation 원천 통제",
    45072: "Training 라벨 실제도로", 45006: "Training 원천 실제도로",
}

FACE_TASK_URL = "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
# face_service.py LEFT_EYE / RIGHT_EYE 와 같은 번호. "L" = 사진 왼쪽 눈 (= 본인 오른눈, 33번 묶음) = AI-Hub JSON Leye (99.98% 사진 왼쪽)
EYE_IDX = {"L": [33, 160, 158, 133, 153, 144], "R": [362, 385, 387, 263, 373, 380]}
STORE = 96            # 저장 크기 (학습 때 augment → prep_eye 가 64×64 로)
CHUNK = 5000          # 사진 이만큼마다 .npz 하나 (끊겨도 이어서)
MAX_PER_DRIVER = 200  # Training 실제도로만: 운전자마다 최대 사진 수 (이웃 프레임이 거의 같음)
BOX_MARGIN = 0.25     # MediaPipe 눈 중심이 JSON 눈 상자를 사방 25% (= 50%) 넓힌 범위 안이어야 씀
SEED = 0


# ── download ─────────────────────────────────────
def read_key():
    for line in open(ENV_PATH, encoding="utf-8"):
        line = line.strip()
        if line.startswith("AIHUB_API_KEY") and "=" in line:
            return line.split("=", 1)[1].strip().strip("\"'")
    raise SystemExit(f"{ENV_PATH} 에 AIHUB_API_KEY=… 가 없습니다")


def download():
    key = read_key()
    tar_dir, raw_dir = os.path.join(ROOT, "tar"), os.path.join(ROOT, "raw")
    os.makedirs(tar_dir, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    for fk, name in FILEKEYS.items():
        tar_path = os.path.join(tar_dir, f"{fk}.tar")
        done = tar_path + ".done"
        if os.path.exists(done):
            print(f"[{fk}] {name} — 이미 받음")
            continue
        have = os.path.getsize(tar_path) if os.path.exists(tar_path) else 0
        req = urllib.request.Request(f"{DOWN_URL}?fileSn={fk}", headers={"apikey": key})
        if have:
            req.add_header("Range", f"bytes={have}-")
        try:
            resp = urllib.request.urlopen(req, timeout=60)
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace").replace(key, "***")
            raise SystemExit(f"[{fk}] HTTP {e.code}: {body[:300]}")
        mode = "ab" if have and resp.status == 206 else "wb"
        total = int(resp.headers.get("Content-Length", 0)) + (have if mode == "ab" else 0)
        got, t0, last = (have if mode == "ab" else 0), time.time(), 0
        with open(tar_path, mode) as f:
            while chunk := resp.read(1 << 20):
                f.write(chunk)
                got += len(chunk)
                if got - last > 200 << 20:
                    last = got
                    print(f"[{fk}] {got / 1e9:.2f} / {total / 1e9:.2f}GB  {got / 1e6 / max(time.time() - t0, 1):.0f}MB/s")
        print(f"[{fk}] {name} 받음 {got / 1e9:.2f}GB → 풀기")
        with tarfile.open(tar_path) as tf:
            tf.extractall(raw_dir)
        open(done, "w").close()
    merge_parts(raw_dir)
    print("zip:", *[os.path.relpath(z, raw_dir) for z in list_zips()], sep="\n  ")


def merge_parts(raw_dir):
    parts = collections.defaultdict(list)
    for p in glob.glob(os.path.join(raw_dir, "**", "*.part*"), recursive=True):
        m = re.match(r"(.*)\.part(\d+)$", p)
        if m:
            parts[m[1]].append((int(m[2]), p))
    for target, ps in parts.items():
        with open(target, "wb") as out:
            for _, p in sorted(ps):
                with open(p, "rb") as f:
                    while chunk := f.read(1 << 24):
                        out.write(chunk)
        for _, p in ps:
            os.remove(p)
        print("조각 합침:", os.path.basename(target), len(ps), "개")


def list_zips():
    return sorted(glob.glob(os.path.join(ROOT, "raw", "**", "*.zip"), recursive=True))


# ── crop ─────────────────────────────────────────
def unzip_all():
    ex_dir = os.path.join(ROOT, "ex")
    for z in list_zips():
        rel = os.path.relpath(z, os.path.join(ROOT, "raw"))
        dst = os.path.join(ex_dir, rel[:-4])
        if os.path.exists(os.path.join(dst, ".done")):
            continue
        t0 = time.time()
        with zipfile.ZipFile(z) as zf:
            for info in zf.infolist():
                name = info.filename if info.flag_bits & 0x800 else info.filename.encode("cp437").decode("cp949", "replace")
                if name.endswith("/"):
                    continue
                out = os.path.join(dst, name)
                os.makedirs(os.path.dirname(out), exist_ok=True)
                with zf.open(info) as src, open(out, "wb") as f:
                    f.write(src.read())
        open(os.path.join(dst, ".done"), "w").close()
        print(f"풀기 {time.time() - t0:4.0f}초  {rel}")
    return ex_dir


def read_labels(ex_dir):
    """눈 하나 = 한 줄. 보이는 눈 · Opened 가 있는 눈만. y = 감음 1 / 뜸 0"""
    lab = {}
    for jp in glob.glob(os.path.join(ex_dir, "**", "*.json"), recursive=True):
        rel = os.path.relpath(jp, ex_dir)
        if "라벨" not in rel:
            continue
        d = json.load(open(jp, encoding="utf-8"))
        bb = d["ObjectInfo"]["BoundingBox"]
        cat = next((p for p in rel.split(os.sep) if re.match(r"^\d\.(버스|승용|택시|트럭)$", p)), "통제")
        base = dict(driver=int(d["UserInfo"]["ID"]), env="road" if "실제도로" in rel else "ctrl", cat=cat,
                    src="Training" if "Training" in rel else "Validation",
                    glasses=bool(d["Accessory"].get("Glasses", False)),  # 22만 건 중 20건은 Glasses 키 없음
                    mask=bool(d["Accessory"].get("Mask", False)),
                    gender=int(d["UserInfo"]["Gender"]), age=int(d["UserInfo"]["Age"]))
        for side, k in (("L", "Leye"), ("R", "Reye")):
            e = bb[k]
            if e["isVisible"] and isinstance(e.get("Opened"), bool):
                lab[(d["FileInfo"]["FileName"], side)] = dict(base, y=int(not e["Opened"]), box=[float(v) for v in e["Position"]])
    return lab


def pick_files(lab, img_path):
    """Training 실제도로만 운전자마다 MAX_PER_DRIVER 장으로 (감음 사진은 전부 남김)"""
    per_file = {}
    for (f, _), r in lab.items():
        if f in img_path:
            p = per_file.setdefault(f, dict(r, closed=0))
            p["closed"] = max(p["closed"], r["y"])
    groups = collections.defaultdict(list)
    for f, r in per_file.items():
        groups[(r["src"], r["env"], r["driver"])].append((f, r["closed"]))
    rng, keep = random.Random(SEED), []
    for (src, env, _), fs in sorted(groups.items()):
        fs.sort()
        if not (src == "Training" and env == "road"):
            keep += [f for f, _ in fs]
            continue
        c, o = [f for f, cl in fs if cl], [f for f, cl in fs if not cl]
        n_open = max(MAX_PER_DRIVER - len(c), MAX_PER_DRIVER // 2)
        keep += c + rng.sample(o, min(n_open, len(o)))
    return sorted(set(keep))


_det = None


def _init(face_task):
    global _det
    import mediapipe as mp  # noqa: F401
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    _det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=face_task), num_faces=1))


def crop_one(path):
    """사진 1장 → {'L': (눈 96×96 uint8, 눈 중심 x, y), 'R': …} / 얼굴 없음 → None"""
    import mediapipe as mp
    bgr = cv2.imdecode(np.fromfile(path, dtype=np.uint8), cv2.IMREAD_COLOR)  # 한글 경로
    if bgr is None:
        return None
    h, w, _ = bgr.shape
    res = _det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
    if not res.face_landmarks:
        return None
    lm = res.face_landmarks[0]
    out = {}
    for side, idx in EYE_IDX.items():
        pts = [(lm[i].x * w, lm[i].y * h) for i in idx]
        eye = crop_eye(bgr, pts)
        if eye is None:  # 눈이 너무 작거나 사진 밖 (crop_eye 가 None, 10.27 팀장 수정) → 이 눈은 버림
            continue
        eye = cv2.cvtColor(eye, cv2.COLOR_BGR2GRAY)
        interp = cv2.INTER_AREA if min(eye.shape) >= STORE else cv2.INTER_LINEAR
        out[side] = (cv2.resize(eye, (STORE, STORE), interpolation=interp),
                     (pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2)
    return out


def in_box(cx, cy, box):
    x1, y1, x2, y2 = box
    mw, mh = (x2 - x1) * BOX_MARGIN, (y2 - y1) * BOX_MARGIN
    return x1 - mw < cx < x2 + mw and y1 - mh < cy < y2 + mh


def crop(limit=0):
    face_task = os.path.join(ROOT, "face_landmarker.task")  # 서버 ml_models/ 와 같은 파일, 저장소 밖에 받음
    if not os.path.exists(face_task):
        os.makedirs(ROOT, exist_ok=True)
        urllib.request.urlretrieve(FACE_TASK_URL, face_task)
    ex_dir = unzip_all()
    lab = read_labels(ex_dir)
    img_path = {os.path.basename(p): p for p in glob.glob(os.path.join(ex_dir, "**", "*"), recursive=True)
                if "원천" in p and p.lower().endswith((".jpg", ".jpeg", ".png"))}
    files = pick_files(lab, img_path)
    if limit:  # 시험용: 무작위 limit 장만, 결과는 eye_npz_test/ 에 (드라이브에 올리지 않음)
        files = sorted(random.Random(SEED).sample(files, min(limit, len(files))))
    print(f"눈 라벨 {len(lab)} / 원천 사진 {len(img_path)} / 쓸 사진 {len(files)}")

    out_dir = os.path.join(ROOT, "eye_npz_test" if limit else "eye_npz")
    os.makedirs(out_dir, exist_ok=True)
    made, t0 = [], time.time()
    with Pool(max(os.cpu_count() - 1, 1), initializer=_init, initargs=(face_task,)) as pool:
        for ci in range(0, len(files), CHUNK):
            part = files[ci:ci + CHUNK]
            name = f"crops_{hashlib.md5(('|'.join(part) + f'{STORE}{BOX_MARGIN}').encode()).hexdigest()[:10]}.npz"
            made.append(name)
            if os.path.exists(os.path.join(out_dir, name)):
                continue
            res = pool.map(crop_one, [img_path[f] for f in part], chunksize=16)
            cols = collections.defaultdict(list)
            cnt = collections.Counter(files=len(part))
            for f, r in zip(part, res):
                if r is None:
                    cnt["noface"] += 1
                    continue
                for side, (eye, cx, cy) in r.items():
                    lb = lab.get((f, side))
                    if lb is None:
                        cnt["eye_not_visible"] += 1
                    elif not in_box(cx, cy, lb["box"]):
                        cnt["outside_box"] += 1
                    else:
                        cnt["eyes"] += 1
                        cols["X"].append(eye)
                        cols["fname"].append(f)  # "file" 은 savez 인자 이름과 겹침
                        cols["side"].append(side)
                        for k in ("y", "driver", "env", "cat", "src", "glasses", "mask", "gender", "age"):
                            cols[k].append(lb[k])
            np.savez_compressed(os.path.join(out_dir, name), X=np.stack(cols["X"]),
                                **{k: np.array(v) for k, v in cols.items() if k != "X"},
                                counts=json.dumps(cnt))
            print(f"{ci + len(part)}/{len(files)}장  {time.time() - t0:.0f}초  {dict(cnt)}")

    for p in glob.glob(os.path.join(out_dir, "crops_*.npz")):  # 이번 설정과 다른 묶음은 지운다 (드라이브에 섞이지 않게)
        if os.path.basename(p) not in made:
            os.remove(p)
    total = collections.Counter()
    for n in made:
        total.update(json.loads(str(np.load(os.path.join(out_dir, n))["counts"])))
    summary = dict(made=time.strftime("%Y-%m-%d %H:%M"), max_per_driver=MAX_PER_DRIVER, store=STORE, box_margin=BOX_MARGIN,
                   seed=SEED, chunks=made, counts=dict(total))
    json.dump(summary, open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    size = sum(os.path.getsize(os.path.join(out_dir, n)) for n in made) / 1e9
    print(f"끝: {out_dir}  {len(made)}개 {size:.2f}GB  {dict(total)}")
    print("→ eye_npz 폴더를 구글 드라이브 sleep_detector/aihub_eye/ 에 올리세요")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("step", choices=["download", "crop"])
    ap.add_argument("--root", default=ROOT, help="받기 · 풀기 · 결과 폴더 (저장소 밖)")
    ap.add_argument("--limit", type=int, default=0, help="crop 시험용: 이만큼만 (결과는 eye_npz_test/)")
    a = ap.parse_args()
    ROOT = a.root
    download() if a.step == "download" else crop(a.limit)
