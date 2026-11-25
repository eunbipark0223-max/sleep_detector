# KPI ⑦ 서버 전송량 — 연습 서버에 올라온 경고 사진 크기를 재서 30분 기준 용량을 계산
#   실행 : sleep_detector_api/venv/Scripts/python.exe docs/kpi7_measure.py   (sleep_detector 폴더에서)
import glob
import os
import statistics

from PIL import Image

PHOTO_DIR = os.path.join('sleep_detector_api', 'uploads', 'events')
BEFORE = 1800  # 1초에 1장 × 30분
AFTER = 180    # 의심 순간만 (팀 1시간 시험 360장 → 30분 환산)

files = [f for f in glob.glob(os.path.join(PHOTO_DIR, '**', '*'), recursive=True)
         if f.lower().endswith(('.jpg', '.jpeg', '.png'))]
if not files:
    raise SystemExit(f'사진이 없어요: {PHOTO_DIR}')

sizes = [os.path.getsize(f) for f in files]
dims = {}
for f in files:
    with Image.open(f) as im:
        dims[im.size] = dims.get(im.size, 0) + 1

avg_kb = statistics.mean(sizes) / 1024
print(f'사진 {len(files)}장 · 평균 {avg_kb:.1f}KB · 가장 작은 것 {min(sizes) / 1024:.1f}KB · 가장 큰 것 {max(sizes) / 1024:.1f}KB')
print('규격(가로 x 세로):', dims)
before_mb = BEFORE * avg_kb / 1024
after_mb = AFTER * avg_kb / 1024
print(f'30분 기준 : {BEFORE}장 ≈ {before_mb:.1f}MB → {AFTER}장 ≈ {after_mb:.1f}MB '
      f'· {before_mb - after_mb:.1f}MB 줄임 ({(1 - AFTER / BEFORE) * 100:.0f}%)')
