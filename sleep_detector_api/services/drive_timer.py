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
#     예) "연속 2시간 운전했습니다. 화물자동차 운수사업법 시행규칙 제22조에 따라 15분 이상 쉬어 가세요. 가까운 졸음쉼터를 확인하세요."
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

import re
import threading
import time

from config import DRIVE_LIMIT_MIN, REST_MIN, REST_GRACE_MIN

_drives = {}            # user_id → {"start", "last_ping", "rest_due_at", "overdue_sent"}
_lock = threading.Lock()
_rule_title = None      # RAG 로 한 번 찾은 휴게 규정 이름 (기사마다 다시 찾지 않음 — 무료 한도 아낌)

REST_RULE_QUERY = "운수종사자 2시간 연속 운전 후 휴게시간 규정"
FALLBACK_RULE = "운수종사자 휴게시간 규정"


def _new(now):
    return {"start": now, "last_ping": now, "rest_due_at": None, "overdue_sent": False}


def _find_rest_rule():
    """RAG(B 의 rag_service) 에서 '2시간 연속 운전 → 휴게' 조항 이름. 못 찾으면 기본 문구.

    검색 결과 맨 앞이 과로 운전 금지(도로교통법 제45조) 일 수 있어서, 내용에 '2시간' 과 '휴게/휴식' 이 있는 조항만 고르고
    우리 대상(화물차) 규정을 먼저 쓴다. 이름은 소리로 읽기 좋게 괄호 앞까지만 ('화물자동차 운수사업법 시행규칙 제22조').
    """
    global _rule_title
    if _rule_title:
        return _rule_title
    try:
        from services import rag_service
        hits = [r for r in rag_service.search_by_text(REST_RULE_QUERY, k=4)
                if "2시간" in r.get("content", "") and re.search("휴게|휴식", r.get("content", ""))]
        hits.sort(key=lambda r: "화물" not in r.get("title", ""))
        if hits:
            title = re.split(r"[(（]", hits[0]["title"])[0].strip()
            if title:
                _rule_title = title if hits[0].get("is_real") else None   # 가짜(대표 규정)는 기억하지 않고 다음에 다시 찾음
                return title
    except Exception as e:   # RAG 가 안 돼도 휴게 알림은 항상 나간다
        print(f"[drive_timer] 휴게 규정 검색 실패 → 기본 문구: {type(e).__name__} {e}")
    return FALLBACK_RULE


def _rest_message():
    hours = DRIVE_LIMIT_MIN // 60
    span = f"{hours}시간" if hours else f"{DRIVE_LIMIT_MIN}분"
    return (f"연속 {span} 운전했습니다. {_find_rest_rule()}에 따라 "
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
        rest_due, overdue = False, False
        if minutes >= DRIVE_LIMIT_MIN and d["rest_due_at"] is None:      # 휴게 알림은 한 번만
            d["rest_due_at"] = now
            rest_due = True
        elif (d["rest_due_at"] is not None and not d["overdue_sent"]
              and now - d["rest_due_at"] >= REST_GRACE_MIN * 60):        # 알림 뒤 15분 안에 안 쉼
            d["overdue_sent"] = True
            overdue = True

    message = _rest_message() if rest_due else ""   # RAG 검색은 잠금 밖에서 (다른 기사의 ping 을 막지 않게)
    return {"drive_min": minutes, "rest_due": rest_due, "rest_message": message, "rest_overdue": overdue}
