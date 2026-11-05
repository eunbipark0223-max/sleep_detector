# ═══════════════════════════════════════════════════════════════
# tools/kpi3_scenarios.py — KPI ③ 단계 전환 정확도 (시나리오 12개 자동 시험)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0 (KPI ③)   |   서버 코드가 아니라 PC 에서 돌리는 시험 도구
#
# [하는 일]
#   - 기획안 KPI ③ 의 시나리오 12개를 진짜 서버 코드(라우터 · sleep_state · drive_timer · agent 규칙)로 돌려
#     기대한 단계와 같은지 ✅ / ❌ 표로 보여 준다. 목표: 12개 모두 통과
#   - 보너스: 3단계는 휴식으로 해제되지 않음 (관리자만)
#
# [어떻게]
#   - DB 는 임시 SQLite (팀원 PC 의 MySQL 을 건드리지 않음, 끝나면 지움)
#   - AI 는 가짜 (LLM · RAG · Agent · 눈 판정) → 무료 한도를 안 씀, Agent 는 규칙 단계 그대로
#     눈 판정 가짜는 파일 이름으로: closed = 감음, noface = 얼굴 없음, 그 밖 = 뜸
#   - 시간이 걸리는 것(10분 · 15분 · 2시간)은 기록 시각을 앞당겨 바로 확인
#
# [실행] (sleep_detector_api 폴더)
#   venv\Scripts\python tools/kpi3_scenarios.py
#   → 끝 줄 "12/12 통과" · 하나라도 실패하면 종료 코드 1
#
# 자세한 내용: 「파이널 프로젝트 최종 기획안 10.13」 KPI ③ · 7장 경고 단계 · 8장 음성 퀴즈
# ═══════════════════════════════════════════════════════════════
import io
import os
import shutil
import sys
import tempfile
from contextlib import redirect_stdout
from datetime import timedelta

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)
os.chdir(BASE)

import config  # noqa: E402

TMP = tempfile.mkdtemp(prefix="kpi3_")
config.UPLOAD_TMP_DIR = os.path.join(TMP, "tmp")      # 시험 사진은 임시 폴더에만
config.UPLOAD_EVENT_DIR = os.path.join(TMP, "events")

from services import agent_service, face_service, llm_service, rag_service, sleep_state, drive_timer  # noqa: E402
from services import voice_quiz_service  # noqa: E402

for m in (llm_service, rag_service, agent_service, face_service):
    m.USE_REAL_AI = False

from sqlalchemy import create_engine  # noqa: E402
from sqlalchemy.orm import sessionmaker  # noqa: E402
from sqlalchemy.pool import StaticPool  # noqa: E402

from database.orm import Base, get_db  # noqa: E402
from database.db_connection import get_session  # noqa: E402
from models.models import SleepEvent, User  # noqa: E402

engine = create_engine("sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool)
Base.metadata.create_all(engine)
TestSession = sessionmaker(bind=engine, autoflush=False, autocommit=False)


def _override():
    with TestSession() as s:
        yield s


with redirect_stdout(io.StringIO()):      # 서버 시작 문구 · AI 가짜 안내는 숨김
    import main  # noqa: E402
    from routers import detect  # noqa: E402
main.app.dependency_overrides[get_session] = _override
main.app.dependency_overrides[get_db] = _override

from fastapi.testclient import TestClient  # noqa: E402

PNG = b"\x89PNG fake"     # 가짜 눈 판정이라 내용은 상관없음 (파일 이름만 봄)
client = TestClient(main.app)
_n = 0


def new_driver():
    """시나리오마다 새 기사 (기록이 섞이지 않게)"""
    global _n
    _n += 1
    email = f"kpi3_{_n}@test.com"
    client.post("/users/signup", json={"email": email, "password": "Test1234!", "name": f"기사{_n}"})
    tok = client.post("/users/login", json={"email": email, "password": "Test1234!"}).json()["access_token"]
    h = {"Authorization": f"Bearer {tok}"}
    uid = client.get("/users/me", headers=h).json()["id"]
    client.post("/drive/start", headers=h)
    detect._last_quiz_at.pop(uid, None)
    return h, uid


def admin_headers():
    email = "kpi3_admin@test.com"
    client.post("/users/signup", json={"email": email, "password": "Test1234!", "name": "관리자"})
    with TestSession() as s:
        s.query(User).filter(User.email == email).one().role = "admin"
        s.commit()
    tok = client.post("/users/login", json={"email": email, "password": "Test1234!"}).json()["access_token"]
    return {"Authorization": f"Bearer {tok}"}


def doze(h, name="closed.png", reason="microsleep", closed_sec="2.0"):
    """앱이 '졸음 의심' 사진 1장을 보낸 것과 같음"""
    r = client.post("/detect", files={"file": (name, PNG, "image/png")},
                    data={"reason": reason, "closed_sec": closed_sec, "perclos": "0.2", "eye_open_prob": "0.05"},
                    headers=h)
    assert r.status_code == 200, r.text
    return r.json()


def ping(h):
    return client.post("/drive/ping", headers=h).json()


def back(uid, minutes):
    """sleep_state 의 시각을 minutes 분 앞으로 (= 그만큼 시간이 흐른 것과 같음)"""
    st = sleep_state.get_state(uid)
    d = timedelta(minutes=minutes)
    st["sleep_times"] = [t - d for t in st["sleep_times"]]
    if st.get("stage_changed_at"):
        st["stage_changed_at"] -= d
    if st.get("rest_started_at"):
        st["rest_started_at"] -= d


def answer_of(quiz):
    a = voice_quiz_service._quizzes[quiz["quiz_id"]]["answer"]   # 시험용: 정답 엿보기
    return str(a)


# ───────────────────────────────────────────────
# 시나리오 (이름, 기대, 함수 → 실제 값)
# ───────────────────────────────────────────────
def s1():
    h, _ = new_driver()
    return doze(h)["stage"]


def s2():
    h, _ = new_driver()
    doze(h)
    return doze(h)["stage"]


def s3():
    h, _ = new_driver()
    doze(h); doze(h)
    return doze(h)["stage"]


def s4():
    h, uid = new_driver()
    doze(h)
    back(uid, config.WINDOW_MIN + 1)
    return ping(h)["stage"]


def s5():
    h, uid = new_driver()
    doze(h); doze(h)                                    # 2단계
    client.post("/drive/rest", headers=h)
    back(uid, config.REST_MIN + 1)
    return client.post("/drive/resume", headers=h).json()["stage"]


def s6():
    h, uid = new_driver()
    doze(h); doze(h)
    client.post("/drive/rest", headers=h)
    back(uid, config.REST_MIN - 5)                      # 아직 덜 쉼
    r = client.post("/drive/resume", headers=h)
    return f"{r.status_code} · {ping(h)['stage']}단계"


def s7():
    h, uid = new_driver()
    doze(h); doze(h); ev = doze(h)                      # 3단계
    client.patch(f"/events/{ev['event_id']}/status", json={"status": "조치완료"}, headers=admin_headers())
    return ping(h)["stage"]


def s8():
    h, _ = new_driver()
    r = doze(h, name="open.png")                        # 앱은 의심했지만 서버가 보니 확실히 뜸 (짧은 깜빡임)
    return f"{'취소' if not r['is_sleep'] else '확정'} · {r['stage']}단계"


def s9():
    h, _ = new_driver()
    r = doze(h, name="noface.png")                      # 사진에서 얼굴을 못 찾음 → 취소 (손 가리기 · 폰 돌아감, 11/04 A · 팀장)
    return f"{'확정' if r['is_sleep'] else '취소'} · {r['method']} · {r['stage']}단계"


def s10():
    h, uid = new_driver()
    drive_timer._drives[uid]["start"] -= (config.DRIVE_LIMIT_MIN + 1) * 60
    first = ping(h)["rest_due"]
    second = ping(h)["rest_due"]
    return f"{first} · 다음 ping {second}"


def s11():
    h, _ = new_driver()
    q = doze(h)["voice_quiz"]
    r = client.post("/quiz/answer", json={"quiz_id": q["quiz_id"], "answer_text": answer_of(q), "answer_sec": 2.0},
                    headers=h).json()
    return f"{'통과' if r['passed'] else '실패'} · {r['stage']}단계"


def s12():
    h, uid = new_driver()
    q = doze(h)["voice_quiz"]                           # 1단계
    r1 = client.post("/quiz/answer", json={"quiz_id": q["quiz_id"], "answer_text": "", "answer_sec": None},
                     headers=h).json()
    nq = r1["next_quiz"]
    r2 = client.post("/quiz/answer", json={"quiz_id": nq["quiz_id"], "answer_text": "", "answer_sec": None},
                     headers=h).json()
    with TestSession() as s:
        no_resp = s.query(SleepEvent).filter(SleepEvent.user_id == uid, SleepEvent.reason == "no_response").count()
    return f"{r2['stage']}단계 · no_response {no_resp}건"


def bonus():
    h, uid = new_driver()
    doze(h); doze(h); doze(h)                           # 3단계
    client.post("/drive/rest", headers=h)
    back(uid, config.REST_MIN + 1)
    return client.post("/drive/resume", headers=h).json()["stage"]


def bonus_no_photo():
    """고개를 떨궈 얼굴을 놓친 채 감김 → 앱이 사진 없이 보냄 → 서버는 앱 판단대로 확정, 사진 없이 기록"""
    h, uid = new_driver()
    r = client.post("/detect", data={"reason": "microsleep", "closed_sec": "1.8"}, headers=h).json()
    with TestSession() as s:
        ev = s.get(SleepEvent, r["event_id"])
        photo = "사진 없음" if ev.photo_path is None else "사진 있음"
    test = client.post("/detect", data={"reason": ""}, headers=h).status_code   # 사진 1장 테스트는 사진이 꼭 있어야
    return f"{'확정' if r['is_sleep'] else '취소'} · {r['method']} · {r['stage']}단계 · {photo} · 사진 테스트 {test}"


def bonus_restart():
    """운행을 다시 시작해도 2 · 3단계는 그대로 (기사는 끌 수 없음, 11/03), 1단계는 0단계로"""
    out = []
    for n in (1, 2, 3):
        h, _ = new_driver()
        for _ in range(n):
            doze(h)
        out.append(client.post("/drive/start", headers=h).json()["stage"])
    return " · ".join(map(str, out))


def bonus_rest_detect():
    """휴식 중(정차했어요 ~ 운행 재개)에 온 졸음 의심은 세지 않음 (11/03)"""
    h, _ = new_driver()
    doze(h)
    doze(h)
    client.post("/drive/rest", headers=h)
    r = doze(h)
    return f"{'무시' if not r['is_sleep'] else '확정'} · {r['stage']}단계"


def bonus_restore():
    """서버를 다시 켜도 3 · 2단계는 DB 경고로 되살아남, 휴식을 마친 2단계는 안 되살아남 (11/04 D)"""
    def restart(uid):                     # 이 기사의 메모리만 비우고, 서버를 켤 때처럼 DB 로 되살림
        sleep_state._states.pop(uid, None)
        with TestSession() as s:
            sleep_state.restore_all(s)
        return sleep_state.get_stage(uid)

    out = []
    h, uid = new_driver()
    for _ in range(3):
        doze(h)
    out.append(restart(uid))
    h, uid = new_driver()
    doze(h)
    doze(h)
    out.append(restart(uid))
    h, uid = new_driver()
    doze(h)
    doze(h)
    client.post("/drive/rest", headers=h)
    back(uid, 16)
    client.post("/drive/resume", headers=h)
    out.append(restart(uid))
    return " · ".join(map(str, out))


def bonus_drive_end():
    """[운행 종료] → 홈 배너는 안 뜨고, 다시 시작해도 연속 운전 시간은 그대로 (휴게 알림을 피할 수 없게, 11/04 D)"""
    h, uid = new_driver()
    drive_timer._drives[uid]["start"] -= 100 * 60
    client.post("/drive/end", headers=h)
    active = client.get("/drive/state", headers=h).json()["active"]
    return f"배너 {active} · {ping(h)['drive_min']}분"


def bonus_reset_race():
    """AI 처리 중 관리자 [조치완료] → 끝나도 단계가 다시 안 오름 · 퀴즈 없음 · 경고는 조치완료로 기록 (11/05)"""
    h, uid = new_driver()
    real = agent_service.generate_response

    def slow(*a, **k):                  # AI 가 도는 사이에 관리자가 누른 것과 같음
        sleep_state.reset(uid)
        return real(*a, **k)

    agent_service.generate_response = slow
    try:
        r = doze(h)
    finally:
        agent_service.generate_response = real
    with TestSession() as s:
        status = s.query(SleepEvent).filter(SleepEvent.user_id == uid).one().status
    return f"단계 {r['stage']} · ping {ping(h)['stage']} · 퀴즈 {r['voice_quiz'] is not None} · {status}"


def bonus_error():
    """서버 판정 오류면 사진이 있어도 앱 판단대로 확정 (얼굴 없음 취소와 구분, 11/04 A)"""
    h, _ = new_driver()
    real_flag, real_fn = face_service.USE_REAL_AI, face_service._real

    def boom(*_a, **_k):
        raise RuntimeError("시험용 오류")

    face_service.USE_REAL_AI, face_service._real = True, boom
    try:
        return "확정" if doze(h)["is_sleep"] else "취소"
    finally:
        face_service.USE_REAL_AI, face_service._real = real_flag, real_fn


SCENARIOS = [
    ("① 졸음 1회 → 1단계",                   1, s1),
    ("② 10분 안 졸음 2회 → 2단계",              2, s2),
    ("③ 10분 안 졸음 3회 → 3단계",              3, s3),
    ("④ 1단계에서 10분 졸음 없음 → 0단계",        0, s4),
    ("⑤ 2단계 → 휴식 15분 → 재개 → 1단계",       1, s5),
    ("⑥ 15분 전 재개 → 거절, 2단계 그대로",       "409 · 2단계", s6),
    ("⑦ 3단계 → 관리자 조치완료 → 0단계",         0, s7),
    ("⑧ 짧은 깜빡임 (서버: 확실히 뜸) → 취소",     "취소 · 0단계", s8),
    ("⑨ 사진에서 얼굴 못 찾음 → 취소",             "취소 · mlkit · 0단계", s9),
    ("⑩ 연속 2시간 → 휴게 알림 1번",             "True · 다음 ping False", s10),
    ("⑪ 운전 중 퀴즈 통과 → 단계 그대로",          "통과 · 1단계", s11),
    ("⑫ 운전 중 퀴즈 2번 실패 → 단계 +1",          "2단계 · no_response 1건", s12),
]
BONUS = [("(보너스) 3단계는 휴식으로 안 풀림 → 3단계", 3, bonus),
         ("(보너스) 사진 없는 졸음 → 앱 판단대로 확정", "확정 · mlkit · 1단계 · 사진 없음 · 사진 테스트 400", bonus_no_photo),
         ("(보너스) 1 · 2 · 3단계에서 운행 다시 시작", "0 · 2 · 3", bonus_restart),
         ("(보너스) 2단계 휴식 중 졸음 의심 → 무시", "무시 · 2단계", bonus_rest_detect),
         ("(보너스) 재시작 복원: 3단계 · 2단계 · 휴식 뒤", "3 · 2 · 0", bonus_restore),
         ("(보너스) 운행 종료 뒤 연속 운전 시간 유지", "배너 False · 100분", bonus_drive_end),
         ("(보너스) 서버 판정 오류 → 앱 판단대로 확정", "확정", bonus_error),
         ("(보너스) AI 처리 중 조치완료 → 단계 안 오름", "단계 0 · ping 0 · 퀴즈 False · 조치완료", bonus_reset_race)]


def run(items):
    passed = 0
    for name, want, fn in items:
        try:
            with redirect_stdout(io.StringIO()):
                got = fn()
        except Exception as e:   # 시나리오 하나가 터져도 나머지는 계속
            got = f"오류: {type(e).__name__} {e}"
        ok = got == want
        passed += ok
        print(f"{'✅' if ok else '❌'} {name:34s} 기대 {want!s:22s} 실제 {got}")
    return passed


if __name__ == "__main__":
    print(f"KPI ③ 단계 전환 시나리오 (DEMO_MODE={config.DEMO_MODE}, 10분={config.WINDOW_MIN} · "
          f"휴식={config.REST_MIN} · 휴게 알림={config.DRIVE_LIMIT_MIN}분)\n")
    try:
        ok = run(SCENARIOS)
        print()
        run(BONUS)
        print(f"\n결과: {ok}/{len(SCENARIOS)} 통과" + ("  🎉 목표 달성" if ok == len(SCENARIOS) else "  ⚠️ 실패한 시나리오 확인"))
    finally:
        shutil.rmtree(TMP, ignore_errors=True)
    sys.exit(0 if ok == len(SCENARIOS) else 1)
