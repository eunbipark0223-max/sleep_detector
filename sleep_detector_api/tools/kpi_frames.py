# ═══════════════════════════════════════════════════════════════
# tools/kpi_frames.py — KPI ① 촬영 자료 정리 (영상 → 프레임 · 사진 이름 붙이기)
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P0 (KPI ①)   |   서버 코드가 아니라 PC 에서 한 번 돌리는 도구
#   촬영 수칙 · 이름 규칙: 노션 「팀원 사진 · 영상 촬영」 (팀장 양식)
#
# [하는 일]
#   video : 영상(사람마다 bright 1개 · dark 1개) → 구간 가운데 1초 간격 프레임 → 이름 자동 + 라벨 확인용 모아보기 그림
#           영상 구성: 녹화 시작 → 2초 대기 → open 5초 → half 5초 → closed 5초 → open → half → closed (총 32초)
#           구간마다 1.5 · 2.5 · 3.5초 지점 (뜨는 중 · 감는 중인 경계는 뺌) → 영상 1개에 open · half · closed 6장씩
#           저장 크기: 앱 카메라(ResolutionPreset.medium, 세로 480×640)와 얼굴 크기가 같게 — 자르지 않고 긴 변을 640 으로
#                      줄임 (세로 9:16 영상 → 360×640, 10/28 팀장 수정). 원본 크기 프레임은 <dst>/_full/ 에 같은 이름으로 (해상도 비교용)
#   photo : 촬영 순서대로 찍은 사진 → 이름 붙여 복사 (원본은 그대로)
#           기본 사진: 사람마다 open 10 → half 5 → closed 10 (25장) 다 찍고 다음 사람
#           조건 사진(마스크 · 선글라스 · 고개)은 조건마다 폴더를 나눠 넣고 --tag · --order · --people 로 한 번씩
#
#   이름 규칙 (notebooks/kpi_eye_accuracy.ipynb · lib/tools/eye_measure_main.dart 가 이 이름을 읽음)
#       영상 프레임  a_bright_closed_v01.jpg        사진  a_bright_open_s01.jpg
#       조건 사진    a_bright_mask_open_s01.jpg · a_bright_sun_closed_s01.jpg · a_bright_turn_open_s01.jpg
#       사람 = 팀원 a · b · c · d, 팀장 t
#
# [실행] (sleep_detector_api 폴더)
#   venv\Scripts\python tools/kpi_frames.py video <영상 폴더> images --people a,b,c,d,t
#   venv\Scripts\python tools/kpi_frames.py photo <사진 폴더> images --people a,b,c,d,t
#   venv\Scripts\python tools/kpi_frames.py photo <마스크 폴더>   images --people a,b,c,d,t --tag mask --order open:2,closed:2
#   venv\Scripts\python tools/kpi_frames.py photo <선글라스 폴더> images --people a,c     --tag sun  --order open:1,closed:1
#   venv\Scripts\python tools/kpi_frames.py photo <고개 폴더>     images --people a,b,c,d,t --tag turn --order open:2
#   → images/_check/ 영상별 모아보기 그림 (라벨이 맞는지 눈으로 확인 → 틀린 프레임은 images/ 에서 지우기)
#   → 서버: venv\Scripts\python services/face_service.py images
#   → 폰:  adb push images/. /sdcard/Pictures/kpi_eye/
#          adb shell content call --method scan_volume --uri content://media --arg external_primary   (갤러리에 보이게)
#
# [주의]
#   - 영상 · 사진은 파일 이름 순서(= 삼성 카메라의 촬영 시각 순서)로 사람 · 조명을 붙인다
#       → 찍는 순서를 지킬 것 (영상: a bright → a dark → b bright → … / 사진: a 25장 → b 25장 → …)
#       → 실패한 영상 · 사진은 촬영할 때 바로 지우기. 장수가 안 맞으면 도구가 멈추고 짝지은 표를 보여 줌
#   - 폰 영상은 옆으로 누운 채 저장되고 회전 정보만 붙는 경우가 많음 → OpenCV 가 회전 정보대로 세움 (--rotate 로 직접 지정 가능)
#   - 얼굴 사진 · 결과는 GitHub 에 올리지 않는다 (images/ · result_images/ 는 gitignore, _full · _check 도 그 안) — Google Drive 에만
#   - 원본 크기도 서버로 재 보려면: venv\Scripts\python services/face_service.py images/_full  (맨 위 폴더 파일만 읽음)
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
VIDEO_LIGHTS = ["bright", "dark"]    # 영상: 사람마다 이 순서로 1개씩
APP_LONG, APP_SHORT = 640, 480       # 앱 카메라 ResolutionPreset.medium (4:3)
DEFAULT_PHOTO_ORDER = "open:10,half:5,closed:10"
STATES = ("open", "half", "closed")
VIDEO_EXT = (".mp4", ".mov", ".3gp", ".mkv")
PHOTO_EXT = (".jpg", ".jpeg", ".png", ".heic")
ROTATE = {90: cv2.ROTATE_90_CLOCKWISE, 180: cv2.ROTATE_180, 270: cv2.ROTATE_90_COUNTERCLOCKWISE}


def _files(folder, exts):
    if not os.path.isdir(folder):
        sys.exit(f"폴더가 없습니다: {folder}")
    return sorted(f for f in os.listdir(folder) if f.lower().endswith(exts))


def _check_count(files, slots, what, need_text):
    if len(files) == len(slots):
        return
    print(f"❌ {what} {len(files)}개인데 {len(slots)}개가 필요합니다 ({need_text}).")
    print("   촬영 순서대로 짝지은 결과 (남거나 모자라는 곳 확인 → 빠진 것 다시 찍기 / 남는 것 지우기):")
    for i in range(max(len(files), len(slots))):
        f = files[i] if i < len(files) else "(없음)"
        s = "_".join(slots[i]) if i < len(slots) else "(남음)"
        print(f"   {i + 1:3d}. {f}  →  {s}")
    sys.exit(1)


def _imwrite(path, img):
    ok, buf = cv2.imencode(os.path.splitext(path)[1] or ".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, 95])
    if ok:
        buf.tofile(path)  # 한글 경로에서도 저장되게
    return ok


def to_app_size(frame):
    """앱 카메라와 같은 조건: 자르지 않고 긴 변을 640 으로 줄인다 (세로 9:16 영상 → 360×640)

    (10/28 팀장 수정) 예전에는 가운데를 3:4 로 잘랐는데, 그러면 얼굴이 앱보다 약 1.3배 크게 나온다.
      - 센서는 4:3 이고 앱(480×640)은 센서 전체를 본다
      - 9:16 영상은 센서의 양옆만 잘린 화면 → 세로 범위가 앱과 같다
      - 여기서 위아래까지 자르면 앱보다 좁게 보는 셈 → 눈이 커져서 기준값이 어긋남
      → 줄이기만 하면 얼굴이 화면에서 차지하는 크기가 앱과 같아진다 (양옆이 좁은 건 얼굴이 가운데면 영향 없음)
    """
    h, w = frame.shape[:2]
    scale = APP_LONG / max(h, w)
    size = (max(1, round(w * scale)), max(1, round(h * scale)))
    return cv2.resize(frame, size, interpolation=cv2.INTER_AREA)


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
    slots = [(p, light) for p in people for light in VIDEO_LIGHTS]
    _check_count(files, slots, "영상", f"사람 {len(people)}명 × {VIDEO_LIGHTS}")
    full = os.path.join(dst, "_full")
    for d in (dst, full, os.path.join(dst, "_check")):
        os.makedirs(d, exist_ok=True)
    need = LEAD_SEC + SEGMENT_SEC * len(SEGMENTS)
    total = 0
    for f, (person, light) in zip(files, slots):
        cap = cv2.VideoCapture(os.path.join(src, f))
        if not cap.isOpened():
            sys.exit(f"영상을 열 수 없습니다: {f}")
        fps = cap.get(cv2.CAP_PROP_FPS) or 30
        length = cap.get(cv2.CAP_PROP_FRAME_COUNT) / fps
        meta = int(cap.get(cv2.CAP_PROP_ORIENTATION_META) or 0)
        if rotate is not None:      # 직접 지정하면 OpenCV 자동 회전을 끄고 그 각도로
            cap.set(cv2.CAP_PROP_ORIENTATION_AUTO, 0)
        if length + 0.5 < need:
            print(f"⚠️ {f}: {length:.1f}초 — 약속({need:.0f}초)보다 짧음, 있는 구간만 뽑음")
        count, sheet, full_size = {}, [], None
        for k, state in enumerate(SEGMENTS):
            for at in PICK_AT:
                sec = LEAD_SEC + k * SEGMENT_SEC + at
                if sec >= length:
                    continue
                cap.set(cv2.CAP_PROP_POS_MSEC, sec * 1000)
                ok, frame = cap.read()
                if not ok:
                    continue
                if rotate in ROTATE:
                    frame = cv2.rotate(frame, ROTATE[rotate])
                full_size = frame.shape[1::-1]
                small = to_app_size(frame)
                count[state] = count.get(state, 0) + 1
                name = f"{person}_{light}_{state}_v{count[state]:02d}.jpg"
                _imwrite(os.path.join(dst, name), small)
                _imwrite(os.path.join(full, name), frame)
                sheet.append((small, f"{state} {sec:.1f}s"))
        cap.release()
        if sheet:
            _contact_sheet(sheet, os.path.join(dst, "_check", f"{person}_{light}.jpg"))
        app_size = sheet[0][0].shape[1::-1] if sheet else None
        print(f"✅ {f} → {person}_{light}: {sum(count.values())}장 {count} · 원본 {full_size} → 앱 크기 {app_size}"
              f" · {length:.1f}초 · 회전정보 {meta}°")
        total += sum(count.values())
    print(f"\n🎉 프레임 {total}장 → {dst} (앱 크기) · {full} (원본 크기)")
    print(f"   라벨 확인: {os.path.join(dst, '_check')} — 틀린 프레임은 두 폴더에서 같이 지우기")


def _parse_order(text):
    order = []
    for part in text.split(","):
        state, _, n = part.strip().partition(":")
        if state not in STATES or not n.isdigit():
            sys.exit(f"--order 형식이 틀렸습니다: {text!r} (예: open:10,half:5,closed:10)")
        order.append((state, int(n)))
    return order


def run_photo(src, dst, people, light, tag, order_text):
    files = _files(src, PHOTO_EXT)
    order = _parse_order(order_text)
    per_person = sum(n for _, n in order)
    slots = [(p, light, tag, state) if tag else (p, light, state) for p in people for state, n in order for _ in range(n)]
    _check_count(files, slots, "사진", f"사람 {len(people)}명 × {per_person}장 = {order_text}")
    os.makedirs(dst, exist_ok=True)
    count = {}
    for f, slot in zip(files, slots):
        count[slot] = count.get(slot, 0) + 1
        ext = os.path.splitext(f)[1].lower()
        name = f"{'_'.join(slot)}_s{count[slot]:02d}{'.jpg' if ext == '.jpeg' else ext}"
        if os.path.exists(os.path.join(dst, name)):
            sys.exit(f"이미 있는 이름입니다: {name} — 같은 폴더를 두 번 돌렸는지 확인")
        shutil.copy2(os.path.join(src, f), os.path.join(dst, name))
        print(f"   {f} → {name}")
    print(f"\n🎉 사진 {len(files)}장 → {dst} (원본은 그대로)")


def main():
    ap = argparse.ArgumentParser(description="KPI ① 촬영 자료 정리")
    ap.add_argument("mode", choices=["video", "photo"])
    ap.add_argument("src", help="영상 / 사진 폴더 (촬영 시각 순서 = 파일 이름 순서)")
    ap.add_argument("dst", help="내보낼 폴더 (예: images)")
    ap.add_argument("--people", default="a,b,c,d,t", help="촬영한 순서대로 사람 이름 (쉼표, 팀원 a~d · 팀장 t)")
    ap.add_argument("--rotate", type=int, choices=[0, 90, 180, 270], default=None,
                    help="(video) 회전을 직접 지정 — 모아보기에서 얼굴이 누워 있을 때만")
    ap.add_argument("--light", default="bright", choices=["bright", "dark"], help="(photo) 이름에 넣을 조명")
    ap.add_argument("--tag", default="", help="(photo) 조건 사진 — mask · sun · turn · down 등 (기본 사진은 비움)")
    ap.add_argument("--order", default=DEFAULT_PHOTO_ORDER, help=f"(photo) 한 사람의 촬영 순서 (기본 {DEFAULT_PHOTO_ORDER})")
    a = ap.parse_args()
    people = [p.strip() for p in a.people.split(",") if p.strip()]
    if a.mode == "video":
        run_video(a.src, a.dst, people, a.rotate)
    else:
        run_photo(a.src, a.dst, people, a.light, a.tag.strip().lower(), a.order)


if __name__ == "__main__":
    main()
