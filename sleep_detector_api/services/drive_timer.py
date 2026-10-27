# ═══════════════════════════════════════════════════════════════
# services/drive_timer.py — 연속 운전 시간 · 휴게 알림 · 휴게 미준수
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P1
# 수업 원본: (없음, 🔴 신규)
#
# [이 파일이 하는 일]
#   - 연속 운전 시간 = /drive/start 이후 ping 이 계속 들어온 시간
#   - 휴식 인정 = [정차했어요] 후 15분, 또는 ping 이 15분 이상 안 옴 (앱을 끄고 쉰 경우) → 운전 시간 0부터
#   - 2시간이면 rest_due = true + 안내문 (RAG 규정 제목, 실패 시 고정 문구) — 한 번만
#   - 안내 뒤 15분 안에 안 쉬면 reason = rest_overdue 경고 저장 (단계는 그대로)
#
# [만들 것 (이름 약속 — detect.py 가 이 이름으로 부름)]
#   - start(user_id)                → 운행 시작 (운전 시간 0부터)
#   - ping(user_id) → {"drive_min", "rest_due", "rest_message", "rest_overdue"}
#   - rest_done(user_id)            → 15분 휴식을 마치고 [운행 재개] (운전 시간 0부터)
#   - drive_min(user_id)            → 지금까지 연속 운전 분 (음성 보고 숫자용)
#
# [주의]
#   - GPS 속도 · 정차 판단은 쓰지 않는다
#   - 기사별 기록은 서버 메모리(dict) — 서버를 다시 켜면 지워짐 (sleep_state 와 같음)
#   - 숫자는 config (DRIVE_LIMIT_MIN · REST_MIN · REST_GRACE_MIN), DEMO_MODE 면 2분 · 1분 · 1분
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

import threading
import time

from config import DRIVE_LIMIT_MIN, REST_MIN, REST_GRACE_MIN

_drives = {}            # user_id → {"start", "last_ping", "rest_due_at", "overdue_sent"}
_lock = threading.Lock()


def _new(now):
    return {"start": now, "last_ping": now, "rest_due_at": None, "overdue_sent": False}


def _rest_message():
    hours = DRIVE_LIMIT_MIN // 60
    span = f"{hours}시간" if hours else f"{DRIVE_LIMIT_MIN}분"
    return (f"연속 {span} 운전했습니다. 운수종사자 휴게시간 규정에 따라 "
            f"{REST_MIN}분 이상 쉬어 가세요. 가까운 졸음쉼터를 확인하세요.")


def start(user_id):
    with _lock:
        _drives[user_id] = _new(time.time())


def rest_done(user_id):
    """[운행 재개] — 휴식을 인정하고 운전 시간을 0부터 다시 잰다."""
    start(user_id)


def drive_min(user_id):
    with _lock:
        d = _drives.get(user_id)
        return int((time.time() - d["start"]) // 60) if d else 0


def ping(user_id):
    """30초마다. 운전 시간을 갱신하고 휴게 알림 · 휴게 미준수를 알려 준다."""
    now = time.time()
    with _lock:
        d = _drives.get(user_id)
        if d is None:                                   # /drive/start 없이 와도 시작한 것으로 본다
            d = _drives[user_id] = _new(now)
        elif now - d["last_ping"] >= REST_MIN * 60:     # ping 이 15분 이상 안 옴 = 앱을 끄고 쉼 → 휴식 인정
            d.update(_new(now))
        d["last_ping"] = now

        minutes = int((now - d["start"]) // 60)
        rest_due, message, overdue = False, "", False
        if minutes >= DRIVE_LIMIT_MIN and d["rest_due_at"] is None:      # 휴게 알림은 한 번만
            d["rest_due_at"] = now
            rest_due, message = True, _rest_message()
        elif (d["rest_due_at"] is not None and not d["overdue_sent"]
              and now - d["rest_due_at"] >= REST_GRACE_MIN * 60):        # 알림 뒤 15분 안에 안 쉼
            d["overdue_sent"] = True
            overdue = True

    return {"drive_min": minutes, "rest_due": rest_due, "rest_message": message, "rest_overdue": overdue}
