# ═══════════════════════════════════════════════════════════════
# notebooks/rest_areas_json.py — 전국졸음쉼터표준데이터 CSV → 앱 assets/rest_areas.json
# ═══════════════════════════════════════════════════════════════
# 담당: B (지도)  |  우선: P2
#
# [하는 일]
#   공공데이터포털 「전국졸음쉼터표준데이터」 CSV 에서 지도에 쓸 열만 뽑아 JSON 으로 저장
#   → sleep_detector_app/assets/rest_areas.json (map_screen.dart 가 읽음, 인터넷 · API 키 없이 동작)
#
# [실행] (파이썬 표준 라이브러리만 씀)
#   python notebooks\rest_areas_json.py <내려받은 CSV 경로>
#
# [규칙]
#   - 열 이름으로 찾는다 (졸음쉼터명 · 위도 · 경도 · 도로노선명 · 도로노선방향 · 소재지도로명주소 · 주차 · 화장실 · 데이터기준일자)
#   - 위도 · 경도가 비었거나 한국 밖이면 버린다 (버린 줄 수를 출력)
#   - 이름에 '쉼터' 가 없으면 ' 졸음쉼터' 를 붙이고, 방향 'A기점 + B종점' 은 'B방향' 으로 (포털 2026-02 데이터 형식)
#   - 데이터를 새로 받으면 이 스크립트를 다시 돌려 파일만 바꾸면 됨
#   - 출처: 공공데이터포털 「전국졸음쉼터표준데이터」 (공공누리 · 이용 허락 범위 안에서 사용)
# ═══════════════════════════════════════════════════════════════

import csv
import json
import os
import re
import sys

OUT = os.path.join(os.path.dirname(__file__), '..', 'sleep_detector_app', 'assets', 'rest_areas.json')

# 앱 JSON 키 → CSV 열 이름 후보 (앞에 있는 것부터)
COLS = {
    'name': ['졸음쉼터명'],
    'lat': ['위도'],
    'lng': ['경도'],
    'road': ['도로노선명', '도로명'],
    'direction': ['도로노선방향', '방향'],
    'address': ['소재지도로명주소', '소재지지번주소'],
    'parking': ['주차면수', '주차가능대수', '주차'],
    'toilet': ['화장실유무', '화장실'],
    'date': ['데이터기준일자'],
}


def read_rows(path):
    for enc in ('utf-8-sig', 'cp949'):          # 포털 CSV 는 cp949 인 경우가 많음
        try:
            with open(path, encoding=enc, newline='') as f:
                return list(csv.DictReader(f))
        except UnicodeDecodeError:
            continue
    sys.exit(f'글자 인코딩을 읽지 못함: {path}')


def pick(header):
    """앱 키 → 실제 CSV 열 이름 (공백 무시, 후보 이름이 들어 있는 첫 열)"""
    found = {}
    for key, names in COLS.items():
        for n in names:
            hit = next((h for h in header if n in h.replace(' ', '')), None)
            if hit:
                found[key] = hit
                break
    missing = [k for k in ('name', 'lat', 'lng') if k not in found]
    if missing:
        sys.exit(f'꼭 필요한 열이 없음: {missing} / CSV 열: {header}')
    return found


def main():
    if len(sys.argv) != 2:
        sys.exit('python notebooks\\rest_areas_json.py <CSV 경로>')
    rows = read_rows(sys.argv[1])
    col = pick(list(rows[0].keys()))
    out, bad = [], 0
    for r in rows:
        try:
            lat, lng = float(r[col['lat']]), float(r[col['lng']])
        except (TypeError, ValueError):
            bad += 1
            continue
        if not (33 <= lat <= 39 and 124 <= lng <= 132):   # 한국 범위 밖 (위도 · 경도가 바뀌어 적힌 줄 등)
            bad += 1
            continue
        item = {k: (r.get(c) or '').strip() for k, c in col.items() if k not in ('lat', 'lng')}
        item.update(lat=round(lat, 6), lng=round(lng, 6))
        if '쉼터' not in item['name']:                    # 포털 이름은 '태인' 처럼 지명만 → '태인 졸음쉼터'
            item['name'] += ' 졸음쉼터'
        m = re.fullmatch(r'\S+기점\s*\+\s*(\S+)종점', item.get('direction', ''))
        if m:                                             # '서울기점 + 부산종점' → '부산방향' (가는 쪽 = 종점)
            item['direction'] = f'{m.group(1)}방향'
        out.append(item)

    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, 'w', encoding='utf-8') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    dates = sorted({o.get('date', '') for o in out} - {''})
    print(f'저장: {os.path.normpath(OUT)} · 쉼터 {len(out)}곳 · 버린 줄 {bad}')
    print('쓴 열:', col)
    print('데이터 기준일:', dates[-1] if dates else '(없음)')


if __name__ == '__main__':
    main()
