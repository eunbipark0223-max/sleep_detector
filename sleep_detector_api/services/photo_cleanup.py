# ═══════════════════════════════════════════════════════════════
# services/photo_cleanup.py — 졸음 확정 사진 30일 자동 삭제
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P1
# 수업 원본: (없음, 🔴 신규)
#
# [이 파일이 하는 일]
#   - 졸음 확정 사진(uploads/events/…)은 얼굴 사진이라 오래 두지 않는다 → 30일이 지난 경고의 사진 파일을 지우고
#     그 경고의 photo_path 를 비운다. 경고 기록(단계 · 요약 · 보고서)은 그대로 남고, 관리자 웹에는 "캡처 사진 없음"으로 보인다
#   - cleanup_old_photos(db)        한 번 정리 (지운 개수를 dict 로 돌려줌, dry_run=True 면 세기만)
#   - run_once()                    자기 DB 연결로 한 번 정리 (명령줄 · 예약 실행용)
#   - daily_loop()                  서버가 켜져 있는 동안 시작할 때 한 번 + 24시간마다 정리 (asyncio 작업)
#
# [서버에 붙이는 법 — main.py 는 팀장 파일이라 여기서는 안 고침. lifespan 안에 3줄]
#       import asyncio
#       from services import photo_cleanup
#       cleanup_task = asyncio.create_task(photo_cleanup.daily_loop())      # yield 앞
#       ...
#       cleanup_task.cancel()                                               # yield 뒤 ("서버 종료" 앞)
#   서버를 안 붙여도 아래처럼 직접 돌릴 수 있다 (예: 윈도우 작업 스케줄러에서 하루 한 번)
#
# [실행] (sleep_detector_api 폴더)
#   venv\Scripts\python services\photo_cleanup.py --dry-run       지울 사진 개수만 보기
#   venv\Scripts\python services\photo_cleanup.py                 30일 지난 사진 지우기
#   venv\Scripts\python services\photo_cleanup.py --days 7        기준 일수 바꾸기 (시연 · 시험용)
#
# [주의]
#   - 파일 이름만 쓴다 (photo_path 의 폴더 부분은 무시) → uploads/events/ 밖의 파일은 절대 안 건드림
#   - 파일이 이미 없어도 photo_path 는 비운다 (관리자 웹에서 깨진 사진 대신 "사진 없음"으로)
#   - 경고 기록 자체는 지우지 않는다 (통계 · 기록 유지). 프로필 사진(uploads/profiles)도 건드리지 않는다
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import argparse
import asyncio
import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # 명령줄로 돌릴 때 import 경로

import config  # noqa: E402

PHOTO_KEEP_DAYS = getattr(config, "PHOTO_KEEP_DAYS", 30)   # 사진을 두는 날짜 (config 에 PHOTO_KEEP_DAYS 가 있으면 그 값)
CLEANUP_EVERY_SEC = 24 * 60 * 60


def cleanup_old_photos(db, days=None, now=None, dry_run=False):
    """days 일이 지난 경고의 사진 파일을 지우고 photo_path 를 비운다.

    돌려주는 값: {"found": 대상 경고 수, "files_deleted": 지운 파일 수, "files_missing": 이미 없던 파일 수, "cutoff": 기준 시각}
    """
    from models.models import SleepEvent

    days = PHOTO_KEEP_DAYS if days is None else days
    now = now or datetime.now()
    cutoff = now - timedelta(days=days)
    rows = (
        db.query(SleepEvent)
        .filter(SleepEvent.photo_path.isnot(None), SleepEvent.photo_path != "", SleepEvent.created_at < cutoff)
        .all()
    )
    result = {"found": len(rows), "files_deleted": 0, "files_missing": 0, "cutoff": cutoff}
    if dry_run:
        return result

    event_dir = os.path.abspath(config.UPLOAD_EVENT_DIR)
    for row in rows:
        name = os.path.basename(str(row.photo_path).replace("\\", "/"))
        target = os.path.abspath(os.path.join(event_dir, name))
        if name and os.path.dirname(target) == event_dir and os.path.isfile(target):   # events 폴더 안의 파일만
            try:
                os.remove(target)
                result["files_deleted"] += 1
            except OSError as e:                      # 지우지 못했으면 이 경고는 그대로 두고 다음 번에 다시 시도
                print(f"⚠️ 사진 삭제 실패 (다음에 다시 시도): {name} — {e}")
                continue
        else:
            result["files_missing"] += 1
        row.photo_path = None
    db.commit()
    return result


def run_once(days=None, dry_run=False):
    """자기 DB 연결로 한 번 정리하고 결과 dict 를 돌려준다."""
    from database.db_connection import SessionLocal

    with SessionLocal() as db:
        return cleanup_old_photos(db, days=days, dry_run=dry_run)


async def daily_loop():
    """서버 시작 때 한 번, 그 뒤 24시간마다. 실패해도 서버는 계속 돈다 (다음 주기에 다시 시도)."""
    while True:
        try:
            r = await asyncio.to_thread(run_once)
            if r["found"]:
                print(f"🧹 {PHOTO_KEEP_DAYS}일 지난 사진 정리: 경고 {r['found']}건 (파일 {r['files_deleted']}개 삭제 · {r['files_missing']}개는 이미 없음)")
        except asyncio.CancelledError:
            raise
        except Exception as e:
            print(f"⚠️ 사진 정리 실패(서버는 계속 실행): {type(e).__name__}: {e}")
        await asyncio.sleep(CLEANUP_EVERY_SEC)


def main():
    ap = argparse.ArgumentParser(description="N일 지난 졸음 확정 사진 지우기")
    ap.add_argument("--days", type=int, default=PHOTO_KEEP_DAYS, help=f"기준 일수 (기본 {PHOTO_KEEP_DAYS})")
    ap.add_argument("--dry-run", action="store_true", help="지우지 않고 대상 개수만 보기")
    args = ap.parse_args()
    r = run_once(days=args.days, dry_run=args.dry_run)
    print(f"기준: {r['cutoff']:%Y-%m-%d %H:%M} 이전 ({args.days}일 지난 경고) — 대상 경고 {r['found']}건")
    if args.dry_run:
        print("[dry-run] 지우지 않았습니다.")
    else:
        print(f"파일 {r['files_deleted']}개 삭제 · {r['files_missing']}개는 이미 없어서 기록만 비움")


if __name__ == "__main__":
    main()
