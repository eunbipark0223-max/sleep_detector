# ═══════════════════════════════════════════════════════════════
# routers/rest_area.py — 졸음쉼터 실제 도로 거리 (POST /rest-areas/road-distance)
# ═══════════════════════════════════════════════════════════════
# 담당: B   |   우선: P2
# 수업 원본: (없음, 🔴 신규 — chat.py 와 같은 모양: 로그인 필요 · 무거운 일은 run_in_threadpool)
#
# [이 파일이 하는 일]
#   - 앱(lib/services/rest_area_service.dart)이 직선 거리로 고른 쉼터 몇 곳 + 내 위치 → 도로 거리 · 시간
#   - 실제 계산은 services/route_distance_service.py (카카오모빌리티 자동차 길찾기, 키는 서버 .env 에만)
#
# [요청 · 응답]
#   POST /rest-areas/road-distance
#     {"lat": 37.5, "lng": 127.1, "destinations": [{"key": "태인 졸음쉼터|35.7|127.0", "lat": 35.7, "lng": 127.0}, ...]}
#   → {"available": true, "results": {"태인 졸음쉼터|35.7|127.0": {"distance_m": 13900, "duration_s": 720}, ...}}
#     available = 서버에 키가 있는지. 못 구한 쉼터는 results 에 없음 → 앱은 직선 거리로
# ═══════════════════════════════════════════════════════════════

from typing import List

from fastapi import APIRouter, Depends
from fastapi.concurrency import run_in_threadpool
from pydantic import BaseModel, Field

from auth.jwt import get_current_user
from models.models import User
from services import route_distance_service

router = APIRouter(prefix="/rest-areas", tags=["rest-areas"])


class RouteDestination(BaseModel):
    key: str = Field(..., max_length=200)
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)


class RoadDistanceRequest(BaseModel):
    lat: float = Field(..., ge=-90, le=90)
    lng: float = Field(..., ge=-180, le=180)
    destinations: List[RouteDestination] = Field(..., max_length=route_distance_service.MAX_DESTINATIONS)


@router.post("/road-distance")
async def road_distance(body: RoadDistanceRequest, user: User = Depends(get_current_user)):
    """내 위치 → 쉼터들까지 자동차 도로 거리 · 시간. 키가 없거나 실패하면 빈 결과 (앱은 직선 거리)."""
    dests = [d.model_dump() for d in body.destinations]
    results = await run_in_threadpool(route_distance_service.road_distances, body.lat, body.lng, dests)
    return {"available": route_distance_service.available(), "results": results}
