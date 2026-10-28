# ═══════════════════════════════════════════════════════════════
# tools/kpi_frames.py — KPI ① 촬영 자료 정리 (영상 → 프레임 · 사진 이름 붙이기)
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P0 (KPI ①)   |   서버 코드가 아니라 PC 에서 한 번 돌리는 도구
#
# [하는 일]
#   video : 영상(사람 × 조명마다 1개) → 구간 가운데에서 1초 간격으로 프레임 → 이름 자동 + 라벨 확인용 모아보기 그림
#           영상 구성 (촬영 약속): 녹화 시작 → LEAD 2초 대기 → open 5초 → half 5초 → closed 5초 → open → half → closed
#           구간마다 1.5 · 2.5 · 3.5초 지점 (뜨는 중 · 감는 중인 구간 경계는 뺌) → 영상 1개에 상태별 6장
#   photo : 촬영 순서대로 찍은 사진 → 이름 붙여 복사 (사람마다 bright[open 2 · half 1 · closed 2] → dark[같은 순서])
#   이름 규칙 = notebooks/kpi_eye_accuracy.ipynb · lib/tools/eye_measure_main.dart 와 같음
#       p1_bright_closed_v03.jpg (영상 프레임) · p1_dark_open_s02.jpg (사진)
#
# [실행] (sleep_detector_api 폴더, venv 켠 상태)
#   python tools/kpi_frames.py video  <영상 폴더>  images  --people p1,p2,p3,p4,p5
#   python tools/kpi_frames.py photo  <사진 폴더>  images  --people p1,p2,p3,p4,p5
#   → images/ 에 프레임 · 사진, images/_check/ 에 영상별 모아보기 그림 (라벨이 맞는지 눈으로 확인 → 틀린 사진은 지움)
#   → 서버: python services/face_service.py images
#   → 폰:  adb push images/. /sdcard/Pictures/kpi_eye/
#          adb shell content call --method scan_volume --uri content://media --arg external_primary   (갤러리에 보이게)
#
# [주의]
#   - 영상 · 사진은 촬영 시각 순서(= 삼성 카메라 파일 이름 순서)로 사람 · 조명을 붙인다
#       → 찍는 순서를 지킬 것: p1 bright → p1 dark → p2 bright → …  (다시 찍은 실패 영상 · 사진은 바로 지우기)
#   - 폰 영상은 옆으로 누운 채 저장되고 회전 정보만 붙는 경우가 많음 → OpenCV 가 회전 정보대로 세움 (--rotate 로 직접 지정 가능)
#   - 얼굴 사진 · 결과는 GitHub 에 올리지 않는다 (images/ 는 gitignore) — Google Drive 에만
# ═══════════════════════════════════════════════════════════════
import argparse
import os
import shutil
import sys

import cv2
import numpy as np

LEAD_SEC = 2.0
SEGMENT_SEC = 5.0
SEGMENTS = ["open", "half", "closed", "open", "half", "closed"]
PICK_AT = (1.5, 2.5, 3.5)            # 구간 시작에서 몇 초 지점을 뽑나 (경계 1초 · 1.5초는 버림)
PHOTO_ORDER = [("open", 2), ("half", 1), ("closed", 2)]   # 조명 하나당 촬영 순서
LIGHTS = ["bright", "dark"]
VIDEO_EXT = (".mp4", ".mov", ".3gp", ".mkv")
PHOTO_EXT = (".jpg", ".jpeg", ".png", ".heic")
ROTATE = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE}


def _files(folder, exts):
    if not os.path.isdir(folder):
        sys.exit(f"폴더가 없습니다: {folder}")
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(exts))


def _slots(people):
    """촬영 순서 = 사람마다 bright → dark"""
    return [(p, light) for p in people for light in LIGHTS]


def _check_count(files, slots, what):
    if len(files) != len(slots):
        print(f"❌ {what} {len(files)}개인데 {len(slots)}개가 필요합니다 (사람 {len(slots) // len(LIGHTS)}명 × {LIGHTS}).")
        print("   촬영 순서대로 짝지은 결과 (남거나 모자라는 쪽 확인):")
        for i in range(max(len(files), len(slots))):
            f = files[i] if i < len(files) else "(없음)"
            s = "_".join(slots[i]) if i < len(slots) else "(남음)"
            print(f"   {i + 1:3d}. {f}  →  {s}")
        sys.exit(1)


def _read_at(cap, sec, rotate):
    cap.set(cv2.CAP_PROP_POS_MSEC, sec * 1000)
    ok, frame = cap.read()
    if not ok:
        return None
    return cv2.rotate(frame, ROTATE[rotate]) if rotate in ROTATE else frame


def _imwrite(path, img):
    ok, buf = cv2.imencode(os.path.splitext(path)[1] or ".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 95])
    if ok:
        buf.tofile(path)  # 한글 경로에서도 저장되게
    return ok


def _contact_sheet(items, path, cols=6, size=200):
    """뽑은 프레임 모아보기 — 그림마다 상태 · 시각 표시 (라벨이 맞는지 눈으로 확인)"""
    tiles = []
    for img, text in items:
        h, w = img.shape[:2]
        s = size / max(h, w)
        t = cv2.resize(img, (int(w * s), int(h * s)))
        tile = np.full((size + 24, size, 3), 255, np.uint8)
        tile[: t.shape[0], : t.shape[1]] = t
        cv2.putText(tile, text, (4, size + 17), cv2.FONT_HERSHEY_SIMPLEX, 0.45, (0, 0, 200), 1, cv2.LINE_AA)
        tiles.append(tile)
    while len(tiles) % cols:
        tiles.append(np.full_like(tiles[0], 255))
    rows = [np.hstack(tiles[i: i + cols]) for i in range(0, len(tiles), cols)]
    _imwrite(path, np.vstack(rows))


def run_video(src, dst, people, rotate):
    files = _files(src, VIDEO_EXT)
    slots = _slots(people)
    _check_count(files, slots, "영상")
    os.makedirs(os.path.join(dst, "_check"), exist_ok=True)
    need = LEAD_SEC + SEGMENT_SEC * len(SEGMENTS)
    total = 0
    for f, (person, light) in zip(files, slots):
        cap = cv2.VideoCapture(os.path.join(src, f))
        if not cap.isOpened():
            sys.exit(f"영상을 열 수 없습니다: {f}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        length = cap.get(cv2.CAP_PROP_FRAME_COUNT) / fps
        meta = int(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0)
        if rotate is None:  # OpenCV 가 회전 정보대로 세움 (CAP_PROP_ORIENTATION_AUTO 기본 켬)
            rot = 0
        else:
            cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 0)
            rot = rotate
        if length + 0.5 < need:
            print(f"⚠️ {f}: {length:.1f}초 — 약속({need:.0f}초)보다 짧음, 있는 구간만 뽑음")
        count, sheet = {}, []
        for k, state in enumerate(SEGMENTS):
            for at in PICK_AT:
                sec = LEAD_SEC + k * SEGMENT_SEC + at
                if sec >= length:
                    continue
                frame = _read_at(cap, sec, rot)
                if frame is None:
                    continue
                count[state] = count.get(state, 0) + 1
                name = f"{person}_{light}_{state}_v{count[state]:02d}.jpg"
                _imwrite(os.path.join(dst, name), frame)
                sheet.append((frame, f"{state} {sec:.1f}s"))
        cap.release()
        if sheet:
            _contact_sheet(sheet, os.path.join(dst, "_check", f"{person}_{light}.jpg"))
        h, w = sheet[0][0].shape[:2] if sheet else (0, 0)
        print(f"✅ {f} → {person}_{light}: {sum(count.values())}장 {count} · {w}×{h} · {length:.1f}초 · 회전정보 {meta}°")
        total += sum(count.values())
    print(f"\n🎉 프레임 {total}장 → {dst}   라벨 확인: {os.path.join(dst, '_check')} (틀린 프레임은 images/ 에서 지우기)")


def run_photo(src, dst, people):
    files = _files(src, PHOTO_EXT)
    per_light = sum(n for _, n in PHOTO_ORDER)
    slots = [(p, light, state) for p, light in _slots(people) for state, n in PHOTO_ORDER for _ in range(n)]
    if len(files) != len(slots):
        print(f"❌ 사진 {len(files)}장인데 {len(slots)}장이 필요합니다 (사람 {len(people)}명 × {LIGHTS} × {per_light}장 "
              f"= {PHOTO_ORDER}).")
        for i in range(max(len(files), len(slots))):
            f = files[i] if i < len(files) else "(없음)"
            s = "_".join(slots[i]) if i < len(slots) else "(남음)"
            print(f"   {i + 1:3d}. {f}  →  {s}")
        sys.exit(1)
    os.makedirs(dst, exist_ok=True)
    count = {}
    for f, (person, light, state) in zip(files, slots):
        key = (person, light, state)
        count[key] = count.get(key, 0) + 1
        ext = os.path.splitext(f)[1].lower()
        name = f"{person}_{light}_{state}_s{count[key]:02d}{'.jpg' if ext == '.jpeg' else ext}"
        shutil.copy2(os.path.join(src, f), os.path.join(dst, name))
        print(f"   {f} → {name}")
    print(f"\n🎉 사진 {len(files)}장 → {dst} (원본은 그대로)")


def main():
    ap = argparse.ArgumentParser(description="KPI ① 촬영 자료 정리")
    ap.add_argument("mode", choices=["video", "photo"])
    ap.add_argument("src", help="영상 / 사진 폴더 (촬영 시각 순서 = 파일 이름 순서)")
    ap.add_argument("dst", help="내보낼 폴더 (예: images)")
    ap.add_argument("--people", default="p1,p2,p3,p4,p5", help="촬영한 순서대로 사람 이름 (쉼표)")
    ap.add_argument("--rotate", type=int, choices=[0, 90, 180, 270], default=None,
                    help="(video) 회전을 직접 지정 — 모아보기에서 얼굴이 누워 있을 때만")
    a = ap.parse_args()
    people = [p.strip() for p in a.people.split(",") if p.strip()]
    if a.mode == "video":
        run_video(a.src, a.dst, people, a.rotate)
    else:
        run_photo(a.src, a.dst, people)


if __name__ == "__main__":
    main()
