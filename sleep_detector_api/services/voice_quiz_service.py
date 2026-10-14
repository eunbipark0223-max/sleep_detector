# ═══════════════════════════════════════════════════════════════
# services/voice_quiz_service.py — 운전 중 음성 퀴즈 출제 · 채점 (코드, LLM 안 씀)
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P1
# 수업 원본: (없음, 🔴 신규 — 수업 서비스의 _normalize 방식)
#
# [이 파일이 하는 일]
#   - 출제: 따라 말하기 · 받아올림 없는 덧셈 중 랜덤 1문제 → quiz_id · type · speak(읽을 문장) · display(화면 글자) · listen_sec
#   -   정답과 event_id 는 서버에만 보관 (응답에 정답을 넣지 않음)
#   -   따라 말하기 문장은 knowledge/voice_quiz/repeat_sentences.txt, 덧셈은 코드가 생성
#   - 채점: 공백 · 문장부호 지우기 → 따라 말하기 글자 유사도 ≥ 0.8 / 덧셈은 아라비아 · 한글 숫자 → 정수 비교
#   - (부품 B 일 때만 = config.QUIZ_MODE "screen") 덧셈만 내고 보기 4개(choices)를 붙임
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - make_quiz(user_id, qtype=None, event_id=None) → 문제 dict (qtype 을 주면 같은 유형 새 문제)
#       {"quiz_id", "type": "repeat" | "add", "speak", "display", "listen_sec"} (+ 부품 B 면 "choices")
#   - check_answer(quiz_id, answer_text) → passed (bool). 한 번 채점한 문제는 지워짐. 없는 quiz_id 면 KeyError
#   - get_quiz(quiz_id) → {"quiz_id", "user_id", "type", "event_id", "attempt", "display", "created_at"} 또는 None
#       quiz.py 가 채점 전에 불러서 404 · 같은 유형 다음 문제 · 결과를 붙일 event_id 를 정함 (정답은 안 줌)
#
# [주의]
#   - 거꾸로 말하기는 넣지 않는다 (기획안 8-3)
#   - 최소 2분 간격 · 2번 기회는 detect.py · quiz.py 가 지킴
#   - 문제는 서버 메모리에만 있음 → 서버를 다시 켜면 사라짐 (quiz.py 가 404 → 앱은 퀴즈만 끝냄)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 8-3 · 8-4 · 9-6
# ═══════════════════════════════════════════════════════════════

import random
import re
import secrets
import threading
import time
from pathlib import Path

import config

BASE_DIR = Path(__file__).resolve().parent.parent
QUIZ_MODE = getattr(config, "QUIZ_MODE", "voice")
LISTEN_SEC = getattr(config, "LISTEN_SEC", 7)
REPEAT_MIN_SCORE = getattr(config, "REPEAT_MIN_SCORE", 0.8)
VOICE_QUIZ_DIR = Path(getattr(config, "VOICE_QUIZ_DIR", BASE_DIR / "knowledge" / "voice_quiz"))
QUIZ_KEEP_SEC = 10 * 60  # 답이 안 온 문제는 10분 뒤 지움 (메모리가 쌓이지 않게)

FALLBACK_SENTENCES = ["졸리면 쉬어 가겠습니다", "안전 운전이 최우선입니다", "창문을 열고 환기하겠습니다"]

_quizzes = {}       # quiz_id → 문제 (정답 포함, 서버에만)
_last_sentence = {}  # user_id → 마지막으로 낸 따라 말하기 문장 (연달아 같은 문장 안 나오게)
_lock = threading.Lock()
_sentences = None


# ───────────────────────────────────────────────
# 출제
# ───────────────────────────────────────────────
def _load_sentences():
    global _sentences
    if _sentences is None:
        path = VOICE_QUIZ_DIR / "repeat_sentences.txt"
        try:
            lines = path.read_text(encoding="utf-8").splitlines()
            _sentences = [s.strip() for s in lines if s.strip() and not s.lstrip().startswith("#")]
        except OSError:
            _sentences = []
        if not _sentences:
            print(f"[voice_quiz] 문장 파일이 없거나 비어서 기본 문장 사용: {path}")
            _sentences = FALLBACK_SENTENCES
    return _sentences


SINO_DIGITS = "영일이삼사오육칠팔구"


def to_korean_number(n):
    """0~999 → 한자어 읽기 ('이십삼'). TTS 가 '23' 을 '스물셋'으로 읽는 일을 막으려고 글자로 넘긴다."""
    if n == 0:
        return "영"
    out = ""
    for unit, name in ((100, "백"), (10, "십")):
        d, n = divmod(n, unit)
        if d:
            out += ("" if d == 1 else SINO_DIGITS[d]) + name
    return out + (SINO_DIGITS[n] if n else "")


def _make_add():
    """받아올림 없는 두 자리 + 두 자리 (예: 23 + 45). 일의 자리는 1~8 이라 '이십 더하기 삼십' 같은 쉬운 문제는 안 나옴."""
    t1 = random.randint(1, 8)
    t2 = random.randint(1, 9 - t1)
    u1 = random.randint(1, 8)
    u2 = random.randint(1, 9 - u1)
    a, b = t1 * 10 + u1, t2 * 10 + u2
    if random.random() < 0.5:
        a, b = b, a
    return a, b


def _choices(answer):
    """(부품 B) 보기 4개 — 정답 + 헷갈리기 쉬운 오답 3개 (±1, ±10, 자리 바꿈)."""
    pool = {answer + 1, answer - 1, answer + 10, answer - 10, int(str(answer)[::-1])}
    pool = [x for x in pool if 10 <= x <= 99 and x != answer]
    picks = random.sample(pool, 3) if len(pool) >= 3 else pool
    out = picks + [answer]
    random.shuffle(out)
    return out


def _cleanup(now):
    for qid in [q for q, v in _quizzes.items() if now - v["created_at"] > QUIZ_KEEP_SEC]:
        del _quizzes[qid]


def make_quiz(user_id, qtype=None, event_id=None):
    """운전 중 음성 퀴즈 1문제. qtype 을 주면 같은 유형의 새 문제 (두 번째 기회).

    user_id  : 기사 번호
    qtype    : None(랜덤) / "repeat" / "add"
    event_id : 이 퀴즈가 붙을 경고 번호 (detect.py 가 경고를 저장한 뒤 넘김 — 결과를 그 보고서에 붙이기 위해)
    """
    if QUIZ_MODE == "screen":  # 부품 B: STT 가 없으니 덧셈 보기 고르기만
        qtype = "add"
    first = qtype is None
    qtype = qtype if qtype in ("repeat", "add") else random.choice(["repeat", "add"])
    intro = "잠을 깨워 볼게요. " if first else ""

    if qtype == "repeat":
        sentences = _load_sentences()
        last = _last_sentence.get(user_id)
        sentence = random.choice([s for s in sentences if s != last] or sentences)
        _last_sentence[user_id] = sentence
        answer, display = sentence, sentence
        speak = f"{intro}따라 말하세요. {sentence}."
    else:
        a, b = _make_add()
        answer, display = a + b, f"{a} + {b} = ?"
        ask = "화면에서 답을 골라 주세요." if QUIZ_MODE == "screen" else "답을 말해 주세요."
        speak = f"{intro}{to_korean_number(a)} 더하기 {to_korean_number(b)}. {ask}"  # 기획안 8-3: 조사 없이

    quiz = {"quiz_id": "", "type": qtype, "speak": speak, "display": display, "listen_sec": LISTEN_SEC}
    if QUIZ_MODE == "screen":
        quiz["choices"] = _choices(answer)

    now = time.time()
    with _lock:
        _cleanup(now)
        quiz_id = f"q_{secrets.token_hex(3)}"
        while quiz_id in _quizzes:
            quiz_id = f"q_{secrets.token_hex(3)}"
        quiz["quiz_id"] = quiz_id
        _quizzes[quiz_id] = {"quiz_id": quiz_id, "user_id": user_id, "type": qtype, "event_id": event_id,
                             "attempt": 1 if first else 2, "display": display, "answer": answer, "created_at": now}
    return quiz


def get_quiz(quiz_id):
    """채점 전 문제 정보 (정답 빼고). 없거나 이미 채점했으면 None → quiz.py 가 404."""
    with _lock:
        q = _quizzes.get(quiz_id)
        return {k: v for k, v in q.items() if k != "answer"} if q else None


# ───────────────────────────────────────────────
# 채점
# ───────────────────────────────────────────────
def _normalize_text(text):
    """공백 · 문장부호 제거 ('쉬어 가겠습니다.' = '쉬어가겠습니다')."""
    return re.sub(r"[^0-9A-Za-z가-힣]", "", str(text or ""))


def _edit_distance(a, b):
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def repeat_score(expected, answer_text):
    """기획안 8-4: 1 − (편집 거리 ÷ 제시 문장 글자 수). 문장을 통째로 말했으면(앞뒤 군말 포함) 1."""
    exp, ans = _normalize_text(expected), _normalize_text(answer_text)
    if not exp or not ans:
        return 0.0
    if exp in ans:
        return 1.0
    return max(0.0, 1 - _edit_distance(exp, ans) / len(exp))


# 한글 숫자 낱말 (긴 것부터 맞춰 봄 — '일곱' 을 '일' 로 읽지 않게)
NATIVE_TENS = {"스물": 20, "서른": 30, "마흔": 40, "쉰": 50, "예순": 60, "일흔": 70, "여든": 80, "아흔": 90, "열": 10}
NATIVE_UNITS = {"하나": 1, "둘": 2, "셋": 3, "넷": 4, "다섯": 5, "여섯": 6, "일곱": 7, "여덟": 8, "아홉": 9}
SINO_UNITS = {"십": 10, "백": 100}
TOKENS = sorted([(w, "ntens", v) for w, v in NATIVE_TENS.items()] + [(w, "nunit", v) for w, v in NATIVE_UNITS.items()]
                + [(w, "unit", v) for w, v in SINO_UNITS.items()]
                + [(c, "digit", i) for i, c in enumerate(SINO_DIGITS) if i], key=lambda t: -len(t[0]))


def extract_numbers(text):
    """말 속의 숫자를 모두 꺼낸다: '68' · '육십팔' · '예순여덟' · '60팔' → 68.

    숫자가 아닌 글자에서 끊고, '팔이요' 처럼 숫자 글자가 조사로 붙으면(한 자리 뒤 한 자리) 새 숫자로 본다.
    """
    s = _normalize_text(text)
    found, total, cur, last, i = [], 0, 0, None, 0

    def close():
        nonlocal total, cur, last
        if last is not None:
            found.append(total + cur)
        total, cur, last = 0, 0, None

    while i < len(s):
        m = re.match(r"\d+", s[i:])
        if m:
            n = int(m.group(0))
            if last not in (None, "unit"):  # '육십8' 만 이어 붙이고 나머지는 새 숫자
                close()
            total += n
            last = "arabic0" if n % 10 == 0 else "arabic"  # '60팔' 은 이어 붙이고, '68이요' 의 '이' 는 새 숫자
            i += len(m.group(0))
            continue
        for word, kind, value in TOKENS:
            if s.startswith(word, i):
                break
        else:
            close()
            i += 1
            continue
        if kind == "digit":
            if last in ("digit", "nunit", "arabic"):
                close()
            cur, last = value, "digit"
        elif kind == "unit":
            if last in ("nunit", "ntens", "arabic", "arabic0"):
                close()
            total += (cur or 1) * value
            cur, last = 0, "unit"
        elif kind == "ntens":
            if last not in (None,):
                close()
            total, last = value, "ntens"
        else:  # nunit
            if last in ("digit", "nunit", "unit", "arabic"):
                close()
            cur, last = value, "nunit"
        i += len(word)
    close()
    return found


def parse_answer_number(text):
    """덧셈 답 꺼내기: 말 속 숫자 중 마지막 두 자리 이상 수.

    답은 항상 22 이상 → 조사에서 생긴 한 자리('육십팔이요' 의 '이')와 문제를 따라 읽은 수('이십삼 더하기 사십오는 육십팔')를 거른다.
    """
    nums = [n for n in extract_numbers(text) if n >= 10]
    return nums[-1] if nums else None


def check_answer(quiz_id, answer_text):
    """채점 → passed (bool). 무응답('')은 실패. 채점한 문제는 지운다 (같은 문제를 두 번 채점하지 않게).

    없는 quiz_id (이미 채점했거나 서버 재시작) 면 KeyError → quiz.py 가 404.
    """
    with _lock:
        q = _quizzes.pop(quiz_id, None)
    if q is None:
        raise KeyError(f"없는 퀴즈입니다: {quiz_id}")
    if q["type"] == "repeat":
        return repeat_score(q["answer"], answer_text) >= REPEAT_MIN_SCORE
    return parse_answer_number(answer_text) == q["answer"]


if __name__ == "__main__":
    # 직접 확인: (sleep_detector_api 폴더에서) python -m services.voice_quiz_service
    for t in ("repeat", "add"):
        q = make_quiz(1, t)
        print(q)
    print(extract_numbers("이십삼 더하기 사십오는 육십팔이요"), parse_answer_number("육십팔이요"))
