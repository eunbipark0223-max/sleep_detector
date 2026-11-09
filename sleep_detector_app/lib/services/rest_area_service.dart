// ═══════════════════════════════════════════════════════════════
// services/rest_area_service.dart — 가까운 졸음쉼터 찾기 (지도 화면 · 경고 음성 안내 공용)
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: (없음, 🔴 신규) — map_screen.dart 에 있던 쉼터 읽기 · 거리 계산을 다른 화면에서도 쓰게 뺀 것
//
// [이 파일이 하는 일]
//   - 공공데이터 '전국 졸음쉼터 표준데이터' (assets/rest_areas.json) 읽기 — 한 번 읽으면 앱이 꺼질 때까지 기억
//   - 내 위치에서 직선 거리로 가까운 n곳
//   - 🆕 (11/09) 도로 거리: 직선 거리로 8곳을 고른 뒤 서버(/rest-areas/road-distance → 카카오모빌리티 자동차 길찾기)에
//     도로 거리 · 시간을 물어 빨리 도착하는 순(시간 순)으로 다시 줄 세움. 서버 · 카카오가 안 되면 직선 거리 그대로
//     (반대편 차로 쉼터가 직선으로는 가깝게 보이던 문제를 줄임)
//   - 경고 음성 안내 문장: "가까운 태인 졸음쉼터, 천안방향, 약 14킬로미터, 약 12분" (도로 거리 없으면 분은 빠짐)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - nearestRestAreas(lat, lng, {n = 5}) → List<NearRestArea> (직선 거리 가까운 순, 데이터를 못 읽으면 빈 목록)
//   - nearestRestAreasByRoad(lat, lng, {n = 5}) → 빨리 도착하는 순 (도로 시간, 못 구하면 직선 거리 순)
//   - NearRestArea: area(RestArea) · km(직선) · roadKm · roadMin(도로, 없으면 null) · distanceText · voice
//   - 2단계 경고 음성 안내 (C 의 warning_screen):
//       final near = await nearestRestAreasByRoad(lat, lng, n: 1);
//       if (near.isNotEmpty) await VoiceService.speak(near.first.voice);
//
// [주의]
//   - 고속도로 쉼터는 방향이 있다 — 가장 가까운 곳이 반대편 차로일 수 있어서 문장 · 목록에 방향을 꼭 넣는다
//     (앱은 달리는 방향을 모름 — GPS 속도 · 방향은 쓰지 않기로 함, 기획안 5-3)
//   - 음성 문장은 'km' 대신 '킬로미터' 로 씀 (TTS 가 'km' 를 '케이엠' 으로 읽을 수 있어서)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import 'api_service.dart';

/// 졸음쉼터 한 곳 (assets/rest_areas.json 한 줄)
class RestArea {
  final String name;
  final String road; // 도로 노선 이름 (예: 경부선)
  final String direction; // 노선 방향 (예: 부산방향)
  final String address;
  final String toilet; // Y · N
  final double lat;
  final double lng;

  const RestArea({
    required this.name,
    required this.lat,
    required this.lng,
    this.road = '',
    this.direction = '',
    this.address = '',
    this.toilet = '',
  });

  factory RestArea.fromJson(Map<String, dynamic> json) => RestArea(
        name: '${json['name'] ?? ''}',
        lat: (json['lat'] as num).toDouble(),
        lng: (json['lng'] as num).toDouble(),
        road: '${json['road'] ?? ''}',
        direction: '${json['direction'] ?? ''}',
        address: '${json['address'] ?? ''}',
        toilet: '${json['toilet'] ?? ''}',
      );

  /// '경부선 · 부산방향' (빈 값은 뺌)
  String get roadText => [road, direction].where((s) => s.isNotEmpty).join(' · ');
}

/// 가까운 쉼터 한 곳 + 거리
class NearRestArea {
  final RestArea area;
  final double km; // 직선 거리
  final double? roadKm; // 도로 거리 (카카오 길찾기, 못 구하면 null)
  final int? roadMin; // 자동차로 걸리는 분 (못 구하면 null)

  const NearRestArea(this.area, this.km, {this.roadKm, this.roadMin});

  /// 도로 거리를 구했는지
  bool get hasRoad => roadKm != null;

  /// 정렬 · 안내에 쓰는 거리 — 도로 거리가 있으면 도로, 없으면 직선
  double get bestKm => roadKm ?? km;

  /// 목록 글자 — '도로 13.9km · 12분' 또는 '직선 9.3km'
  String get distanceText =>
      hasRoad ? '도로 ${roadKm!.toStringAsFixed(1)}km${roadMin == null ? '' : ' · $roadMin분'}' : '직선 ${km.toStringAsFixed(1)}km';

  /// 경고 음성 안내 문장 — "가까운 태인 졸음쉼터, 천안방향, 약 14킬로미터, 약 12분"
  /// (도로 거리를 못 구하면 직선 거리로 "약 12킬로미터"만)
  String get voice => [
        '가까운 ${area.name}',
        if (area.direction.isNotEmpty) area.direction,
        bestKm < 1 ? '1킬로미터 안' : '약 ${bestKm.round()}킬로미터',
        if (roadMin != null) '약 $roadMin분',
      ].join(', ');
}

/// 위도 · 경도
typedef LatLng = ({double lat, double lng});

/// 두 점 사이 직선 거리 (km, 하버사인)
double distanceKm(LatLng a, LatLng b) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(a.lat)) * math.cos(rad(b.lat)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.sqrt(h));
}

/// 주어진 목록에서 가까운 순 n곳 (지도 화면 · 시험에서 목록을 바꿔 끼울 때)
List<NearRestArea> nearestFrom(List<RestArea> all, LatLng me, {int n = 5}) {
  final withDist = [for (final a in all) NearRestArea(a, distanceKm(me, (lat: a.lat, lng: a.lng)))];
  withDist.sort((x, y) => x.km.compareTo(y.km));
  return withDist.take(n).toList();
}

List<RestArea>? _all;

/// 졸음쉼터 전체 목록 (assets/rest_areas.json, 처음 한 번만 읽음)
Future<List<RestArea>> loadRestAreas() async {
  if (_all != null) return _all!;
  final raw = jsonDecode(await rootBundle.loadString('assets/rest_areas.json')) as List;
  return _all = raw.map((e) => RestArea.fromJson(Map<String, dynamic>.from(e as Map))).toList();
}

/// 내 위치에서 가까운 순 n곳. 데이터를 못 읽으면 빈 목록 (경고 음성 안내는 건너뛰면 됨)
Future<List<NearRestArea>> nearestRestAreas(double lat, double lng, {int n = 5}) async {
  try {
    return nearestFrom(await loadRestAreas(), (lat: lat, lng: lng), n: n);
  } catch (_) {
    return [];
  }
}

/// 도로 거리를 물어볼 때 직선 거리로 먼저 고르는 후보 수 (서버 MAX_DESTINATIONS 와 같게)
const int roadCandidates = 8;

/// 서버에 도로 거리를 묻는 함수 모양 — 기본은 ApiService.fetchRoadDistances (시험 · 미리보기에서 바꿔 끼움)
typedef RoadDistanceFetcher = Future<Map<String, dynamic>> Function(
    double lat, double lng, List<Map<String, dynamic>> destinations);

/// 쉼터를 서버 요청에서 구분하는 이름 (이름만으로는 같은 이름 · 양방향 쉼터가 겹침)
String restAreaKey(RestArea a) => '${a.name}|${a.lat}|${a.lng}';

/// 줄 세우기 (11/09): 도로 시간을 구한 쉼터가 먼저, 빨리 도착하는 순 (같은 분이면 도로 거리 짧은 순)
/// → 시간을 못 구한 쉼터는 그 뒤에 직선 거리 순.
/// 거리 순이 아닌 이유: 거리는 가까워도 더 오래 걸리는 곳이 있음 (실제 키 시험 11/09 — 천안 부근 19.1km · 31분 vs 22.1km · 18분)
int byArrival(NearRestArea x, NearRestArea y) {
  if (x.roadMin != null && y.roadMin != null) {
    final t = x.roadMin!.compareTo(y.roadMin!);
    return t != 0 ? t : x.roadKm!.compareTo(y.roadKm!);
  }
  if (x.roadMin != null) return -1;
  if (y.roadMin != null) return 1;
  return x.km.compareTo(y.km);
}

/// 직선 거리로 고른 후보에 도로 거리 · 시간을 붙여서 빨리 도착하는 순 n곳 (byArrival).
/// 서버 · 카카오가 안 되거나 [timeout] 안에 답이 없으면 직선 거리 순 그대로 (경고 음성 안내가 늦어지지 않게).
/// 도로 거리를 못 구한 쉼터는 직선 거리로 같이 줄 세움.
Future<List<NearRestArea>> withRoadDistance(
  LatLng me,
  List<NearRestArea> candidates, {
  int n = 5,
  RoadDistanceFetcher? fetch,
  Duration timeout = const Duration(seconds: 5),
}) async {
  if (candidates.isEmpty) return candidates;
  try {
    final dests = [
      for (final c in candidates.take(roadCandidates))
        {'key': restAreaKey(c.area), 'lat': c.area.lat, 'lng': c.area.lng}
    ];
    final results = await (fetch ?? ApiService.fetchRoadDistances)(me.lat, me.lng, dests).timeout(timeout);
    if (results.isEmpty) return candidates.take(n).toList();
    final out = [
      for (final c in candidates.take(roadCandidates))
        switch (results[restAreaKey(c.area)]) {
          {'distance_m': final num m, 'duration_s': final num s} =>
            NearRestArea(c.area, c.km, roadKm: m / 1000, roadMin: math.max(1, (s / 60).round())),
          _ => c,
        }
    ]..sort(byArrival);
    return out.take(n).toList();
  } catch (e) {
    debugPrint('[rest_area] 도로 거리 실패 → 직선 거리: $e');
    return candidates.take(n).toList();
  }
}

/// 내 위치에서 빨리 도착하는 n곳 (도로 시간 순) (2단계 경고 음성 안내 · 지도 화면). 도로 거리를 못 구하면 직선 거리.
Future<List<NearRestArea>> nearestRestAreasByRoad(double lat, double lng, {int n = 5, RoadDistanceFetcher? fetch}) async {
  final me = (lat: lat, lng: lng);
  final straight = await nearestRestAreas(lat, lng, n: roadCandidates);
  return withRoadDistance(me, straight, n: n, fetch: fetch);
}
