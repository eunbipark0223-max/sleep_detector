# ═══════════════════════════════════════════════════════════════
# services/route_distance_service.py — 졸음쉼터까지 실제 도로 거리 · 시간 (카카오모빌리티 자동차 길찾기)
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2
# 수업 원본: (없음, 🔴 신규 — routers/admin.py 의 카카오 주소 변환과 같은 방식: requests + KakaoAK 키 + 짧은 timeout)
#
# [이 파일이 하는 일]
#   - 앱이 직선 거리로 고른 가까운 쉼터 몇 곳(최대 MAX_DESTINATIONS)만 받아서, 각각 자동차 길찾기로 도로 거리 · 시간을 묻는다
#   - 여러 곳을 동시에 물음 (스레드) · 전체 시간 제한 TOTAL_TIMEOUT_SEC — 경고 음성 안내가 늦어지지 않게
#   - 같은 출발 지점(소수 3자리 ≈ 100m) · 같은 쉼터는 CACHE_SEC 동안 다시 묻지 않음 (무료 쿼터 아끼기)
#
# [만들 것 (이름 약속 — routers/rest_area.py 가 이 이름으로 부름)]
#   - road_distances(origin_lat, origin_lng, destinations) → {key: {"distance_m": int, "duration_s": int}}
#       destinations: [{"key": str, "lat": float, "lng": float}, ...]
#       못 구한 쉼터는 결과에 없음 → 앱이 그 쉼터는 직선 거리로 둠
#   - available() → 키가 있어 실제로 물어볼 수 있는지
#
# [주의]
#   - 키: .env 의 KAKAO_API_KEY (카카오 REST API 키, 관리자 웹 주소 변환과 같은 키). 🔴 앱에 넣지 않는다 (서버만)
#   - 카카오 개발자 콘솔에서 '카카오모빌리티 자동차 길찾기' 사용 권한이 켜져 있어야 함 → 없으면 401/403 → 직선 거리로
#   - 비상업 용도는 무료 쿼터 안에서 사용 (상업 용도는 카카오모빌리티와 별도 제휴 필요 — devtalk 답변, 11/09 확인)
#   - 응답 모양: routes[0].result_code == 0 이면 routes[0].summary.distance(m) · duration(초) — 공식 문서 페이지를
#     열지 못해서 (11/09) 모양이 다르면 그 쉼터는 결과에서 빠지고 직선 거리로 넘어감
# ═══════════════════════════════════════════════════════════════

import os
import threading
import time
from concurrent.futures import ThreadPoolExecutor, wait

import requests
from dotenv import load_dotenv

load_dotenv()

DIRECTIONS_URL = "https://apis-navi.kakaomobility.com/v1/directions"
MAX_DESTINATIONS = 8        # 한 번에 물어보는 쉼터 수 (앱은 5곳)
PER_REQUEST_TIMEOUT_SEC = 3
TOTAL_TIMEOUT_SEC = 4       # 이 시간 안에 온 답만 씀
CACHE_SEC = 5 * 60

_cache = {}                 # (출발 lat, lng 소수 3자리, key) → (저장 시각, 결과 dict)
_lock = threading.Lock()
_pool = ThreadPoolExecutor(max_workers=MAX_DESTINATIONS, thread_name_prefix="route")


def _key():
    return os.getenv("KAKAO_API_KEY", "")


def available():
    return bool(_key())


def _ask(origin_lat, origin_lng, dest_lat, dest_lng):
    """자동차 길찾기 1번 → {"distance_m", "duration_s"} 또는 None (경로 없음 · 응답 모양이 다름)."""
    resp = requests.get(
        DIRECTIONS_URL,
        params={
            "origin": f"{origin_lng},{origin_lat}",          # 경도,위도 순서
            "destination": f"{dest_lng},{dest_lat}",
            "priority": "RECOMMEND",
            "summary": "true",                              # 경로 좌표는 필요 없음 (거리 · 시간만)
        },
        headers={"Authorization": f"KakaoAK {_key()}"},
        timeout=PER_REQUEST_TIMEOUT_SEC,
    )
    resp.raise_for_status()
    route = (resp.json().get("routes") or [{}])[0]
    summary = route.get("summary") or {}
    if route.get("result_code") != 0 or "distance" not in summary or "duration" not in summary:
        return None
    return {"distance_m": int(summary["distance"]), "duration_s": int(summary["duration"])}


def _safe_ask(origin_lat, origin_lng, dest):
    try:
        return _ask(origin_lat, origin_lng, dest["lat"], dest["lng"])
    except (requests.RequestException, ValueError, TypeError, KeyError) as e:
        print(f"[route] 길찾기 실패 {dest.get('key')}: {type(e).__name__}: {e}")
        return None


def road_distances(origin_lat, origin_lng, destinations):
    """쉼터별 도로 거리 · 시간. 키가 없거나 다 실패하면 빈 dict (앱은 직선 거리 그대로)."""
    if not available() or not destinations:
        return {}
    now = time.time()
    o = (round(origin_lat, 3), round(origin_lng, 3))
    out, todo = {}, []
    with _lock:
        for d in destinations[:MAX_DESTINATIONS]:
            hit = _cache.get((*o, d["key"]))
            if hit and now - hit[0] < CACHE_SEC:
                out[d["key"]] = hit[1]
            else:
                todo.append(d)
    futures = {_pool.submit(_safe_ask, origin_lat, origin_lng, d): d for d in todo}
    done, _ = wait(futures, timeout=TOTAL_TIMEOUT_SEC)
    with _lock:
        for f in done:
            result = f.result()
            if result:
                key = futures[f]["key"]
                out[key] = result
                _cache[(*o, key)] = (now, result)
    return out
