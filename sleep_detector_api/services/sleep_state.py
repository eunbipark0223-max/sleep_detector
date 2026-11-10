# ═══════════════════════════════════════════════════════════════
# services/sleep_state.py — 기사별 졸음 상태 기억 (서버 메모리)  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P0
# 수업 원본: (없음, 🔴 신규 — 파이썬 dict)
#
# [이 파일이 하는 일]
#   - 10분 안 졸음 기록 → 규칙 단계 (1번=1, 2번=2, 3번 이상=3)
#   - set_stage — 지금 단계와 새 단계 중 큰 값만 저장 (올리기만, 퀴즈로 올라간 단계 유지)
#   - 1단계 10분간 졸음 없으면 0단계 / 관리자 조치완료면 reset
#   - 운행 시작(start_drive): 0 · 1단계만 0단계로. 2 · 3단계 · 10분 졸음 기록은 유지 (다시 시작으로 경고를 끌 수 없게)
#   - 개인 기준 EAR, 음성 보고용 facts (10분 졸음 횟수 · 마지막 closed_sec · 운행 분 · 단계)
#   - 휴식 시작 시각 · 운전 중 퀴즈 실패 횟수 · 마지막 퀴즈 시각 · 마지막 ping 시각
#   - 🆕 (11/10 팀장 결정) 반쯤 감은 눈: 평소 뜬 눈 EAR (출발 전 5초 측정 중간값, set_open_ear · get_open_ear) 저장
#       add_half(user_id, is_half) — 최근 4번 중 3번 반쯤이면 True (확정) → 기록 비움 (실눈이 이어져도 40초마다 단계가 오르지 않게)
#       반쯤인지는 face_service.check_half 가 정함 (평소 × 0.85 미만). 측정 실패한 사람은 평소 값 None → 반쯤 판정 안 함
#
# [주의]
#   - 연속 감김 · PERCLOS · 얼굴 없음 계산은 여기서 하지 않는다 → 앱 eye_monitor.dart
#   - 서버를 다시 켜면 메모리가 비워짐 (DB 에는 경고만 남음) — 시연 전에 서버 재시작 금지
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
from datetime import datetime, timedelta
import config

# 기사별(user_id) 메모리 저장소
_states: dict[int, dict] = {}


def _get_window_minutes() -> float:
    if getattr(config, "DEMO_MODE", False):
        return 1.0
    return float(getattr(config, "WINDOW_MIN", 10))


def _get_rest_minutes() -> float:
    if getattr(config, "DEMO_MODE", False):
        return 1.0
    return float(getattr(config, "REST_MIN", 15))


def get_state(user_id: int) -> dict:
    """기사 상태 조회 (없으면 초기화)"""
    if user_id not in _states:
        _states[user_id] = {
            "sleep_times": [],           # 최근 10분 내 졸음 발생 시각 리스트
            "stage": 0,                  # 현재 경고 단계 (0~3)
            "stage_changed_at": datetime.now(),  # 단계가 마지막으로 바뀐 시각 (1단계 자동 해제 기준)
            "last_sleep_at": None,       # 마지막 졸음 시각
            "last_closed_sec": 0.0,      # 마지막 연속 감김 시간(초)
            "personal_ear": getattr(config, "EAR_THRESHOLD", 0.20),
            "drive_started_at": datetime.now(),
            "rest_started_at": None,     # [정차했어요] 누른 시각
            "quiz_fails": 0,             # 운전 중 퀴즈 연속 실패 횟수
            "last_quiz_at": None,        # 마지막 퀴즈 출제 시각 (2분 간격 제한용)
            "last_ping_at": None,        # 마지막 ping 수신 시각
            "reset_count": 0,            # 관리자 [조치완료] 횟수 (/detect 가 AI 처리 중 해제됐는지 확인)
            "open_ear": None,            # 🆕 출발 전 측정 뜬 눈 EAR 중간값 (face_service.calibrate, 실패면 None)
            "half_recent": [],           # 🆕 최근 반쯤 확인 결과 [(시각, 반쯤 여부)]
        }
    return _states[user_id]


def _change_stage(state: dict, stage: int) -> None:
    """단계를 바꾸고 바뀐 시각을 기록 (1단계 자동 해제가 이 시각부터 10분을 셈)"""
    if state["stage"] != stage:
        state["stage"] = stage
        state["stage_changed_at"] = datetime.now()


def _prune_old_sleeps(state: dict, now: datetime) -> None:
    """10분(시연 모드 1분)이 지난 졸음 기록 제거 및 1단계 자동 해제"""
    cutoff = now - timedelta(minutes=_get_window_minutes())
    state["sleep_times"] = [t for t in state["sleep_times"] if t >= cutoff]

    # 1단계가 된 지 10분이 지났고 그동안 졸음이 없으면 0단계로 자동 해제
    #   (휴식 후 1단계로 내려온 경우 sleep_times 가 비어 있어도 재개 시각부터 10분은 1단계 유지)
    if state["stage"] == 1 and not state["sleep_times"] and state["stage_changed_at"] <= cutoff:
        _change_stage(state, 0)


def start_drive(user_id: int) -> dict:
    """운행 시작 (/drive/start) -> 0 · 1단계만 0단계로, 2 · 3단계는 유지

    다시 시작으로 경고를 끌 수 없게 (11/03 시연 폰 시험에서 재시작으로 3단계가 풀림, 팀장 결정):
      - 2단계는 쉬어야만, 3단계는 관리자만 해제
      - 10분 졸음 기록(sleep_times)도 지우지 않음 — 지우면 2단계에서 다시 졸아도 3단계로 안 올라감 (10분 지나면 저절로 빠짐)
    """
    state = get_state(user_id)
    now = datetime.now()
    _prune_old_sleeps(state, now)
    if state["stage"] < 2:
        _change_stage(state, 0)
    state["drive_started_at"] = now
    state["rest_started_at"] = None
    state["quiz_fails"] = 0
    state["last_ping_at"] = now
    state["half_recent"] = []   # 반쯤 확인은 이번 운행부터 다시 셈 (평소 뜬 눈 EAR 은 출발 전 측정이 새로 덮어씀)
    return state


def record_sleep(user_id: int, closed_sec: float = 0.0) -> int:
    """
    졸음 확정 시 호출:
    10분 내 졸음 횟수 +1 -> 규칙 단계 계산 (1회=1, 2회=2, 3회 이상=3)
    단계는 올리기만 함 (set_stage 원칙)
    """
    state = get_state(user_id)
    now = datetime.now()
    _prune_old_sleeps(state, now)

    state["sleep_times"].append(now)
    state["last_sleep_at"] = now
    state["last_closed_sec"] = round(float(closed_sec or 0.0), 1)

    count = len(state["sleep_times"])
    rule_stage = min(3, count)
    if state["stage"] == 1:
        # 1단계에서 또 졸면 최소 2단계 — 휴식 후 1단계는 10분 기록이 비어 있어도 "다시 졸면 바로 2단계" (기획안 8-5)
        rule_stage = max(rule_stage, 2)

    set_stage(user_id, rule_stage)
    return state["stage"]


def add_sleep(user_id: int, reason: str | None = None, closed_sec: float = 0.0) -> int:
    """약속 이름 (detect.py 가 부름) — reason(microsleep / perclos) 은 기록만, 단계 계산은 record_sleep 과 같음"""
    return record_sleep(user_id, closed_sec)


def set_stage(user_id: int, new_stage: int) -> int:
    """단계를 올리기만 하는 함수 (기존 단계와 새 단계 중 큰 값 유지, 최대 3)"""
    state = get_state(user_id)
    clamped = max(0, min(3, int(new_stage)))
    if clamped > state["stage"]:
        _change_stage(state, clamped)
    return state["stage"]


def get_current_stage(user_id: int) -> tuple[int, str]:
    """현재 단계 숫자(0~3)와 한글 라벨 반환"""
    state = get_state(user_id)
    _prune_old_sleeps(state, datetime.now())
    stage = state["stage"]
    labels = getattr(
        config, "STAGE_LABELS", {0: "정상", 1: "주의", 2: "휴식 권고", 3: "긴급"}
    )
    return stage, labels.get(stage, "정상")


def reset(user_id: int) -> int:
    """관리자 [조치완료] 시 3단계 -> 0단계 완전 초기화"""
    state = get_state(user_id)
    state["sleep_times"] = []
    _change_stage(state, 0)
    state["quiz_fails"] = 0
    state["rest_started_at"] = None
    state["reset_count"] = state.get("reset_count", 0) + 1
    return 0


def reset_count(user_id: int) -> int:
    """관리자 [조치완료] 횟수 — /detect 가 AI 처리 전 · 후로 비교 (처리 중 해제되면 단계를 다시 올리지 않게, 11/05)"""
    return get_state(user_id).get("reset_count", 0)


reset_by_admin = reset


def restore_from_events(user_id: int, events: list[tuple[int, str, str, datetime]]) -> int:
    """서버를 다시 켠 뒤 DB 경고로 단계 · 10분 졸음 기록을 되살린다 (앱 홈 화면 currentStage 와 같은 규칙).

    events : [(stage, status, reason, created_at), ...] 그 기사의 경고 전부
      - 관리자 [조치완료]는 그 기사 단계를 전부 0 으로 되돌림 → 조치완료된 경고와 그보다 오래된 경고는 세지 않음
      - 가장 최근 휴식완료도 같은 식으로: 그 경고보다 오래된 1 · 2단계 경고는 세지 않음 (3단계는 그대로)
        (2단계 경고가 2건이고 최근 것만 휴식완료여도 오래된 2단계가 다시 살아나지 않게)
      - 3단계: 조치완료 전까지 / 2단계: 휴식완료 · 조치완료 전까지 / 1단계: 10분 안
      - 휴게 미준수(rest_overdue)는 단계를 올린 경고가 아니라서 세지 않음
    이미 메모리에 단계가 있으면(서버가 켜진 뒤 쓰던 기사) 건드리지 않음. 되살린 단계를 돌려줌.
    """
    if user_id in _states:
        return _states[user_id]["stage"]
    now = datetime.now()
    window = timedelta(minutes=_get_window_minutes())
    reset_at = max((c for _, st, _, c in events if st == "조치완료"), default=None)
    rest_done_at = max((c for _, st, _, c in events if st == "휴식완료"), default=None)
    stage, sleeps = 0, []
    for ev_stage, status, reason, created in events:
        if status == "조치완료" or reason == "rest_overdue":
            continue
        if reset_at is not None and created <= reset_at:
            continue
        if rest_done_at is not None and created <= rest_done_at and int(ev_stage) < 3:
            continue                        # 휴식을 마치면 그 전의 1 · 2단계 경고는 끝난 것 (3단계는 조치완료만 해제)
        age = now - created
        active = {3: True, 2: status != "휴식완료", 1: age <= window}.get(int(ev_stage), False)
        if active:
            stage = max(stage, int(ev_stage))
        if reason in ("microsleep", "perclos") and status != "휴식완료" and age <= window:
            sleeps.append(created)
    state = get_state(user_id)
    state["sleep_times"] = sorted(sleeps)
    state["last_sleep_at"] = state["sleep_times"][-1] if sleeps else None
    if stage:
        _change_stage(state, stage)
    return stage


def restore_all(session) -> dict[int, int]:
    """서버를 켤 때 한 번 — 단계가 남아 있는 기사들의 단계를 DB 경고로 되살린다 (main.py lifespan 이 부름).
    {user_id: 되살린 단계} 중 0 이 아닌 것만 돌려줌."""
    from sqlalchemy import select
    from models.models import SleepEvent
    rows = session.execute(
        select(SleepEvent.user_id, SleepEvent.stage, SleepEvent.status, SleepEvent.reason, SleepEvent.created_at)
        .where(SleepEvent.user_id.is_not(None))
    ).all()
    by_user: dict[int, list] = {}
    for uid, stage, status, reason, created in rows:
        by_user.setdefault(uid, []).append((stage, status or "", reason or "", created))
    restored = {}
    for uid, events in by_user.items():
        stage = restore_from_events(uid, events)
        if stage:
            restored[uid] = stage
    return restored


def start_rest(user_id: int) -> datetime:
    """[정차했어요] 호출 시 휴식 시작 시각 기록"""
    state = get_state(user_id)
    now = datetime.now()
    state["rest_started_at"] = now
    return now


def resume_drive(user_id: int) -> tuple[bool, int, dict]:
    """
    [운행 재개] 호출 시 서버 시각으로 15분 경과 여부 검사.
    통과 시 2단계 -> 1단계로 하향, 휴식 기록 반환.
    """
    state = get_state(user_id)
    now = datetime.now()
    started = state.get("rest_started_at")
    req_min = _get_rest_minutes()

    if started is None:
        return False, state["stage"], {}

    elapsed_min = (now - started).total_seconds() / 60.0
    if elapsed_min < req_min:
        return False, state["stage"], {"minutes": int(elapsed_min)}

    if state["stage"] == 2:
        _change_stage(state, 1)
    state["sleep_times"] = []
    state["quiz_fails"] = 0
    state["rest_started_at"] = None

    rest_info = {
        "started": started.strftime("%H:%M"),
        "resumed": now.strftime("%H:%M"),
        "minutes": int(round(elapsed_min)),
    }
    return True, state["stage"], rest_info


def record_quiz_result(user_id: int, passed: bool) -> tuple[int, bool]:
    """운전 중 음성 퀴즈 채점 결과 반영 (2번 연속 실패 시 단계 +1)"""
    state = get_state(user_id)
    if passed:
        state["quiz_fails"] = 0
        return state["stage"], False

    state["quiz_fails"] += 1
    max_tries = getattr(config, "VOICE_QUIZ_MAX_TRIES", 2)
    if state["quiz_fails"] >= max_tries:
        state["quiz_fails"] = 0
        old_stage = state["stage"]
        new_stage = set_stage(user_id, old_stage + 1)
        return new_stage, (new_stage > old_stage)

    return state["stage"], False


def set_personal_ear(user_id: int, ear_threshold: float) -> None:
    state = get_state(user_id)
    state["personal_ear"] = ear_threshold


def get_personal_ear(user_id: int) -> float:
    return get_state(user_id)["personal_ear"]


def get_facts(user_id: int, drive_min: int = 0) -> dict:
    """Agent 기사 음성 보고(driver_voice) 숫자 보증용 facts 반환"""
    state = get_state(user_id)
    _prune_old_sleeps(state, datetime.now())
    stage, status = get_current_stage(user_id)
    return {
        "sleep_count_10min": len(state["sleep_times"]),
        "closed_sec": state["last_closed_sec"],
        "drive_min": drive_min,
        "stage": stage,
        "status": status,
    }


# ═══════════════════════════════════════════════════════════════
# 약속 이름 (10/27 팀장 추가) — 팀장 detect.py · quiz.py, A 의 face_service.py, D 의 event.py 가 이 이름으로 부름
#   위 A 의 함수를 그대로 감싸기만 한다 (동작은 같음)
# ═══════════════════════════════════════════════════════════════
def get_stage(user_id: int) -> int:
    """지금 단계 숫자 (1단계 10분 자동 해제 검사 포함)"""
    return get_current_stage(user_id)[0]


def facts(user_id: int) -> dict:
    """Agent 음성 보고 숫자 — 10분 졸음 횟수 · 마지막 감김 초 · 단계 (운행 분은 drive_timer 가 줌)"""
    f = get_facts(user_id)
    return {"sleep_count_10min": f["sleep_count_10min"], "last_closed_sec": f["closed_sec"], "stage": f["stage"]}


def rest_elapsed_min(user_id: int) -> float | None:
    """[정차했어요] 뒤 지난 분. 안 쉬는 중이면 None (/drive/resume 이 15분 검사에 씀)"""
    started = get_state(user_id).get("rest_started_at")
    if started is None:
        return None
    return (datetime.now() - started).total_seconds() / 60.0


def finish_rest(user_id: int) -> int:
    """15분 휴식 뒤 [운행 재개] — resume_drive 와 같은 정리 (2단계 → 1단계, 10분 기록 · 퀴즈 실패 비움)"""
    state = get_state(user_id)
    if state["stage"] == 2:
        _change_stage(state, 1)
    state["sleep_times"] = []
    state["quiz_fails"] = 0
    state["rest_started_at"] = None
    return state["stage"]


def get_ear_threshold(user_id: int) -> float | None:
    """서버 개인 기준 EAR (face_service 가 부름). 측정 전이면 config.EAR_THRESHOLD"""
    return get_personal_ear(user_id)


def set_ear_threshold(user_id: int, ear: float) -> None:
    """/drive/calibrate 가 5장으로 만든 개인 기준 EAR 저장"""
    set_personal_ear(user_id, ear)


# ── 🆕 (11/10) 반쯤 감은 눈 ──────────────────────────────────
#   ML Kit 은 반쯤 감은 눈을 뜸 (0.73 ~ 0.99) 으로 봐서 앱이 의심을 안 냄 → 앱이 10초마다 보낸 사진의 서버 EAR 로 판정
#   값은 config 에 있으면 그 값 (팀장 파일), 없으면 아래 기본값 — 11/11 시험 전에는 바꾸지 않음 (팀장)
HALF_RECENT = getattr(config, "HALF_RECENT", 4)         # 최근 몇 번을 볼지
HALF_NEED = getattr(config, "HALF_NEED", 3)             # 그중 몇 번 반쯤이면 확정
HALF_MAX_AGE_SEC = getattr(config, "HALF_MAX_AGE_SEC", 60)  # 이보다 오래된 결과는 버림 (경고 · 휴식으로 끊긴 앞 기록을 이어 세지 않게)


def set_open_ear(user_id: int, ear: float | None) -> None:
    """출발 전 측정 뜬 눈 EAR 중간값 저장 (face_service.calibrate). 측정 실패면 None → 반쯤 판정 안 함"""
    get_state(user_id)["open_ear"] = None if ear is None else float(ear)


def get_open_ear(user_id: int) -> float | None:
    return get_state(user_id).get("open_ear")


def add_half(user_id: int, is_half: bool) -> bool:
    """반쯤 확인 결과 1개 기록 → 최근 HALF_RECENT 번 중 HALF_NEED 번 반쯤이면 True (피로 확정, 기록 비움)"""
    state = get_state(user_id)
    now = datetime.now()
    recent = [(t, h) for t, h in state["half_recent"] if (now - t).total_seconds() <= HALF_MAX_AGE_SEC]
    recent.append((now, bool(is_half)))
    recent = recent[-HALF_RECENT:]
    n_half = sum(1 for _, h in recent if h)
    fatigue = n_half >= HALF_NEED
    state["half_recent"] = [] if fatigue else recent
    print(f"[half] {now:%H:%M:%S} u{user_id} half={bool(is_half)} {n_half}/{len(recent)} {'확정' if fatigue else '-'}")
    return fatigue
