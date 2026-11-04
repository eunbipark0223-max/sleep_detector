# ═══════════════════════════════════════════════════════════════
# notebooks/aihub548.py — AI-Hub 548 (안구 움직임, 한국인 RGB) 받기 · 시험 · 눈 자르기 (PC 에서, eye_cnn.ipynb 6번 구간 준비)
# ═══════════════════════════════════════════════════════════════
# 담당: B (CNN 학습)  |  우선: P2 (CNN)
#
# [왜 548]  (11/02 팀장 결정)
#   지금 CNN 은 적외선(MRL · AI-Hub 173)으로만 학습 → 폰 같은 컬러 카메라에서 확인 필요
#   548 = 한국인 1,510명 웹캠 RGB 1280×720 (얼굴 전체, 30 · 50cm, 정면 · 좌 · 우 보기, 안경 · 마스크 섞임)
#        + 눈꺼풀 라벨 open / half / closed (CVAT XML, 눈마다 16점 다각형)
#   ⚠️ 시선 데이터라 감은 눈이 적음 (Validation G1: RGB 28,080장 중 half 478 · closed 505)
#   ⚠️ 사람이 아니라 사진 단위로 나뉨 — Validation G1 65명(526~590번)이 Training G1 안에 전원 있음
#      → 추가 학습용 눈 자르기에서 Validation 사람은 반드시 뺀다 (eval 이 공정하게)
#
# [하는 일]
#   download : filekey 를 AI-Hub API 로 받기 (aihub_crop.py 와 같은 방식, 이어받기 됨) → tar 풀기 → .part 합치기
#   eval     : Validation G1 → 지금 서버 판정(face_service 그대로) 시험 — 감음 · 반쯤 전부 + 사람 · 거리마다 뜸 25장
#              → result_g1.csv (사진마다 한 줄, 저장소 밖에만) + 요약 출력
#   wandb    : eval 결과 숫자 · 묶음 표만 W&B eye-cnn 에 (run b_eval548_g1)
#   crop     : 추가 학습용 — 학습 라벨(TL.zip) + 학습 사진 zip(TS_*) → 서버와 같은 MediaPipe · crop_eye → 흑백 96×96 눈
#              → eye_npz/crops_*.npz + summary.json (aihub_crop.py 와 같은 모양 → eye_cnn.ipynb 에서 3-1 처럼 읽음)
#              · Validation(VL.zip) 에 있는 사람은 전부 뺌 (사람 = 그룹 + 번호, 예: G1_526 — 번호는 그룹마다 따로 매겨짐)
#              · 남은 사람을 사람 단위로 train / val 85 : 15 (시드 0) → split 칸. 기준값은 val 로 고르고, 시험은 Validation · 팀 사진
#              · 눈 하나 = 한 줄. 라벨은 그 눈 다각형의 status: y = 감음 1 / 뜸 0 / 반쯤 -1 (반쯤을 학습에 넣을지는 노트북에서)
#              · 사진 고르기: 감음 · 반쯤 감음 사진 전부 + 사람 · 거리마다 뜸 OPEN_PER_TRAIN 장
#              · 라벨의 left_eyelid = 사진 왼쪽 눈. 그래도 이름 대신 MediaPipe 눈 중심 ↔ 다각형 중심 거리로 짝지음 (먼 눈은 버림)
#
# [실행] 서버 venv (mediapipe 1.1.0 · opencv · torch) 로, 저장소 폴더에서:
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py download --keys 55882
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py eval [--set val_g1 | val | train]
#     val_g1 = Validation G1 65명 (첫 시험) · val = Validation 전부 151명 · train = TS_G1_1 (Validation 사람 뺌, 지금 모델이 안 본 사람)
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py eval --set val --model eye_cnn_548.pt
#     (eye_cnn.ipynb 7번에서 학습한 모델로 같은 시험 → result_val_eye_cnn_548.csv, 지금 모델 result_val.csv 와 비교)
#   ... eval --set val --model eye_cnn8_resnet18.pt,eye_cnn8_effb0.pt,eye_cnn8_mnv3.pt   (8번 앙상블: 감음 확률 평균)
#   ... team [--model ...]   팀 사진 (D:\aihub173\kpi_eye\images · images_cond) 서버 판정 → 묶음 × 라벨 요약
#   ... eval|team ... --tta   좌우 반전 평균 (결과 이름 끝 _tta)
#   ... wrong --csv result_val_eye_cnn_548.csv   틀린 사진의 눈만 모은 그림 → D:\aihub548\wrong_*.png (저장소 X)
#   ... curve [--csvs result_val.csv,result_val_eye_cnn_548.csv]   기준값 0.05~0.95 곡선 (오경보 ↔ 반쯤 · 감은 눈 취소) 모델끼리 겹침
#       + 오경보 0.5 · 1 · 3% 고정점 + 지금 기준값 보고 형식 (전체 / 판정됨 / 판정 불가 / 해당 / 비율 / 95% 범위) — 중간 점검 피드백 11/04
#   ... extra [--dir D:\aihub71421\sel] [--model ...]   외부 사진 시험 (하위 폴더 closed · open, 학습에 안 씀)
#       기본 = AI-Hub 71421 「디스플레이 중심 안구 움직임」 Validation 13명 (한국인 · 스마트폰 · 차량 LCD 등, 라벨: 홍채 없음 + 눈꺼풀 세로/가로 < 0.15 = 감음)
#       (참고: CEW 는 --dir D:\cew\faces\dataset_B_FacialImages --pad 0.4 — 외국인 얼굴이라 판단에는 안 씀, 11/03)
#   set PYTHONUTF8=1 && sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py wandb
#     (PYTHONUTF8: 사용자 폴더 이름이 한글이면 wandb 가 cp949 로 읽다 실패함)
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py crop --limit 300   (시험: 결과는 eye_npz_test/)
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py crop
#   → D:\aihub548\eye_npz\ 안 파일을 구글 드라이브 sleep_detector/aihub548_eye/ 에 (본인 드라이브만)
#   sleep_detector_api\venv\Scripts\python.exe notebooks\aihub548.py crop --color
#   → D:\aihub548\eye_npz_color\ (컬러 눈, eye_cnn.ipynb 8번) → 드라이브 sleep_detector/aihub548_eye_color/
#
# [filekey]  TL 55881 · TS_G1_1 55882 · TS_G1_2 55883 · TS_G2_1 55884 · TS_G2_2 55885 · TS_U_1 55886 · TS_U_2 55887
#            VL 55888 · VS_G1 55889 · VS_G2 55890 · VS_U 55891
#
# [규칙]
#   - API 키는 notebooks/.env 의 AIHUB_API_KEY (.gitignore 에 있음). 키는 출력하지 않는다
#   - 🔴 AI-Hub 원본 · 꺼낸 사진 · 사진마다 한 줄 결과는 저장소 밖(D:\aihub548)과 본인 드라이브에만. GitHub · 단톡 X
#   - W&B 에는 숫자 · 묶음 표만 (사진 · 사진마다 한 줄 · 키 X)
#   - 출처: AI-Hub 「안구 움직임 영상 데이터」 (dataSetSn=548)
# ═══════════════════════════════════════════════════════════════

import argparse
import collections
import csv
import glob
import os
import random
import re
import sys
import tarfile
import time
import urllib.error
import urllib.request
import xml.etree.ElementTree as ET
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
API_DIR = os.path.join(HERE, "..", "sleep_detector_api")
ROOT = r"D:\aihub548"  # 저장소 밖
ENV_PATH = os.path.join(HERE, ".env")
DOWN_URL = "https://api.aihub.or.kr/down/0.6/548.do"  # aihubshell v0.6 과 같은 주소 (aihub_crop.py 와 같음)
OPEN_PER = 25  # eval: 사람 · 거리마다 뜬 눈 사진 수
OPEN_PER_TRAIN = 30  # crop: 사람 · 거리마다 뜬 눈 사진 수 (이웃 프레임이 거의 같아서 많이 넣어도 이득 적음)
VAL_FRAC = 0.15  # crop: val 로 뗄 사람 비율
STORE = 96  # crop: 저장 크기 (학습 때 augment → prep_eye 가 64×64 로, aihub_crop.py 와 같음)
CHUNK = 5000  # crop: 사진 이만큼마다 .npz 하나 (끊겨도 이어서)
MATCH = 0.6  # crop: MediaPipe 눈 중심이 라벨 다각형 중심에서 '다각형 폭 × 이 값' 안이어야 같은 눈
Y_OF = {"open": 0, "closed": 1, "half": -1}
SEED = 0


def zname(info):
    """zip 안 이름 (한글 폴더가 cp949 로 들어 있음)"""
    return info.filename if info.flag_bits & 0x800 else info.filename.encode("cp437").decode("cp949", "replace")


WEB_DIR = r"D:\033.안구 움직임 영상 데이터"  # AI-Hub 웹 화면에서 받은 폴더 (VL · VS_G1 은 여기로 받았음)
EXTRA_DIR = r"D:\aihub548_extra"  # 동시에 받은 묶음 (TL · VS_G2 · VS_U) — 받는 중 조각 파일이 섞이지 않게 폴더를 나눔


def data_dirs():
    return (ROOT, WEB_DIR, EXTRA_DIR)


def find(pattern):
    """ROOT · WEB_DIR · EXTRA_DIR 아래에서 파일 하나 찾기 (API 로 받은 구조 · 브라우저로 받은 구조 둘 다)"""
    hits = sorted(h for d in data_dirs() for h in glob.glob(os.path.join(d, "**", pattern), recursive=True)
                  if os.path.getsize(h) > 0)  # 브라우저로 받다 멈춘 0바이트 파일은 건너뜀
    if not hits:
        raise SystemExit(f"{' · '.join(data_dirs())} 아래에 {pattern} 이 없습니다 (download 먼저, 또는 --root)")
    return hits[0]


# ── download ─────────────────────────────────────
def read_key():
    for line in open(ENV_PATH, encoding="utf-8"):
        line = line.strip()
        if line.startswith("AIHUB_API_KEY") and "=" in line:
            return line.split("=", 1)[1].strip().strip("\"'")
    raise SystemExit(f"{ENV_PATH} 에 AIHUB_API_KEY=… 가 없습니다")


def download(keys):
    key = read_key()
    tar_dir, raw_dir = os.path.join(ROOT, "tar"), os.path.join(ROOT, "raw")
    os.makedirs(tar_dir, exist_ok=True)
    os.makedirs(raw_dir, exist_ok=True)
    for fk in keys:
        tar_path = os.path.join(tar_dir, f"{fk}.tar")
        done = tar_path + ".done"
        if os.path.exists(done):
            print(f"[{fk}] 이미 받음")
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
                if got - last > 1 << 30:
                    last = got
                    print(f"[{fk}] {got / 1e9:.1f} / {total / 1e9:.1f}GB  {got / 1e6 / max(time.time() - t0, 1):.0f}MB/s", flush=True)
        print(f"[{fk}] 받음 {got / 1e9:.2f}GB → 풀기", flush=True)
        with tarfile.open(tar_path) as tf:
            tf.extractall(raw_dir)
        open(done, "w").close()
        os.remove(tar_path)  # 88GB 를 두 번 들고 있지 않게 (풀었으면 tar 는 필요 없음)
    merge_parts(raw_dir)


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


# ── 라벨 ─────────────────────────────────────────
def read_labels(label_zip, group=None):
    """사진 이름 → open / half / closed (두 눈 모두 closed = closed, 하나라도 half · closed = half). group 을 주면 그 그룹 폴더만"""
    label = {}
    with zipfile.ZipFile(label_zip) as z:
        for i in z.infolist():
            n = zname(i)
            if not n.endswith("_RGB.xml") or (group and not n.startswith(group + "/")):
                continue
            for im in ET.fromstring(z.read(i)).iter("image"):
                st = [([t.text for t in pg.iter("attribute") if t.get("name") == "status"] or ["open"])[0]
                      for pg in im.iter("polygon") if pg.get("label", "").endswith("eyelid")]
                s = set(st)
                label[im.get("name")] = "closed" if s == {"closed"} else "half" if s & {"half", "closed"} else "open"
    return label


# ── eval ─────────────────────────────────────────
EVAL_SETS = {
    # 이름: (라벨 zip, 라벨 그룹, 사진 zip 들, Validation 사람 빼기, 결과 CSV)
    "val_g1": ("VL.zip", "G1", ["VS_G1.zip"], False, "result_g1.csv"),  # 11/02 첫 시험 (65명)
    "val": ("VL.zip", None, ["VS_G1.zip", "VS_G2.zip", "VS_U.zip"], False, "result_val.csv"),  # Validation 전부 (151명)
    "train": ("TL.zip", None, ["TS_G1_1.[zZ]ip"], True, "result_train.csv"),  # 학습용 묶음 — 지금 모델은 548 을 안 봤으니 시험지로도 됨 (Validation 사람 뺌)
}


def make_net(arch):
    """모델 구조 (eye_cnn.ipynb 8-4 make_net 과 같음) — 출력 1개 = 감음 logit, 흑백을 3채널로 복사해 넣음"""
    import torch
    import torchvision
    if arch == "resnet18":
        m = torchvision.models.resnet18(weights=None)
        m.fc = torch.nn.Linear(m.fc.in_features, 1)
    elif arch == "efficientnet_b0":
        m = torchvision.models.efficientnet_b0(weights=None)
        m.classifier[1] = torch.nn.Linear(m.classifier[1].in_features, 1)
    elif arch == "mobilenet_v3_large":
        m = torchvision.models.mobilenet_v3_large(weights=None)
        m.classifier[3] = torch.nn.Linear(m.classifier[3].in_features, 1)
    else:
        raise SystemExit(f"모르는 모델 구조: {arch}")
    return m


def use_model(fs, model, tta=False):
    """face_service 가 쓸 CNN 을 바꿈 (서버 config.py 는 안 바꿈) → 결과 파일 이름에 붙일 말
    model: ml_models/ 안 이름 또는 경로. 쉼표로 여러 개면 감음 확률 평균(앙상블). .pt 의 arch 로 구조를 고름
    tta: 눈을 좌우 반전해 한 번 더 넣고 확률 평균 (eye_cnn.ipynb 9-3)"""
    import torch
    model = model or os.path.basename(fs.CNN_MODEL_PATH)
    paths = [os.path.abspath(p if os.path.exists(p) else os.path.join(API_DIR, "ml_models", p)) for p in model.split(",")]
    nets = []
    for p in paths:
        if not os.path.exists(p):
            raise SystemExit(f"모델 파일이 없습니다: {p}")
        ck = torch.load(p, map_location="cpu", weights_only=True)
        nets.append(make_net(ck.get("arch", "resnet18")))
        nets[-1].load_state_dict(ck["state_dict"])
        print("CNN 모델:", p, ck.get("arch", "resnet18"), flush=True)

    class Avg(torch.nn.Module):  # face_service._cnn_closed_prob 가 sigmoid 하므로 평균 확률을 logit 으로 돌려줌
        def __init__(self, ms):
            super().__init__()
            self.ms = torch.nn.ModuleList(ms)

        def forward(self, x):
            xs = [x, x.flip(-1)] if tta else [x]
            p = torch.stack([torch.sigmoid(m(v)) for m in self.ms for v in xs]).mean(0).clamp(1e-6, 1 - 1e-6)
            return torch.log(p / (1 - p))

    fs._cnn, fs._cnn_failed = Avg(nets).eval(), False
    stem = os.path.splitext(os.path.basename(paths[0]))[0]
    return (stem if len(paths) == 1 else f"{stem}_ens{len(paths)}") + ("_tta" if tta else "")


def _judge(fs, img, tmp, scale=1.0, info=None, blur=0.0, jpeg=0):
    """사진 한 장 (BGR 배열) → 서버 판정 그대로 (_real → _normalize) + 눈 폭(px, 두 눈 눈꼬리 사이 평균 — 눈 crop 원래 크기)
    scale < 1 이면 사진 전체를 줄여서 넣음 (저해상도 확인 — 중간 점검 피드백 11/04). face_service 는 안 고치고 얼굴 검출 결과만 엿봄
    blur (가우시안 시그마 px) · jpeg (품질 1~100) 은 줄인 뒤 더 망가뜨리기 (CEW 원인 확인 — cewcheck)
    info 에 dict 를 주면 눈 점 (사진 왼쪽 눈 · 오른쪽 눈 6점씩, 넣은 사진 기준 px) · 눈 선명도를 채움"""
    import cv2
    import numpy as np
    if scale != 1.0:
        img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_AREA)
    if blur:
        img = cv2.GaussianBlur(img, (0, 0), blur)
    if jpeg:
        img = cv2.imdecode(cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, jpeg])[1], cv2.IMREAD_COLOR)
    cv2.imencode(".png", img)[1].tofile(tmp)  # imwrite 는 한글 경로에서 실패. png = 화질 그대로
    det, seen = fs._get_detector(), {}

    class Peek:  # _real 이 부르는 detect 결과를 그대로 넘기면서 눈 점만 봄
        def detect(self, im):
            seen["r"] = det.detect(im)
            return seen["r"]

    orig, fs._get_detector = fs._get_detector, lambda: Peek()
    try:
        thr = fs.EAR_THRESHOLD
        n = fs._normalize(fs._real(tmp, thr), thr, "microsleep")
    finally:
        fs._get_detector = orig
    eye_w = None
    if seen.get("r") is not None and seen["r"].face_landmarks:
        h, w = img.shape[:2]
        lm = seen["r"].face_landmarks[0]
        eye_w = round(float(np.mean([np.hypot((lm[a].x - lm[b].x) * w, (lm[a].y - lm[b].y) * h)
                                     for a, b in ((fs.LEFT_EYE[0], fs.LEFT_EYE[3]), (fs.RIGHT_EYE[0], fs.RIGHT_EYE[3]))])), 1)
        if info is not None:
            pts = [np.array([(lm[i].x * w, lm[i].y * h) for i in eye]) for eye in (fs.LEFT_EYE, fs.RIGHT_EYE)]
            info["pts"] = pts
            info["sharp"] = _sharp(img, pts)
    return n, eye_w


def _sharp(img, pts):
    """눈 선명도 — 눈마다 눈꼬리 사이 거리만 한 정사각형을 32×32 로 맞춘 뒤 라플라시안 분산 (두 눈 평균). 눈 크기와 상관없이 '눈 안에 디테일이 얼마나 남았나'"""
    import cv2
    import numpy as np
    g, out = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY), []
    for p in pts:
        c, s = p.mean(0), max(np.hypot(*(p[0] - p[3])), 4) / 2
        x0, y0, x1, y1 = int(c[0] - s), int(c[1] - s), int(c[0] + s) + 1, int(c[1] + s) + 1
        patch = g[max(y0, 0):y1, max(x0, 0):x1]
        if patch.size >= 16:
            out.append(cv2.Laplacian(cv2.resize(patch, (32, 32), interpolation=cv2.INTER_LINEAR), cv2.CV_64F).var())
    return round(float(np.mean(out)), 1) if out else None


def evaluate(which="val_g1", model="", tta=False, scale=1.0):
    """지금 서버 판정(face_service 그대로)으로 548 시험 — 감음 · 반쯤 전부 + 사람 · 거리마다 뜸 OPEN_PER 장
    model: 다른 CNN 파일로 시험 (use_model — 쉼표로 여러 개면 앙상블) → 결과 CSV 이름 뒤에 모델 이름
    scale: 사진을 이 배율로 줄여서 시험 (CEW 처럼 눈이 작을 때 오경보가 오르나 — 해상도 원인 확인) → 이름 뒤 _s배율"""
    import tempfile
    import cv2
    import numpy as np
    sys.path.insert(0, API_DIR)
    os.chdir(API_DIR)
    from services import face_service as fs  # 서버 판정 그대로 (config.py 의 CNN · EAR 기준)

    label_zip, group, img_zips, drop_val, out_name = EVAL_SETS[which]
    if model or tta:
        out_name = out_name.replace(".csv", f"_{use_model(fs, model, tta)}.csv")
    if scale != 1.0:
        out_name = out_name.replace(".csv", f"_s{scale:g}.csv")
    label = read_labels(find(label_zip), group)
    drop = val_people(find("VL.zip")) if drop_val else set()
    zips, items, meta = {}, {}, {}  # 사진 이름 → (zip, 안 이름) / (zip, 번호) → 사람 정보
    for pattern in img_zips:
        zp = find(pattern)
        zips[zp] = zipfile.ZipFile(zp)
        for i in zips[zp].infolist():
            n = zname(i)
            if "/RGB/" in n and n.endswith(".jpg"):
                items[os.path.basename(n)] = (zp, i)
            elif n.endswith("meta.xml"):
                t = ET.fromstring(zips[zp].read(i))
                meta[(zp, t.findtext("id"))] = dict(age=t.findtext("age"), gender=t.findtext("gender"), glasses=t.findtext("glasses"))
    rng, groups, pick = random.Random(SEED), collections.defaultdict(list), []
    for f in sorted(items):
        lab = label.get(f)
        if not lab or person_of(f) in drop:
            continue
        if lab == "open":
            groups[(person_of(f), f.split("_")[4])].append(f)
        else:
            pick.append(f)
    for k in sorted(groups):
        pick += rng.sample(groups[k], min(OPEN_PER, len(groups[k])))
    print(f"[{which}] 라벨 {len(label)} / RGB {len(items)} / 뺀 Validation 사람 {len(drop)} / 고른 사진 {len(pick)}",
          dict(collections.Counter(label[f] for f in pick)), flush=True)

    rows, tmp = [], os.path.join(tempfile.gettempdir(), "aihub548_eval.png")  # 사진은 한 장씩 임시 파일에만 (저장소 · 드라이브에 안 남김)
    for k, f in enumerate(pick, 1):
        zp, info = items[f]
        img = cv2.imdecode(np.frombuffer(zips[zp].read(info), np.uint8), cv2.IMREAD_COLOR)
        n, eye_w = _judge(fs, img, tmp, scale)
        rows.append(dict(file=f, person=person_of(f), dist=f.split("_")[4], view=f.split("_")[6], label=label[f],
                         **{"age": "", "gender": "", "glasses": "", **meta.get((zp, f.split("_")[3]), {})},
                         face=n["face_found"], prob=n["eye_closed_prob"], ear=n["ear"], closed=n["is_closed"],
                         cancel=n["is_definitely_open"], eye_w=eye_w))
        if k % 1000 == 0:
            print(k, "/", len(pick), flush=True)
    os.remove(tmp)
    for z in zips.values():
        z.close()

    out = os.path.join(ROOT, out_name)
    with open(out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    for line in report(rows):
        print(line)
    print("CSV:", out)


def _stat(rows, lab, **cond):
    rs = [r for r in rows if r["label"] == lab and all(str(r.get(k) or '') == str(v) for k, v in cond.items())]
    face = [r for r in rs if str(r["face"]) == "True" and r["prob"] not in ("", None)]
    n = len(face)
    return dict(n=len(rs), face_rate=round(n / len(rs), 4) if rs else None,
                closed_rate=round(sum(str(r["closed"]) == "True" for r in face) / n, 4) if n else None,
                cancel_rate=round(sum(str(r["cancel"]) == "True" for r in face) / n, 4) if n else None)


def report(rows):
    yield "== 라벨별 (얼굴 찾은 사진 기준) =="
    for lab in ("open", "half", "closed"):
        s = _stat(rows, lab)
        yield f"{lab:<7} n={s['n']:5d}  얼굴 {s['face_rate']:.1%} | 감음 판정 {s['closed_rate']:.1%} | 서버 취소(확실히 뜸) {s['cancel_rate']:.1%}"
    for g in ("dist", "glasses", "view"):
        for v in sorted({str(r.get(g) or '') for r in rows}):  # meta.xml 이 없는 사람은 빈칸
            for lab in ("open", "closed"):
                s = _stat(rows, lab, **{g: v})
                if s["closed_rate"] is not None:
                    yield f"  {lab} · {g}={v:<4} n={s['n']:5d} 감음 판정 {s['closed_rate']:.1%} | 취소 {s['cancel_rate']:.1%}"


TEAM_DIRS = [r"D:\aihub173\kpi_eye\images", r"D:\aihub173\kpi_eye\images_cond"]  # 팀 사진 (KPI ①) · 조건 사진 (마스크 · 선글라스, 시연 폰 10/29)


def team(model="", tta=False):
    """팀 사진을 서버 판정 그대로 (eval 과 같은 _real → _normalize) → 묶음(밝은 곳 · 어두운 곳 · 고개 · 마스크 · 선글라스) × 라벨 요약
    결과 CSV 는 팀 사진 폴더 옆에만 (저장소 X). 팀 사진은 시험에만 — 기준값 · 모델 고르기를 여러 번 반복하지 않는다"""
    sys.path.insert(0, API_DIR)
    os.chdir(API_DIR)
    from services import face_service as fs
    suffix = use_model(fs, model, tta) if model or tta else os.path.splitext(os.path.basename(fs.CNN_MODEL_PATH))[0]
    import tempfile
    rows, tmp = [], os.path.join(tempfile.gettempdir(), "team_eval.png")
    for d in TEAM_DIRS:
        for f in sorted(os.listdir(d)):
            if not f.lower().endswith((".jpg", ".png")):
                continue
            n, eye_w = _judge(fs, fs._read_image_bgr(os.path.join(d, f)), tmp)  # 서버와 같은 읽기
            tag = next((t for t in ("mask", "sun", "turn", "down") if f"_{t}_" in f), "")
            group = {"mask": "마스크", "sun": "선글라스", "turn": "고개", "down": "고개"}.get(tag, "밝은 곳" if "_bright_" in f else "어두운 곳")
            rows.append(dict(file=f, group=group, cond=tag, label=fs._label_of(f), face=n["face_found"], prob=n["eye_closed_prob"], ear=n["ear"],
                             closed=n["is_closed"], cancel=n["is_definitely_open"], eye_w=eye_w))  # cond: 고개는 turn(돌림) · down(숙임) 따로
    os.remove(tmp)
    out = os.path.join(os.path.dirname(TEAM_DIRS[0]), f"team_{suffix}.csv")
    with open(out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"== 팀 사진 ({suffix}) — 감음 판정 / 서버 취소(확실히 뜸), 얼굴 · CNN 값 있는 사진 기준 ==")
    for g in ("밝은 곳", "어두운 곳", "고개", "마스크", "선글라스"):
        line = []
        for lab in ("open", "half", "closed"):
            rs = [r for r in rows if r["group"] == g and r["label"] == lab and r["face"] and r["prob"] is not None]
            if rs:
                line.append(f"{lab} {sum(r['closed'] for r in rs)}/{len(rs)} 감음 · 취소 {sum(r['cancel'] for r in rs)}")
        print(f"  {g:<5} " + " | ".join(line))
    print("CSV:", out)


def extra(folder, model="", tta=False, pad=0.4, scale=1.0):
    """학습 · 기준값 고르기에 한 번도 안 쓴 외부 얼굴 사진 시험 (예: CEW) — 하위 폴더 이름에 closed / open 이 들어 있으면 그게 라벨
    얼굴이 사진에 꽉 찬 데이터라 사방을 pad 비율만큼 가장자리 색으로 늘려 MediaPipe 에 넣음 (두 라벨 똑같이). 결과 CSV 는 그 폴더 옆에만"""
    import tempfile
    import cv2
    import numpy as np
    sys.path.insert(0, API_DIR)
    os.chdir(API_DIR)
    from services import face_service as fs
    suffix = use_model(fs, model, tta) if model or tta else os.path.splitext(os.path.basename(fs.CNN_MODEL_PATH))[0]
    rows, tmp = [], os.path.join(tempfile.gettempdir(), "extra_eval.png")
    for sub in sorted(os.listdir(folder)):
        lab = next((l for l in ("closed", "open") if l in sub.lower()), "")
        if not lab or not os.path.isdir(os.path.join(folder, sub)):
            continue
        for f in sorted(os.listdir(os.path.join(folder, sub))):
            if not f.lower().endswith((".jpg", ".png")):
                continue
            img = cv2.imdecode(np.fromfile(os.path.join(folder, sub, f), np.uint8), cv2.IMREAD_COLOR)
            if img is None:
                continue
            b = int(max(img.shape[:2]) * pad)
            if b:
                img = cv2.copyMakeBorder(img, b, b, b, b, cv2.BORDER_REPLICATE)
            n, eye_w = _judge(fs, img, tmp, scale)
            rows.append(dict(file=f"{sub}/{f}", label=lab, face=n["face_found"], prob=n["eye_closed_prob"], ear=n["ear"],
                             closed=n["is_closed"], cancel=n["is_definitely_open"], eye_w=eye_w))
    os.remove(tmp)
    suffix += f"_s{scale:g}" if scale != 1.0 else ""
    out = os.path.join(os.path.dirname(os.path.abspath(folder)), f"extra_{os.path.basename(os.path.abspath(folder))}_{suffix}.csv")
    with open(out, "w", newline="", encoding="utf-8-sig") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)
    print(f"== 외부 사진 {folder} ({suffix}) ==")
    rate = {}
    for lab in ("open", "closed"):
        rs = [r for r in rows if r["label"] == lab]
        ok = [r for r in rs if r["face"] and r["prob"] is not None]
        rate[lab] = sum(r["closed"] for r in ok) / max(len(ok), 1)
        print(f"  {lab:<6} {len(rs)}장 · 얼굴 · CNN {len(ok)} ({len(ok) / max(len(rs), 1):.1%}) · 감음 판정 {rate[lab]:.1%} · 서버 취소 {sum(r['cancel'] for r in ok) / max(len(ok), 1):.1%}"
              f" · EAR < 기준 {sum(r['ear'] < fs.EAR_THRESHOLD for r in ok) / max(len(ok), 1):.1%}")
    if all(any(r["label"] == l for r in rows) for l in ("open", "closed")):
        print(f"  CNN 균형 정확도 (기준 {fs.CNN_CLOSED_PROB}) = {(1 - rate['open'] + rate['closed']) / 2:.1%}")
        for th in (0.2, 0.3, 0.4, 0.5, 0.6):
            o = [r["prob"] >= th for r in rows if r["label"] == "open" and r["face"] and r["prob"] is not None]
            c = [r["prob"] >= th for r in rows if r["label"] == "closed" and r["face"] and r["prob"] is not None]
            print(f"    기준 {th}: 뜬 눈 → 감음 {sum(o) / len(o):.1%} · 감은 눈 → 감음 {sum(c) / len(c):.1%} · 균형 {(1 - sum(o) / len(o) + sum(c) / len(c)) / 2:.1%}")
    if rows[0]["file"].split("/")[-1].startswith("NIA22EYE"):  # 71421: 이름 = …_사람_T_S_기기_rgb_상태_자세_… → 나눠 보기
        for k, (pos, names) in {"사람": (2, None), "기기": (5, {"S": "스마트폰", "T": "태블릿", "L": "노트북", "V": "차량 LCD", "M": "모니터"}),
                                "상태": (7, {"F": "집중", "S": "졸림", "D": "집중결핍", "A": "집중하락", "N": "태만"})}.items():
            line = []
            for v in sorted({r["file"].split("/")[-1].split("_")[pos] for r in rows}):
                g = [r for r in rows if r["file"].split("/")[-1].split("_")[pos] == v and r["face"] and r["prob"] is not None]
                o = [r["closed"] for r in g if r["label"] == "open"]
                c = [r["closed"] for r in g if r["label"] == "closed"]
                line.append(f"{(names or {}).get(v, v)} 감음 {sum(c)}/{len(c)} · 뜬눈오판 {sum(o)}/{len(o)}")
            print(f"  {k}: " + " | ".join(line))
    print("CSV:", out)


def wrong(csv_name, n=48):
    """eval 결과 CSV → 틀린 사진(감은 눈을 뜸으로 · 뜬 눈을 감음으로, 확신하고 틀린 것부터)의 **눈만** 모은 그림 (저장소 밖에만)
    사진은 zip 에서 한 장씩 꺼내 서버와 같은 MediaPipe · crop_eye 로 두 눈만 자름 (얼굴 전체는 저장하지 않음)"""
    import cv2
    import numpy as np
    sys.path.insert(0, os.path.join(API_DIR, "services"))
    rows = list(csv.DictReader(open(os.path.join(ROOT, csv_name), encoding="utf-8-sig")))
    which = next(k for k, v in EVAL_SETS.items() if csv_name.startswith(v[4][:-4]))
    rs = [r for r in rows if str(r["face"]) == "True" and r["prob"] not in ("", None) and r["label"] in ("open", "closed")
          and (str(r["closed"]) == "True") != (r["label"] == "closed")]
    rs.sort(key=lambda r: -abs(float(r["prob"]) - 0.4))
    print(f"틀린 사진 {len(rs)}장 (감은 눈 → 뜸 {sum(r['label'] == 'closed' for r in rs)} · 뜬 눈 → 감음 {sum(r['label'] == 'open' for r in rs)}) — 그림은 {min(n, len(rs))}장")
    items = {}
    for pattern in EVAL_SETS[which][2]:
        z = zipfile.ZipFile(find(pattern))
        for i in z.infolist():
            if "/RGB/" in zname(i):
                items[os.path.basename(zname(i))] = (z, i)
    _init(os.path.join(API_DIR, "ml_models", "face_landmarker.task"), color=True)
    tiles = []
    for r in rs[:n]:
        z, i = items[r["file"]]
        eyes = crop_bytes(z.read(i)) or []
        t = np.hstack([e[1] for e in eyes][:2] or [np.zeros((STORE, STORE, 3), np.uint8)])
        t = cv2.copyMakeBorder(cv2.resize(t, (STORE * 2, STORE)), 18, 0, 0, 0, cv2.BORDER_CONSTANT, value=(255, 255, 255))
        cv2.putText(t, f"{r['label']} p={float(r['prob']):.2f} {r['dist']} {r['view']} {'G' if r.get('glasses') == 'yes' else ''}", (2, 13), 0, 0.4, (0, 0, 200), 1)
        tiles.append(t)
    while len(tiles) % 6:
        tiles.append(np.full_like(tiles[0], 255))
    sheet = np.vstack([np.hstack(tiles[k:k + 6]) for k in range(0, len(tiles), 6)])
    out = os.path.join(ROOT, f"wrong_{os.path.splitext(csv_name)[0]}.png")
    cv2.imencode(".png", sheet)[1].tofile(out)
    print("그림:", out, "(AI-Hub 사진 — 저장소 · 단톡 X)")


def _wilson(k, n, z=1.96):
    """비율 k/n 의 95% 범위 (Wilson) — 사진 수가 적거나 0% 근처여도 범위가 0~1 안"""
    if not n:
        return None, None
    p, d = k / n, 1 + z * z / n
    c, h = (p + z * z / (2 * n)) / d, z * (p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5 / d
    return max(c - h, 0.0), min(c + h, 1.0)


def _judge_at(r, t, ear_thr, ear_margin, open_margin):
    """eval CSV 한 줄 → 기준값 t 일 때 서버 판정 (face_service 의 CNN 규칙 그대로) — (감음, 취소)"""
    p, e = float(r["prob"]), float(r["ear"])
    return p >= t, p < t - open_margin and e >= ear_thr + ear_margin


def curve(csv_names, fa_fix=(0.005, 0.01, 0.03)):
    """중간 점검 피드백 (11/04): 기준값 0.05~0.95 를 바꿔 가며 (뜬 눈 오경보율, 반쯤 감은 눈 취소율) 곡선 — 모델 여러 개를 한 그림에
    eval 결과 CSV (사진마다 감음 확률 · EAR) 로 다시 계산만 함 (사진을 다시 안 돌림). 곡선이 아래(같은 오경보에서 취소가 적음)면 개선
    숫자 = 오경보를 fa_fix 마다 고정 (그 이하가 되는 가장 낮은 기준값) → 반쯤 · 감은 눈 취소율 + 지금 기준값(config) 에서 고정 보고 형식
    ⚠️ 기준값 ≤ 확실히 뜸 여유(0.1) 이면 취소가 아예 안 생겨 곡선이 0 으로 떨어짐 (규칙 탓, 모델 실력 아님)"""
    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    sys.path.insert(0, API_DIR)
    import config
    ear_thr, ear_margin = config.EAR_THRESHOLD, config.CONFIRM_OPEN_MARGIN
    open_margin, now = getattr(config, "CNN_OPEN_MARGIN", 0.1), config.CNN_CLOSED_PROB  # 기본값은 face_service 와 같게
    ts = [round(0.05 + 0.01 * k, 2) for k in range(91)]
    plt.rcParams["font.family"] = "Malgun Gothic"
    # 오른쪽 = 감은 눈 취소율: 반쯤만 보면 기준값을 낮춘 옛 모델이 좋아 보이는데, 그때 감은 눈을 취소하는지 같이 봐야 함
    fig, (ax, ax2) = plt.subplots(1, 2, figsize=(11, 4.8))
    for name in csv_names:
        rows = list(csv.DictReader(open(os.path.join(ROOT, name), encoding="utf-8-sig")))
        by = {lab: [r for r in rows if r["label"] == lab] for lab in ("open", "half", "closed")}
        ok = {lab: [r for r in rs if str(r["face"]) == "True" and r["prob"] not in ("", None)] for lab, rs in by.items()}
        pts = []
        for t in ts:
            fa, hc, cc = (sum(_judge_at(r, t, ear_thr, ear_margin, open_margin)[i] for r in ok[lab]) / len(ok[lab])
                          for lab, i in (("open", 0), ("half", 1), ("closed", 1)))
            pts.append((t, fa, hc, cc))
        label = os.path.splitext(name)[0]
        line, = ax.plot([p[1] * 100 for p in pts], [p[2] * 100 for p in pts], marker=".", ms=3, label=label)
        ax2.plot([p[1] * 100 for p in pts], [p[3] * 100 for p in pts], marker=".", ms=3, color=line.get_color(), label=label)
        cur = min(pts, key=lambda p: abs(p[0] - now))
        ax.plot(cur[1] * 100, cur[2] * 100, "o", ms=8, mfc="none", color=line.get_color())
        ax2.plot(cur[1] * 100, cur[3] * 100, "o", ms=8, mfc="none", color=line.get_color())
        print(f"\n== {name} ==")
        for f in fa_fix:
            # t 가 오를수록 오경보 ↓ · 취소 ↑ → 오경보 f 이하인 가장 낮은 t. 취소가 생기는 t (> 여유) 만
            fix = next((p for p in pts if p[1] <= f and p[0] > open_margin + 1e-9), None)
            if fix:
                print(f"오경보 {f:.1%} 이하 → 기준값 {fix[0]:.2f}: 오경보 {fix[1]:.2%} · 반쯤 취소 {fix[2]:.1%} · 감은 눈 취소 {fix[3]:.1%}")
        print(f"[기준값 {now} (지금 config) · EAR {ear_thr} + {ear_margin} · 확실히 뜸 {now - open_margin:.2f} 미만]")
        print("묶음     | 전체 | 판정됨 | 판정 불가(얼굴 없음) | 해당 | 비율 | 95% 범위")
        for lab, what, idx in (("open", "오경보(감음 판정)", 0), ("half", "취소(확실히 뜸)", 1), ("closed", "취소(확실히 뜸)", 1)):
            k = sum(_judge_at(r, now, ear_thr, ear_margin, open_margin)[idx] for r in ok[lab])
            n = len(ok[lab])
            lo, hi = _wilson(k, n)
            print(f"{lab:<6} {what} | {len(by[lab])} | {n} | {len(by[lab]) - n} | {k} | {k / n:.1%} | {lo:.1%} ~ {hi:.1%}")
    for a, what in ((ax, "반쯤 감은 눈"), (ax2, "감은 눈")):
        for f in fa_fix:
            a.axvline(f * 100, color="gray", ls=":", lw=1)
        a.set_xlabel("뜬 눈 오경보율 (%) — 뜬 눈을 감음으로")
        a.set_ylabel(f"{what} 취소율 (%) — 확실히 뜸으로 경고 취소")
        a.set_title(f"{what} · 아래일수록 좋음")
        a.grid(alpha=0.3)
        a.legend(fontsize=8)
    fig.suptitle(f"Validation 151명 · 기준값 0.05~0.95 (동그라미 = 지금 {now})")
    out = os.path.join(ROOT, "curve_" + "_vs_".join(os.path.splitext(n)[0] for n in csv_names) + ".png")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print("\n그림:", out, "(숫자만 들어 있음 — 노션 · 발표 OK)")


def load_rows():
    return list(csv.DictReader(open(os.path.join(ROOT, "result_g1.csv"), encoding="utf-8-sig")))


# ── crop (추가 학습용) ───────────────────────────
def person_of(fname):
    """NIA_EYE_G1_526_30_RGB_F_0001.jpg → 'G1_526' (번호는 그룹마다 따로라 그룹을 붙임)"""
    p = fname.split("_")
    return f"{p[2]}_{p[3]}"


def eye_labels(zips):
    """라벨 zip 들 → {사진 이름: [(status, 중심 x, 중심 y, 폭), …]} (RGB 눈꺼풀 다각형만)"""
    out = {}
    for path in zips:
        with zipfile.ZipFile(path) as z:
            for i in z.infolist():
                if not zname(i).endswith("_RGB.xml"):
                    continue
                for im in ET.fromstring(z.read(i)).iter("image"):
                    eyes = []
                    for pg in im.iter("polygon"):
                        if not pg.get("label", "").endswith("eyelid"):
                            continue
                        pts = [tuple(map(float, xy.split(","))) for xy in pg.get("points").split(";") if xy.strip()]
                        xs, ys = [p[0] for p in pts], [p[1] for p in pts]
                        st = ([t.text for t in pg.iter("attribute") if t.get("name") == "status"] or ["open"])[0]
                        eyes.append((st, sum(xs) / len(xs), sum(ys) / len(ys), max(xs) - min(xs)))
                    out[im.get("name")] = eyes
    return out


def val_people(vl_zip):
    """Validation 라벨에 나오는 사람 전부 (학습에서 뺄 사람)"""
    with zipfile.ZipFile(vl_zip) as z:
        return {person_of(os.path.basename(zname(i))) for i in z.infolist() if zname(i).endswith("_RGB.xml")}


_det = None
_color = False  # crop --color: 흑백으로 바꾸지 않고 BGR 그대로 저장 (eye_cnn.ipynb 8번 색온도 증강용)


def _init(face_task, color=False):
    global _det, _color
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision
    _det = vision.FaceLandmarker.create_from_options(vision.FaceLandmarkerOptions(
        base_options=mp_python.BaseOptions(model_asset_path=face_task), num_faces=1))
    _color = color


def crop_bytes(data):
    """jpg bytes → [('L' | 'R', 96×96 흑백(--color 면 BGR) 눈, 눈 중심 x, y), …] (L = 사진 왼쪽 눈) / 얼굴 없음 → None. 서버 face_service 와 같은 눈 점 · crop_eye"""
    import cv2
    import mediapipe as mp
    import numpy as np
    from eye_preprocess import crop_eye
    bgr = cv2.imdecode(np.frombuffer(data, np.uint8), cv2.IMREAD_COLOR)
    if bgr is None:
        return None
    h, w = bgr.shape[:2]
    res = _det.detect(mp.Image(image_format=mp.ImageFormat.SRGB, data=cv2.cvtColor(bgr, cv2.COLOR_BGR2RGB)))
    if not res.face_landmarks:
        return None
    lm, out = res.face_landmarks[0], []
    for side, idx in (("L", [33, 160, 158, 133, 153, 144]), ("R", [362, 385, 387, 263, 373, 380])):  # face_service LEFT_EYE · RIGHT_EYE
        pts = [(lm[i].x * w, lm[i].y * h) for i in idx]
        eye = crop_eye(bgr, pts)
        if eye is None:
            continue
        if not _color:
            eye = cv2.cvtColor(eye, cv2.COLOR_BGR2GRAY)
        interp = cv2.INTER_AREA if min(eye.shape[:2]) >= STORE else cv2.INTER_LINEAR  # [:2]: 컬러면 채널 3 이 끼어 늘 LINEAR 가 됐음
        out.append((side, cv2.resize(eye, (STORE, STORE), interpolation=interp), (pts[0][0] + pts[3][0]) / 2, (pts[0][1] + pts[3][1]) / 2))
    return out


def crop(limit=0, color=False):
    import hashlib
    import json
    from multiprocessing import Pool
    import numpy as np
    sys.path.insert(0, os.path.join(API_DIR, "services"))  # eye_preprocess (서버와 같은 파일)

    face_task = os.path.join(API_DIR, "ml_models", "face_landmarker.task")
    labels = eye_labels([find("TL.zip")])
    drop = val_people(find("VL.zip"))
    ts_zips = sorted({h for d in data_dirs() for h in glob.glob(os.path.join(d, "**", "TS_*.[zZ]ip"), recursive=True)
                      if os.path.getsize(h) > 0})
    if not ts_zips:
        raise SystemExit("학습 사진 zip (TS_*.zip) 이 없습니다 — download 먼저")
    meta, items = {}, {}  # (zip, 번호) → 나이 · 성별 · 안경 (번호는 그룹 = zip 마다 따로) / 사진 이름 → (zip 경로, zip 안 이름)
    for zp in ts_zips:
        with zipfile.ZipFile(zp) as z:
            for i in z.infolist():
                n = zname(i)
                if n.endswith("meta.xml"):
                    t = ET.fromstring(z.read(i))
                    meta[(zp, t.findtext("id"))] = dict(age=t.findtext("age"), gender=t.findtext("gender"), glasses=t.findtext("glasses"))
                elif "/RGB/" in n and n.endswith(".jpg"):
                    items[os.path.basename(n)] = (zp, i.filename)

    # 사람 단위 train / val (Validation 사람은 뺀 뒤)
    #   한 번 정한 분할은 people_split.json 에 고정 — 묶음을 더 받아도 예전 사람은 그대로 (학습한 사람이 val 로 넘어가지 않게),
    #   새 사람만 따로 VAL_FRAC 만큼 val
    people = sorted({person_of(f) for f in items if f in labels} - drop)
    rng = random.Random(SEED)
    split_path = os.path.join(ROOT, "people_split.json")
    fixed = json.load(open(split_path, encoding="utf-8")) if os.path.exists(split_path) else {}
    new = [p for p in people if p not in fixed]
    val_set = {p for p in people if fixed.get(p) == "val"} | set(rng.sample(new, round(len(new) * VAL_FRAC)))
    if not limit:
        fixed.update({p: "val" if p in val_set else "train" for p in new})
        json.dump(fixed, open(split_path, "w", encoding="utf-8"), ensure_ascii=False, indent=0)
    print(f"분할: 예전 사람 {len(people) - len(new)} (고정) · 새 사람 {len(new)}", flush=True)
    # 사진 고르기: 감음 · 반쯤 전부 + 사람 · 거리마다 뜸 OPEN_PER_TRAIN 장
    opens, pick = collections.defaultdict(list), []
    for f in sorted(items):
        if f not in labels or person_of(f) in drop:
            continue
        if all(e[0] == "open" for e in labels[f]):
            opens[(person_of(f), f.split("_")[4])].append(f)
        else:
            pick.append(f)
    for k in sorted(opens):
        pick += rng.sample(opens[k], min(OPEN_PER_TRAIN, len(opens[k])))
    pick.sort()
    if limit:
        pick = sorted(random.Random(SEED).sample(pick, min(limit, len(pick))))
    print(f"학습 zip {len(ts_zips)}개 · 라벨 사진 {len(labels)} · RGB 사진 {len(items)} · Validation 이라 뺀 사람 {len(drop)}"
          f" · 남은 사람 {len(people)} (val {len(val_set)}) · 쓸 사진 {len(pick)}", flush=True)

    out_dir = os.path.join(ROOT, ("eye_npz_test" if limit else "eye_npz") + ("_color" if color else ""))
    os.makedirs(out_dir, exist_ok=True)
    made, t0, zf = [], time.time(), {}
    with Pool(max(os.cpu_count() - 1, 1), initializer=_init, initargs=(face_task, color)) as pool:
        for ci in range(0, len(pick), CHUNK):
            part = pick[ci:ci + CHUNK]
            name = f"crops_{hashlib.md5(('|'.join(part) + f'{STORE}{MATCH}{VAL_FRAC}').encode()).hexdigest()[:10]}.npz"
            made.append(name)
            if os.path.exists(os.path.join(out_dir, name)):
                continue
            datas = []
            for f in part:
                zp, inner = items[f]
                if zp not in zf:
                    zf[zp] = zipfile.ZipFile(zp)
                datas.append(zf[zp].read(inner))
            res = pool.map(crop_bytes, datas, chunksize=16)
            cols, cnt = collections.defaultdict(list), collections.Counter(files=len(part))
            for f, r in zip(part, res):
                if r is None:
                    cnt["noface"] += 1
                    continue
                for side, eye, cx, cy in r:
                    near = min(labels[f], key=lambda e: (e[1] - cx) ** 2 + (e[2] - cy) ** 2, default=None)
                    if near is None or ((near[1] - cx) ** 2 + (near[2] - cy) ** 2) ** 0.5 > near[3] * MATCH:
                        cnt["no_match"] += 1
                        continue
                    pid, m = person_of(f), meta.get((items[f][0], f.split("_")[3]), {})
                    cnt[f"eyes_{near[0]}"] += 1
                    cols["X"].append(eye)
                    cols["fname"].append(f)
                    cols["side"].append(side)
                    cols["y"].append(Y_OF.get(near[0], 0))
                    cols["status"].append(near[0])
                    cols["driver"].append(pid)
                    cols["split"].append("val" if pid in val_set else "train")
                    cols["dist"].append(f.split("_")[4])
                    cols["view"].append(f.split("_")[6])
                    cols["glasses"].append(m.get("glasses") == "yes")
                    cols["gender"].append(m.get("gender", ""))
                    cols["age"].append(int(m["age"]) // 10 * 10 if m.get("age", "").isdigit() else -1)
            np.savez_compressed(os.path.join(out_dir, name), X=np.stack(cols["X"]),
                                **{k: np.array(v) for k, v in cols.items() if k != "X"}, counts=json.dumps(cnt))
            print(f"{ci + len(part)}/{len(pick)}장  {time.time() - t0:.0f}초  {dict(cnt)}", flush=True)
    for z in zf.values():
        z.close()

    for p in glob.glob(os.path.join(out_dir, "crops_*.npz")):  # 이번 설정과 다른 묶음은 지운다 (드라이브에 섞이지 않게)
        if os.path.basename(p) not in made:
            os.remove(p)
    total = collections.Counter()
    for n in made:
        total.update(json.loads(str(np.load(os.path.join(out_dir, n))["counts"])))
    summary = dict(made=time.strftime("%Y-%m-%d %H:%M"), ts_zips=[os.path.basename(z) for z in ts_zips], store=STORE, color=color,
                   open_per_train=OPEN_PER_TRAIN, val_frac=VAL_FRAC, match=MATCH, seed=SEED, dropped_val_people=len(drop),
                   people=len(people), val_people=len(val_set), chunks=made, counts=dict(total))
    json.dump(summary, open(os.path.join(out_dir, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"끝: {out_dir}  {dict(total)}")


# ── wandb ────────────────────────────────────────
def to_wandb():
    import wandb

    rows = load_rows()
    face = [r for r in rows if r["face"] == "True" and r["prob"]]
    run = wandb.init(project="eye-cnn", name="b_eval548_g1", id="b_eval548_g1", group="eval", job_type="eval", resume="allow",
                     config=dict(data="AI-Hub 548 안구 움직임 Validation G1 RGB", people=65, model="eye_cnn_aihub.pt",
                                 cnn_closed_prob=0.4, cnn_open_margin=0.1, ear_threshold=0.23, confirm_open_margin=0.03,
                                 pick="감음 · 반쯤 감음 전부 + 사람 · 거리마다 뜸 25장 (시드 0)",
                                 label_rule="두 눈 closed = closed, 하나라도 half · closed = half", judge="서버 face_service 그대로"))
    table = wandb.Table(columns=["group", "value", "label", "n", "face_rate", "closed_rate", "cancel_rate"])
    for lab in ("open", "half", "closed"):
        s = _stat(rows, lab)
        table.add_data("all", "all", lab, *s.values())
        for k, v in s.items():
            run.summary[f"{lab}_{k}"] = v
    for g in ("dist", "glasses", "view"):
        for v in sorted({str(r.get(g) or '') for r in rows}):  # meta.xml 이 없는 사람은 빈칸
            for lab in ("open", "half", "closed"):
                table.add_data(g, v, lab, *_stat(rows, lab, **{g: v}).values())
    sweep = wandb.Table(columns=["cnn_threshold", "open_closed_rate", "half_closed_rate", "closed_closed_rate", "balanced_acc"])
    for t in (0.4, 0.3, 0.2, 0.1, 0.05):
        def rate(lab):
            rs = [r for r in face if r["label"] == lab]
            return sum(float(r["prob"]) >= t for r in rs) / len(rs)
        sweep.add_data(t, round(rate("open"), 4), round(rate("half"), 4), round(rate("closed"), 4),
                       round((1 - rate("open") + rate("closed")) / 2, 4))
    c = [r for r in face if r["label"] == "closed"]
    run.summary["closed_ear_rate"] = round(sum(float(r["ear"]) < 0.23 for r in c) / len(c), 4)
    run.summary["closed_either_rate"] = round(sum(float(r["prob"]) >= 0.4 or float(r["ear"]) < 0.23 for r in c) / len(c), 4)
    run.summary["cnn_balanced_acc"] = round((1 - run.summary["open_closed_rate"] + run.summary["closed_closed_rate"]) / 2, 4)
    run.log({"eval548_g1_table": table, "eval548_g1_threshold": sweep})
    print(run.url)
    run.finish()


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("step", choices=["download", "eval", "wandb", "crop", "team", "wrong", "extra", "curve"])
    ap.add_argument("--dir", default=r"D:\aihub71421\sel", help="extra: 외부 사진 폴더 (하위 폴더 이름에 closed / open)")
    ap.add_argument("--pad", type=float, default=0.0, help="extra: 얼굴이 꽉 찬 사진이면 사방을 이 비율만큼 늘림 (CEW 0.4, 얼굴 전체 사진은 0)")
    ap.add_argument("--root", default=ROOT, help="받기 · 결과 폴더 (저장소 밖)")
    ap.add_argument("--keys", type=int, nargs="+", default=[55882], help="download: filekey (기본 TS_G1_1)")
    ap.add_argument("--limit", type=int, default=0, help="crop 시험용: 이만큼만 (결과는 eye_npz_test/)")
    ap.add_argument("--tta", action="store_true", help="eval · team: 눈을 좌우 반전해 한 번 더 넣고 확률 평균")
    ap.add_argument("--csv", default="result_val_eye_cnn_548.csv", help="wrong: 틀린 사진을 모을 eval 결과 CSV (ROOT 안)")
    ap.add_argument("--csvs", default="result_val.csv,result_val_eye_cnn_548.csv", help="curve: 한 그림에 겹칠 eval 결과 CSV (쉼표, ROOT 안)")
    ap.add_argument("--color", action="store_true", help="crop: 컬러(BGR)로 저장 → eye_npz_color/ (8번 색온도 증강용, 사람 분할은 같음)")
    ap.add_argument("--set", default="val_g1", choices=list(EVAL_SETS), help="eval: 시험할 묶음 (val_g1 · val · train)")
    ap.add_argument("--scale", type=float, default=1.0, help="eval · extra: 사진을 이 배율로 줄여서 (저해상도 원인 확인, 결과 이름 끝 _s배율)")
    ap.add_argument("--model", default="", help="eval · team: 다른 CNN 파일 (예: eye_cnn_548.pt, ml_models/ 안). 쉼표로 여러 개면 앙상블 (감음 확률 평균)")
    a = ap.parse_args()
    ROOT = a.root
    {"download": lambda: download(a.keys), "eval": lambda: evaluate(a.set, a.model, a.tta, a.scale), "wrong": lambda: wrong(a.csv), "wandb": to_wandb, "crop": lambda: crop(a.limit, a.color),
     "team": lambda: team(a.model, a.tta), "curve": lambda: curve(a.csvs.split(",")), "extra": lambda: extra(a.dir, a.model, a.tta, a.pad, a.scale)}[a.step]()
