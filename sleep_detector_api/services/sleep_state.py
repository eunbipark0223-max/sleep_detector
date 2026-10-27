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
#   - 개인 기준 EAR, 음성 보고용 facts (10분 졸음 횟수 · 마지막 closed_sec · 운행 분 · 단계)
#   - 휴식 시작 시각 · 운전 중 퀴즈 실패 횟수 · 마지막 퀴즈 시각 · 마지막 ping 시각
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
            "last_sleep_at": None,       # 마지막 졸음 시각
            "last_closed_sec": 0.0,      # 마지막 연속 감김 시간(초)
            "personal_ear": getattr(config, "EAR_THRESHOLD", 0.20),
            "drive_started_at": datetime.now(),
            "rest_started_at": None,     # [정차했어요] 누른 시각
            "quiz_fails": 0,             # 운전 중 퀴즈 연속 실패 횟수
            "last_quiz_at": None,        # 마지막 퀴즈 출제 시각 (2분 간격 제한용)
            "last_ping_at": None,        # 마지막 ping 수신 시각
        }
    return _states[user_id]


def _prune_old_sleeps(state: dict, now: datetime) -> None:
    """10분(시연 모드 1분)이 지난 졸음 기록 제거 및 1단계 자동 해제"""
    cutoff = now - timedelta(minutes=_get_window_minutes())
    state["sleep_times"] = [t for t in state["sleep_times"] if t >= cutoff]

    # 1단계에서 10분 동안 추가 졸음이 없으면 0단계로 자동 해제
    if state["stage"] == 1 and len(state["sleep_times"]) == 0:
        state["stage"] = 0


def start_drive(user_id: int) -> dict:
    """운행 시작 (/drive/start) -> 단계 및 기록 초기화"""
    state = get_state(user_id)
    now = datetime.now()
    state["sleep_times"] = []
    state["stage"] = 0
    state["last_sleep_at"] = None
    state["last_closed_sec"] = 0.0
    state["drive_started_at"] = now
    state["rest_started_at"] = None
    state["quiz_fails"] = 0
    state["last_ping_at"] = now
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

    set_stage(user_id, rule_stage)
    return state["stage"]


add_sleep = record_sleep


def set_stage(user_id: int, new_stage: int) -> int:
    """단계를 올리기만 하는 함수 (기존 단계와 새 단계 중 큰 값 유지, 최대 3)"""
    state = get_state(user_id)
    clamped = max(0, min(3, int(new_stage)))
    if clamped > state["stage"]:
        state["stage"] = clamped
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
    state["stage"] = 0
    state["quiz_fails"] = 0
    state["rest_started_at"] = None
    return 0


reset_by_admin = reset


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
        state["stage"] = 1
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