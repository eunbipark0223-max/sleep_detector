// ═══════════════════════════════════════════════════════════════
// services/rest_area_service.dart — 가까운 졸음쉼터 찾기 (지도 화면 · 경고 음성 안내 공용)
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: (없음, 🔴 신규) — map_screen.dart 에 있던 쉼터 읽기 · 거리 계산을 다른 화면에서도 쓰게 뺀 것
//
// [이 파일이 하는 일]
//   - 공공데이터 '전국 졸음쉼터 표준데이터' (assets/rest_areas.json) 읽기 — 한 번 읽으면 앱이 꺼질 때까지 기억
//   - 내 위치에서 직선 거리로 가까운 n곳 (도로 거리는 지도 화면 [길찾기] 에서)
//   - 경고 음성 안내 문장: "가까운 태인 졸음쉼터, 천안방향, 약 12킬로미터"
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - nearestRestAreas(lat, lng, {n = 5}) → List<NearRestArea> (가까운 순, 데이터를 못 읽으면 빈 목록)
//   - NearRestArea: area(RestArea) · km(직선 거리) · voice(음성 안내 문장)
//   - 2단계 경고 음성 안내 (C 의 warning_screen):
//       final near = await nearestRestAreas(lat, lng, n: 1);
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

import 'package:flutter/services.dart' show rootBundle;

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

  const NearRestArea(this.area, this.km);

  /// 경고 음성 안내 문장 — "가까운 태인 졸음쉼터, 천안방향, 약 12킬로미터"
  String get voice => [
        '가까운 ${area.name}',
        if (area.direction.isNotEmpty) area.direction,
        km < 1 ? '1킬로미터 안' : '약 ${km.round()}킬로미터',
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
