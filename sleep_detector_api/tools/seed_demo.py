# ═══════════════════════════════════════════════════════════════
# tools/seed_demo.py — 시연용 예시 데이터 (예시 기사 + 일주일치 졸음 경고)
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P1   |   서버 코드가 아니라 PC 에서 돌리는 도구
#
# [하는 일]
#   - 관리자 웹 대시보드 · 통계 · 기사 관리가 텅 비어 보이지 않게, 예시 기사 3~4명과 최근 일주일치 경고를 DB 에 넣는다
#   - 예시 기사 이메일은 모두 @demo.test (예약된 가짜 주소) → 진짜 계정과 섞이지 않고, --clear 로 이 기사들과 경고만 지운다
#   - 경고는 실제 서버가 만드는 모양 그대로: 단계 1~3 · reason(microsleep · perclos · rest_overdue · no_response) ·
#     상태 · 보고서 JSON(눈 숫자 · 운전 중 퀴즈 · 휴식 기록). 졸음이 몰리는 새벽 · 점심 뒤 · 밤 시간대가 더 많다
#   - 오늘 안에 아직 처리 안 된 3단계 · "음성 응답 없음"을 몇 건 남겨서 긴급 알림 · 긴급 카드도 보인다
#   - 사진은 만들지 않는다 (얼굴 사진은 가짜로도 만들지 않음) → 관리자 웹에는 "사진 없음"으로 보인다
#   - 예시 기사의 비밀번호는 아무도 모르는 무작위 값 (로그인 못 함)
#
# [실행] (sleep_detector_api 폴더, 서버와 같은 .env 의 MySQL 에 넣는다)
#   venv\Scripts\python tools/seed_demo.py --dry-run      어떤 데이터가 들어갈지 요약만 보기 (DB 를 건드리지 않음)
#   venv\Scripts\python tools/seed_demo.py                예시 데이터 넣기 (이미 있으면 안 넣고 알려 줌)
#   venv\Scripts\python tools/seed_demo.py --clear        예시 기사 · 그 기사들의 경고만 지우기
#   venv\Scripts\python tools/seed_demo.py --drivers 3 --days 7 --seed 42      (기본값. --seed 가 같으면 같은 데이터)
#   venv\Scripts\python tools/seed_demo.py --db-url sqlite:///임시.db           MySQL 대신 다른 DB 에 시험 (도구 시험용)
#
# [주의]
#   - 넣거나 지우기 전에 어느 DB 인지(호스트 · DB 이름) 먼저 출력한다. 발표 직전에는 --clear 로 정리하고 진짜로 시연
#   - 이 파일은 서버 DB 칸을 바꾸지 않는다 (users · sleep_events 에 있는 칸만 채움)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
import argparse
import json
import os
import random
import secrets
import sys
from collections import Counter
from datetime import datetime, timedelta

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # sleep_detector_api 를 import 경로에

DEMO_DOMAIN = "demo.test"

# (이름, 전화번호, 차량번호) — 전부 가짜. 번호는 표시용 형식만 맞춤
DEMO_DRIVERS = [
    ("김도윤", "010-5550-0101", "경기 81바 1234"),
    ("이서준", "010-5550-0102", "서울 82사 5678"),
    ("박지후", "010-5550-0103", "충남 83아 2468"),
    ("최민재", "010-5550-0104", "경기 84자 1357"),
]

# 경부고속도로 따라 몇 곳 (위도, 경도)
PLACES = [(37.3947, 127.1112), (37.0045, 127.2799), (36.8151, 127.1139), (36.3504, 127.3845), (36.1398, 128.1136), (35.8714, 128.6014)]

# 졸음이 몰리는 시간대 (시 → 가중치): 새벽 2~5시, 점심 뒤 13~15시, 밤 22~23시
HOUR_WEIGHTS = {0: 2, 1: 3, 2: 5, 3: 6, 4: 6, 5: 4, 6: 1, 9: 1, 12: 1, 13: 3, 14: 4, 15: 3, 16: 1, 20: 1, 21: 2, 22: 3, 23: 3}

QUIZ_SENTENCES = ["졸리면 쉬어 가겠습니다", "안전 운전이 최우선입니다", "졸음쉼터에서 잠깐 쉬겠습니다", "신호를 잘 지키겠습니다"]
QUIZ_SUMS = [("23+45", "육십팔"), ("31+52", "팔십삼"), ("14+25", "삼십구"), ("42+36", "칠십팔")]

GUIDANCE = {1: "창문을 열고 환기하며 주의해서 운전해 주세요.", 2: "가까운 졸음쉼터에서 15분 이상 쉬어 주세요.", 3: "관리자에게 알렸습니다. 안전한 곳에 바로 정차해 주세요."}
STAGE_REASON = {1: "처음 감지된 졸음으로 주의가 필요", 2: "반복된 졸음으로 휴식 필요", 3: "졸음이 계속되어 긴급 조치 필요"}
RECOMMENDED = {1: "기록 확인", 2: "기사에게 연락해 휴식 여부 확인", 3: "즉시 기사에게 연락하고 정차 여부 확인"}
REGULATION = "화물자동차 운수사업법 시행규칙 제22조"


def _round(x, n=2):
    return None if x is None else round(x, n)


def make_event(rng, driver_idx, when, stage, reason, status, count):
    """경고 1건 (SleepEvent 칸 이름 그대로). 사진은 없다."""
    closed_sec = _round(rng.uniform(1.5, 4.0), 1) if reason == "microsleep" else None
    perclos = _round(rng.uniform(0.15, 0.4), 2) if reason == "perclos" else None
    eye_open = _round(rng.uniform(0.02, 0.25)) if reason in ("microsleep", "perclos") else None
    lat, lng = rng.choice(PLACES)

    if reason == "perclos":
        summary = f"눈 감김 비율(PERCLOS)이 {int(round(perclos * 100))}%로 피로가 누적된 상태입니다. 10분 안에 {count}번째 졸음입니다."
    elif reason == "microsleep":
        summary = f"눈을 약 {int(round(closed_sec))}초간 감고 있었습니다. 10분 안에 {count}번째 졸음입니다."
    elif reason == "rest_overdue":
        summary = "연속 운전 2시간이 지났는데 휴식을 취하지 않았습니다."
    else:
        summary = "운전 중 음성 퀴즈에 2번 답하지 못했습니다."

    report = {
        "situation": summary,
        "stage_reason": "연속 운전 2시간 초과 · 휴게 미준수" if reason == "rest_overdue" else STAGE_REASON[stage],
        "regulation": REGULATION,
        "recommended_action": "기사에게 휴식 안내" if reason == "rest_overdue" else RECOMMENDED[stage],
        "location": f"{lat}, {lng}",
        "is_real": {"llm": False, "rag": False, "agent": False, "driver_voice": False},  # 예시 데이터 → 관리자 웹에 '모의' 표시
        "driving_quiz": [],
        "rest": None,
        "eye": None,
    }
    if reason in ("microsleep", "perclos"):
        report["eye"] = {"closed_sec": closed_sec, "perclos": perclos, "eye_open_prob": eye_open, "photo": False}
    if reason == "no_response":
        report["driving_quiz"] = [
            {"type": "repeat", "asked": rng.choice(QUIZ_SENTENCES), "heard": "", "passed": False, "answer_sec": None},
            {"type": "add", "asked": rng.choice(QUIZ_SUMS)[0], "heard": "", "passed": False, "answer_sec": None},
        ]
    elif stage >= 2 and reason != "rest_overdue" and rng.random() < 0.6:
        asked, heard = rng.choice(QUIZ_SUMS)
        report["driving_quiz"] = [{"type": "add", "asked": asked, "heard": heard, "passed": True, "answer_sec": _round(rng.uniform(1.5, 4.5), 1)}]
    if stage == 2 and status == "휴식완료":
        start = when + timedelta(minutes=rng.randint(1, 4))
        minutes = rng.randint(15, 25)
        report["rest"] = {"started": start.strftime("%H:%M"), "resumed": (start + timedelta(minutes=minutes)).strftime("%H:%M"), "minutes": minutes}

    return {
        "stage": stage, "ear": None, "eye_closed_prob": _round(1 - eye_open, 3) if eye_open is not None else None, "method": "mlkit",
        "reason": reason, "perclos": perclos, "summary": summary[:255], "guidance": ("가까운 졸음쉼터에서 쉬어 주세요." if reason == "rest_overdue" else GUIDANCE[stage]),
        "report": json.dumps(report, ensure_ascii=False), "photo_path": None, "latitude": lat, "longitude": lng,
        "status": status, "created_at": when, "_driver": driver_idx,
    }


def pick_status(rng, stage, reason, age_days, urgent_open):
    """오래된 경고일수록 처리가 끝난 쪽으로. urgent_open 이면 오늘 처리 안 된 긴급으로 남긴다."""
    if urgent_open:
        return "미확인"
    if stage == 3 or reason == "no_response":
        return "조치완료" if age_days >= 1 else rng.choice(["미확인", "확인"])
    if stage == 2:
        return "휴식완료" if age_days >= 1 or rng.random() < 0.6 else "미확인"
    return rng.choice(["확인", "확인", "미확인"]) if age_days < 1 else rng.choice(["확인", "확인", "확인", "조치완료"])


def build_events(rng, n_drivers, days, now):
    """기사별 · 날짜별로 졸음이 이어지는 묶음(1 → 2 → 3단계)을 만든다."""
    hours = list(HOUR_WEIGHTS)
    weights = list(HOUR_WEIGHTS.values())
    events = []
    for d in range(n_drivers):
        for age in range(days):                          # age 0 = 오늘
            day = (now - timedelta(days=age)).replace(hour=0, minute=0, second=0, microsecond=0)
            for _ in range(rng.choices([0, 1, 2], weights=[3, 5, 2])[0]):   # 하루 0~2번 졸음 묶음
                hour = rng.choices(hours, weights)[0]
                start = day + timedelta(hours=hour, minutes=rng.randint(0, 59))
                if start > now:
                    start = now - timedelta(minutes=rng.randint(20, 240))
                depth = rng.choices([1, 2, 3], weights=[5, 3, 1.5])[0]      # 이 묶음이 몇 단계까지 가는가
                for step in range(depth):
                    when = start + timedelta(minutes=step * rng.randint(3, 8))
                    stage = step + 1
                    reason = "no_response" if (stage == 3 and rng.random() < 0.5) else rng.choice(["microsleep", "microsleep", "perclos"])
                    events.append(dict(driver=d, when=when, stage=stage, reason=reason, age=age, count=step + 1))
            if rng.random() < 0.12:                      # 가끔 휴게 미준수
                when = day + timedelta(hours=rng.randint(10, 20), minutes=rng.randint(0, 59))
                if when <= now:
                    events.append(dict(driver=d, when=when, stage=1, reason="rest_overdue", age=age, count=1))
    # 오늘 처리 안 된 긴급(3단계 · 음성 응답 없음)이 최소 2건은 있게 (시연에서 긴급 카드 · 알림이 비어 보이지 않게)
    todays = [e for e in events if e["age"] == 0 and (e["stage"] == 3 or e["reason"] == "no_response")]
    for k in range(max(0, 2 - len(todays))):
        d = k % n_drivers
        events.append(dict(driver=d, when=now - timedelta(minutes=15 + 40 * k), stage=3, reason="no_response" if k else "microsleep", age=0, count=3))
    events.sort(key=lambda e: e["when"])
    out = []
    for e in events:
        urgent = e["age"] == 0 and (e["stage"] == 3 or e["reason"] == "no_response") and e["when"] >= now - timedelta(hours=3)
        status = pick_status(rng, e["stage"], e["reason"], e["age"], urgent)
        out.append(make_event(rng, e["driver"], e["when"], e["stage"], e["reason"], status, e["count"]))
    return out


def summarize(events, n_drivers):
    by_stage = Counter(e["stage"] for e in events)
    by_reason = Counter(e["reason"] for e in events)
    open_urgent = sum(1 for e in events if (e["stage"] == 3 or e["reason"] == "no_response") and e["status"] != "조치완료")
    print(f"  예시 기사 {n_drivers}명 · 경고 {len(events)}건")
    print("  단계별  :", " · ".join(f"{s}단계 {by_stage.get(s, 0)}건" for s in (1, 2, 3)))
    print("  종류별  :", " · ".join(f"{k} {v}건" for k, v in sorted(by_reason.items())))
    print(f"  처리 안 된 긴급(3단계 · 음성 응답 없음): {open_urgent}건")


def open_session(db_url):
    """--db-url 이 있으면 그 DB(표도 만듦), 없으면 서버와 같은 MySQL(.env)."""
    if db_url:
        from sqlalchemy import create_engine
        from sqlalchemy.orm import sessionmaker
        from database.orm import Base
        import models.models  # noqa: F401  (표 정의를 불러온다)
        engine = create_engine(db_url)
        Base.metadata.create_all(engine)
        return sessionmaker(bind=engine, autocommit=False, autoflush=False)(), db_url.split("///")[-1] or db_url
    from database.db_connection import DB_HOST, DB_NAME, DB_PORT, SessionLocal
    return SessionLocal(), f"MySQL {DB_HOST}:{DB_PORT}/{DB_NAME}"


def main():
    ap = argparse.ArgumentParser(description="시연용 예시 기사 · 경고 넣기 / 지우기")
    ap.add_argument("--clear", action="store_true", help="예시 기사(@demo.test)와 그 경고만 지움")
    ap.add_argument("--dry-run", action="store_true", help="DB 를 건드리지 않고 넣을 내용만 요약")
    ap.add_argument("--drivers", type=int, default=4, help="예시 기사 수 (3~4, 기본 4)")
    ap.add_argument("--days", type=int, default=7, help="최근 며칠치 (기본 7)")
    ap.add_argument("--seed", type=int, default=42, help="같은 값이면 같은 데이터 (기본 42)")
    ap.add_argument("--db-url", default=None, help="MySQL 대신 시험할 DB 주소 (예: sqlite:///demo_test.db)")
    args = ap.parse_args()
    n_drivers = max(3, min(len(DEMO_DRIVERS), args.drivers))

    if args.dry_run and not args.clear:
        events = build_events(random.Random(args.seed), n_drivers, args.days, datetime.now().replace(microsecond=0))
        print("[dry-run] DB 를 건드리지 않았습니다. 넣게 되면:")
        summarize(events, n_drivers)
        return 0

    from models.models import SleepEvent, User
    session, target = open_session(args.db_url)
    print(f"대상 DB: {target}")
    try:
        demo_users = session.query(User).filter(User.email.like(f"%@{DEMO_DOMAIN}")).all()
        if args.clear:
            ids = [u.id for u in demo_users]
            n_events = session.query(SleepEvent).filter(SleepEvent.user_id.in_(ids)).count() if ids else 0
            print(f"지울 것: 예시 기사 {len(ids)}명 · 그 기사들의 경고 {n_events}건 (@{DEMO_DOMAIN} 계정만)")
            if args.dry_run:
                print("[dry-run] 지우지 않았습니다.")
                return 0
            if ids:
                session.query(SleepEvent).filter(SleepEvent.user_id.in_(ids)).delete(synchronize_session=False)
                session.query(User).filter(User.id.in_(ids)).delete(synchronize_session=False)
                session.commit()
            print("지웠습니다." if ids else "지울 예시 데이터가 없어요.")
            return 0

        if demo_users:
            print(f"이미 예시 기사 {len(demo_users)}명이 있어요. 먼저 --clear 로 지운 뒤 다시 넣어 주세요. (아무것도 바꾸지 않음)")
            return 1

        from auth.password import hash_password
        now = datetime.now().replace(microsecond=0)
        rng = random.Random(args.seed)
        users = []
        for i in range(n_drivers):
            name, phone, vehicle = DEMO_DRIVERS[i]
            u = User(email=f"demo{i + 1}@{DEMO_DOMAIN}", hashed_password=hash_password(secrets.token_urlsafe(24)), name=name, role="user",
                     provider="email", phone=phone, vehicle_no=vehicle, created_at=now - timedelta(days=args.days + 3))
            session.add(u)
            users.append(u)
        session.flush()                                  # users[i].id 를 받는다
        events = build_events(rng, n_drivers, args.days, now)
        for e in events:
            fields = {k: v for k, v in e.items() if not k.startswith("_")}
            session.add(SleepEvent(user_id=users[e["_driver"]].id, **fields))
        session.commit()
        print("넣었습니다:")
        summarize(events, n_drivers)
        print("지우려면: venv\\Scripts\\python tools/seed_demo.py --clear")
        return 0
    finally:
        session.close()


if __name__ == "__main__":
    sys.exit(main())
