# ═══════════════════════════════════════════════════════════════
# tools/kpi4_rag.py — KPI ④ RAG 효과 (같은 질문: LLM만 vs LLM + RAG)
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2 (KPI ④, 선택)   |   서버 코드가 아니라 PC 에서 돌리는 시험 도구
#
# [설계 — 돌리기 전에 정해 둔 것 (11/02, 첫 시험의 편향을 고침)]
#   1. 질문 (tools/kpi4_questions.csv): 자료(knowledge/)를 보고 만든 질문은 쓰지 않음 — RAG 에 유리해짐
#      · app  : 앱 규정 도우미 예시 질문 4개 (실제 사용자가 누르는 질문) — a3 는 11/04 지시문 조정에 써서 집계 제외 (exclude 칸)
#      · team : 팀원이 knowledge/ 를 보지 않고 '기사라면 물어볼 질문' 을 쓴 것 (6개 이상)
#      · 돌리기 전에 B 가 질문마다 answerable(yes / no) · gold(정답 법령 · 조항, law.go.kr 로 확인) · key_facts 를 채움
#        answerable = knowledge/ 문서로 답할 수 있나 → '자료 범위' 지표 (RAG 가 답할 수 있는 질문 비율)
#   2. 조건: 같은 모델 · 같은 온도 · 같은 지시문. 다른 것은 '근거 문서가 있나' 하나뿐
#      · LLM + RAG = 실제 규정 도우미 그대로 (chat_service.answer — 검색 → 근거 안에서만 답 → 숫자 검사)
#      · LLM만 = chat_service.SYSTEM_PROMPT 에서 [근거] 를 '네가 아는 법령' 으로만 바꾼 지시문 (모르면 '확인되지 않습니다' 도 같게)
#   3. 반복: 질문마다 조건별 3번 (같은 질문도 답이 달라짐 → 평균과 범위)
#   4. 채점은 사람이, 정해 둔 기준으로, 어느 조건 답인지 모르게 (review.csv — 순서를 섞고 [1] 같은 출처 번호를 지움)
#      verdict (한 칸):
#        correct  — 자료로 답할 수 있는 질문: 핵심 사실 맞음 + 틀린 사실 없음 + 근거 조항이 맞음
#                   자료에 없는 질문: 실제 법령으로 맞게 답함 (LLM만이 이길 수 있는 경우 — 그대로 인정)
#        partial  — 사실은 맞는데 조항이 없거나 틀림, 또는 핵심 사실 일부 빠짐
#        wrong    — 틀린 사실이 있음
#        refused  — '확인되지 않습니다' 처럼 답을 안 함 (자료에 없는 질문이면 안전한 답)
#      made_up (0/1) — 존재하지 않는 법령 · 조항을 댐 (law.go.kr 로 확인. 실제로 있는 조항이면 자료 밖이라도 0)
#      hint_articles 칸은 답에 적힌 '제○조' 를 뽑아 둔 것 — 확인을 돕는 참고일 뿐 채점이 아님
#   5. 지표 (summarize): 조건별 · 질문 출처별 — 정답률 · 지어낸 조항 비율 · 모름 비율, 3번의 평균과 최소~최대
#
# [실행] (sleep_detector_api 폴더, .env 의 GEMINI_API_KEY 필요 · 질문 N개 × 2조건 × 3번 호출 + 임베딩)
#   venv\Scripts\python tools/kpi4_rag.py check                    질문 파일 확인 (빈칸 · gold 안 채운 것)
#   venv\Scripts\python tools/kpi4_rag.py run --out D:\kpi4        → answers.csv · review.csv(채점용) · key.csv(정답 조건)
#   (review.csv 의 verdict · made_up 을 채운 뒤)
#   venv\Scripts\python tools/kpi4_rag.py summarize --out D:\kpi4
#   - 결과 파일은 저장소 밖 폴더에 (--out)
#
# 자세한 내용: 「파이널 프로젝트 최종 기획안 10.13」 KPI ④ · 6-2 RAG · knowledge/README.md
# ═══════════════════════════════════════════════════════════════
import argparse
import csv
import os
import random
import re
import sys
import time

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)
os.chdir(BASE)

QUESTIONS_CSV = os.path.join(BASE, "tools", "kpi4_questions.csv")
RUNS = 3
SEED = 0
VERDICTS = ("correct", "partial", "wrong", "refused")
ARTICLE = re.compile(r"제\s*\d+\s*조(?:\s*의\s*\d+)?")
CITE_NO = re.compile(r"\s*\[\d+(?:\s*,\s*\d+)*\]")


def _excluded(r):
    """exclude 칸에 이유가 있으면 집계에서 뺌 (예: a3 — 11/04 이 질문으로 chat_service 지시문을 고침 → 시험 질문이 아님)"""
    return bool((r.get("exclude") or "").strip())


def load_questions():
    rows = list(csv.DictReader(open(QUESTIONS_CSV, encoding="utf-8-sig")))
    return [r for r in rows if r["question"].strip() and not _excluded(r)]


def check():
    rows = list(csv.DictReader(open(QUESTIONS_CSV, encoding="utf-8-sig")))
    empty = [r["id"] for r in rows if not r["question"].strip()]
    skipped = [f"{r['id']}({r['exclude'].strip()})" for r in rows if _excluded(r)]
    if skipped:
        print(f"집계 제외: {', '.join(skipped)}")
    qs = [r for r in rows if r["question"].strip() and not _excluded(r)]
    no_label = [r["id"] for r in qs if r["answerable"].strip() not in ("yes", "no")]
    no_gold = [r["id"] for r in qs if r["answerable"].strip() == "yes" and not r["gold"].strip()]
    print(f"질문 {len(qs)}개 (출처: {', '.join(sorted({r['source'] for r in qs}))}) · 빈 질문 {empty or '없음'}")
    print(f"answerable 안 채움: {no_label or '없음'} · yes 인데 gold 없음: {no_gold or '없음'}")
    ok = not no_label and not no_gold
    print("→ run 해도 됨" if ok else "→ 돌리기 전에 채우기 (질문 · answerable · gold 는 돌리기 전에 정해 둠)")
    return ok


def llm_only_prompt():
    """chat_service.SYSTEM_PROMPT 와 같은 역할 · 길이 · 출처 · 모름 규칙. 다른 것은 [근거] 대신 '네가 아는 법령' 하나"""
    from services import chat_service
    p = chat_service.SYSTEM_PROMPT
    p = p.replace("아래 [근거]에 있는 내용만 사용해", "네가 알고 있는 한국 법령 지식으로")
    p = p.replace("각 근거에는 유형(법령 / 일반 자료)이 표시되어 있다. ", "")
    p = p.replace("답에 쓴 근거는 문장 끝에만 [출처 번호]로 표시하고, '[1]에 따르면'처럼 문장 앞에는 쓰지 마라.",
                  "답에 쓴 근거는 문장 끝에 법령 이름과 조항 번호로 표시하라.")
    p = p.replace("숫자는 근거에 적힌 그대로 쓰고", "숫자는 법령에 적힌 그대로 쓰고")
    p = p.replace("근거가 질문의 대상과 다른 대상에 관한 것이면 그 근거를 대신 적용하지 마라. ",
                  "질문의 대상과 다른 대상에 관한 법령을 대신 적용하지 마라. ")
    p = p.replace("질문이 묻는 규정이나 통계가 [근거]에 없으면", "질문이 묻는 규정이나 통계를 확실히 알지 못하면")
    assert "[근거]" not in p, "SYSTEM_PROMPT 가 바뀜 — llm_only_prompt 를 다시 맞추기"
    return p


def run(out):
    if not check():
        raise SystemExit(1)
    from services import chat_service, llm_service
    if not llm_service.USE_REAL_AI:
        raise SystemExit("USE_REAL_AI 가 꺼져 있음 (.env 의 GEMINI_API_KEY 확인)")
    os.makedirs(out, exist_ok=True)
    prompt = llm_only_prompt()
    qs = load_questions()
    answers = []
    for k in range(1, RUNS + 1):
        for q in qs:
            a1 = chat_service._real_answer([{"role": "system", "content": prompt}, {"role": "user", "content": q["question"]}])
            time.sleep(2)  # 무료 한도
            r = chat_service.answer(q["question"])
            time.sleep(2)
            answers.append(dict(id=q["id"], run=k, cond="llm", answer=a1, is_real=True, cited=""))
            answers.append(dict(id=q["id"], run=k, cond="rag", answer=r["answer"], is_real=r["is_real"],
                                cited=" | ".join(s["title"] for s in r["sources"])))
            print(f"{k}회 {q['id']} 완료", flush=True)
    write(os.path.join(out, "answers.csv"), answers)

    # 채점용: 순서를 섞고, 어느 조건인지 숨김 (출처 번호 [1] 도 지움 — RAG 답인 티가 남)
    byq = {q["id"]: q for q in qs}
    order = list(range(len(answers)))
    random.Random(SEED).shuffle(order)
    review, key = [], []
    for n, i in enumerate(order, 1):
        a, q = answers[i], byq[answers[i]["id"]]
        text = CITE_NO.sub("", a["answer"])
        review.append(dict(rid=n, id=q["id"], question=q["question"], answerable=q["answerable"], gold=q["gold"],
                           key_facts=q["key_facts"], answer=text,
                           hint_articles=";".join(sorted({re.sub(r"\s+", "", m) for m in ARTICLE.findall(text)})),
                           verdict="", made_up="", note=""))
        key.append(dict(rid=n, cond=a["cond"], run=a["run"], is_real=a["is_real"]))
    write(os.path.join(out, "review.csv"), review)
    write(os.path.join(out, "key.csv"), key)
    print(f"\n→ {out}\\review.csv 의 verdict({' / '.join(VERDICTS)}) · made_up(0/1) 채우기 — key.csv 는 채점 끝날 때까지 열지 않기")


def write(path, rows):
    with open(path, "w", newline="", encoding="utf-8-sig") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)


def summarize(out):
    review = {r["rid"]: r for r in csv.DictReader(open(os.path.join(out, "review.csv"), encoding="utf-8-sig"))}
    key = list(csv.DictReader(open(os.path.join(out, "key.csv"), encoding="utf-8-sig")))
    src = {q["id"]: q["source"] for q in load_questions()}
    bad = [rid for rid, r in review.items() if r["verdict"].strip() not in VERDICTS or r["made_up"].strip() not in ("0", "1")]
    if bad:
        raise SystemExit(f"채점 안 된 줄 {len(bad)}개 (rid {bad[:10]} …) — verdict · made_up 채우기")
    rows = [dict(review[k["rid"]], cond=k["cond"], run=int(k["run"]), source=src.get(review[k["rid"]]["id"], "?")) for k in key]

    def rate(rs, test):
        """3번 각각의 비율 → '평균% (최소~최대)'"""
        per = []
        for k in range(1, RUNS + 1):
            sub = [r for r in rs if r["run"] == k]
            if sub:
                per.append(sum(test(r) for r in sub) / len(sub))
        if not per:
            return "-"
        return f"{sum(per) / len(per):.0%} ({min(per):.0%}~{max(per):.0%})"

    groups = [("전체", lambda r: True), ("자료로 답할 수 있는 질문", lambda r: r["answerable"] == "yes"),
              ("자료에 없는 질문", lambda r: r["answerable"] == "no")]
    groups += [(f"출처 {s}", (lambda s: lambda r: r["source"] == s)(s)) for s in sorted({r["source"] for r in rows})]
    qs = load_questions()
    print(f"질문 {len(qs)}개 · 자료 범위(자료로 답할 수 있는 질문) {sum(q['answerable'] == 'yes' for q in qs)}/{len(qs)} · {RUNS}번씩\n")
    print("| 묶음 | 지표 | LLM만 | LLM + RAG |\n|---|---|---|---|")
    for name, f in groups:
        for label, test in (("정답", lambda r: r["verdict"] == "correct"), ("지어낸 조항", lambda r: r["made_up"] == "1"),
                            ("모름", lambda r: r["verdict"] == "refused")):
            llm = rate([r for r in rows if r["cond"] == "llm" and f(r)], test)
            rag = rate([r for r in rows if r["cond"] == "rag" and f(r)], test)
            print(f"| {name} | {label} | {llm} | {rag} |")


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("step", choices=["check", "run", "summarize"])
    ap.add_argument("--out", default=r"D:\kpi4", help="결과 폴더 (저장소 밖)")
    a = ap.parse_args()
    {"check": check, "run": lambda: run(a.out), "summarize": lambda: summarize(a.out)}[a.step]()
