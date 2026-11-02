# ═══════════════════════════════════════════════════════════════
# tools/phone_drive_wandb.py — 시연 폰 실시간 시험 로그 → 차례별 요약표 → W&B (eye-kpi1 / a_phone_drive)
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P1 (실험 기록 — 강사님 요청 · 10/29 팀장 공지)   |   서버 코드가 아니라 PC 에서 돌리는 도구
#
# [실행] (sleep_detector_api 폴더, 시스템 Python — pandas · wandb 필요, 한글 사용자 폴더면 PYTHONUTF8=1)
#   1. 폰: flutter run -t lib/tools/eye_live_main.dart → [다음 단계] 버튼 누르며 시험
#   2. PC: adb logcat -d -s flutter -v raw > <로그 폴더>/r1_1.5s.txt  (차례마다 파일 하나, 이름은 ROUNDS 와 같게)
#   3. python tools/phone_drive_wandb.py <로그 폴더> --dry   → 표만 확인
#      python tools/phone_drive_wandb.py <로그 폴더>         → W&B 에 올림 (wandb login 먼저)
#
# [주의]
#   - 로그에는 숫자 · 글자만 (얼굴 사진 없음). 로그 파일은 GitHub 에 올리지 않고 드라이브에만
# ═══════════════════════════════════════════════════════════════
"""시연 폰 실시간 시험 로그 (tools/eye_live_main.dart) → 시험별 요약 → W&B eye-kpi1 / a_phone_drive
   로그에는 숫자 · 글자만 있음 (사진 없음). 사용: python phone_drive_wandb.py <로그 폴더> [--dry]"""
import re, sys, os
import pandas as pd

D = sys.argv[1]
DRY = '--dry' in sys.argv
# 시험 차례 → (로그 파일, 고개 규칙, 떨구기 시험이 들어 있는 단계)
ROUNDS = [
    ('1차', 'r1_1.5s.txt',        '숙임 = 감김 (1.5초)', 4),
    ('2차', 'r2_3s.txt',          '숙임 3초 · PERCLOS 눈만', 4),
    ('3차', 'r3_3s_nullfix.txt',  '+ 눈 확률 없는 프레임으로 숙임 시작 안 함', 7),
    ('4차', 'r4_3s_grace.txt',    '+ 0.5초 들어야 숙임 리셋', 7),
]

def parse(path):
    ev, st, step = [], [], 0
    for l in open(path, encoding='utf-8'):
        m = re.search(r'\] ([\d.]+)s (.*)', l)
        if not m:
            continue
        t, s = float(m[1]), m[2]
        if s.startswith('=='):
            step = int(re.search(r'== (\d)', s)[1]); ev.append((t, step, 'step', s)); continue
        if s.startswith('상태'):
            p = re.search(r'확률 ([\d.]+|모름)', s)[1]; d = re.search(r'숙인 정도 (-?[\d.]+|-)', s)[1]
            st.append((t, step, None if p == '모름' else float(p), None if d == '-' else float(d), s.endswith('숙임')))
        elif '🚨' in s:
            ev.append((t, step, 'perclos' if 'perclos' in s else 'microsleep', s))
        elif '📷' in s:
            ev.append((t, step, 'camera', s))
    return ev, st

def spans(st, step):
    out, cur = [], None
    for t, s, p, d, down in st:
        if s == step and down:
            if cur is None: cur = [t, t, 0.0]
            cur[1] = t; cur[2] = max(cur[2], d or 0)
        elif cur:
            out.append(cur); cur = None
    if cur: out.append(cur)
    return [(a, b, b - a + 0.5, m) for a, b, m in out]   # 상태 줄이 0.5초 간격 → +0.5

rows = []
for name, f, rule, drop_step in ROUNDS:
    ev, st = parse(os.path.join(D, f))
    alarms = [e for e in ev if e[2] in ('microsleep', 'perclos')]
    def first(step, kinds):
        start = next((t for t, s, k, _ in ev if k == 'step' and s == step), None)
        hit = next((t for t, s, k, _ in ev if s == step and k in kinds), None)
        return start, hit
    s2, h2 = first(2, ('microsleep',))
    dash = spans(st, 6)
    dash_alarm = sum(1 for e in alarms if e[1] == 6)
    drop = spans(st, drop_step)
    drop_sp = max(drop, key=lambda x: x[2]) if drop else None
    drop_hit = next((t for t, s, k, _ in ev if k == 'microsleep' and drop_sp and drop_sp[0] - 0.5 <= t <= drop_sp[1] + 1.0), None)
    cover = [k for t, s, k, _ in ev if s == 5 and k != 'step']
    rows.append({
        '시험': name, '고개 규칙': rule,
        '눈 감기 단계 시작 → 미세수면(초)': round(h2 - s2, 1) if h2 and s2 else None,
        '계기판 보기 횟수': len(dash), '계기판 최대 길이(초)': round(max((x[2] for x in dash), default=0), 1),
        '계기판 괜한 경고': dash_alarm,
        '떨구기 길이(초)': round(drop_sp[2], 1) if drop_sp else None,
        '떨구기 → 경고(초)': round(drop_hit - drop_sp[0], 1) if drop_hit and drop_sp else None,
        '떨구기 최대 숙임(°)': round(drop_sp[3], 1) if drop_sp else None,
        '얼굴 가리기 결과': cover[0] if cover else '없음',
        '전체 경고 수': len(alarms),
    })

T = pd.DataFrame(rows)
pd.set_option('display.width', 250)
print(T.to_string(index=False))
if DRY:
    sys.exit()

import wandb
run = wandb.init(project='eye-kpi1', name='a_phone_drive', group='phone',
                 config=dict(phone='Galaxy S10 (SM-G977N)', camera='front ResolutionPreset.medium 720x480 nv21',
                             fps='10~12 (ML Kit 62~83ms)', eye_closed_prob=0.25, closed_sec=1.5,
                             head_down_deg=6.0, head_down_sec=3.0, head_up_reset_sec=0.5, head_base_sec=60,
                             test_tool='sleep_detector_app/lib/tools/eye_live_main.dart',
                             steps='1 정면 · 2 눈 감기 · 3 고개 숙이기 · 4 떨구기 · 5 얼굴 가리기 · 6 계기판 보기 · 7 깜빡이기'),
                 settings=wandb.Settings(console='off'))
wandb.log({'시연 폰 시험 (차례별)': wandb.Table(dataframe=T.astype(str))})
for i, r in T.iterrows():
    wandb.log({'차례': i + 1, '계기판 괜한 경고': r['계기판 괜한 경고'],
               '떨구기 → 경고(초)': r['떨구기 → 경고(초)'] if pd.notna(r['떨구기 → 경고(초)']) else -1,
               '계기판 최대 길이(초)': r['계기판 최대 길이(초)']})
last = T.iloc[-1]
wandb.summary.update({'최종/계기판 괜한 경고': int(last['계기판 괜한 경고']), '최종/떨구기 → 경고(초)': float(last['떨구기 → 경고(초)']),
                      '최종/얼굴 가리기': last['얼굴 가리기 결과'], '1차/계기판 괜한 경고': int(T.iloc[0]['계기판 괜한 경고'])})
print('W&B run:', run.url)
wandb.finish()
