// rest_area_service 도로 거리 시험 (B, 11/09) — 서버 · 카카오 없이 가짜 응답으로
//   flutter test test/rest_area_service_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sleep_detector_app/services/rest_area_service.dart';

void main() {
  const me = (lat: 37.5, lng: 127.0);
  // 직선으로는 반대편 차로 쉼터(가까움)가 1등, 도로로는 같은 방향 쉼터가 1등인 상황
  const opposite = RestArea(name: '반대편 쉼터', lat: 37.51, lng: 127.0, direction: '서울방향');
  const sameWay = RestArea(name: '같은 방향 쉼터', lat: 37.55, lng: 127.0, direction: '부산방향');
  const far = RestArea(name: '먼 쉼터', lat: 37.7, lng: 127.0, direction: '부산방향');
  final candidates = nearestFrom([far, sameWay, opposite], me, n: 3);

  test('직선 거리 순서', () {
    expect(candidates.map((c) => c.area.name), ['반대편 쉼터', '같은 방향 쉼터', '먼 쉼터']);
  });

  test('도로 시간을 받으면 빨리 도착하는 순 + 분 + 음성 문장', () async {
    final near = await withRoadDistance(me, candidates, n: 2, fetch: (lat, lng, dests) async {
      expect(dests.length, 3);
      return {
        restAreaKey(opposite): {'distance_m': 23400, 'duration_s': 1260}, // 돌아가야 함
        restAreaKey(sameWay): {'distance_m': 6100, 'duration_s': 300},
        // 먼 쉼터는 못 구함 → 시간을 구한 쉼터들 뒤로
      };
    });
    expect(near.map((c) => c.area.name), ['같은 방향 쉼터', '반대편 쉼터']);
    expect(near.first.hasRoad, isTrue);
    expect(near.first.roadMin, 5);
    expect(near.first.distanceText, '도로 6.1km · 5분');
    expect(near.first.voice, '가까운 같은 방향 쉼터, 부산방향, 약 6킬로미터, 약 5분');
    expect(near[1].distanceText, '도로 23.4km · 21분');
    final all = await withRoadDistance(me, candidates, n: 3, fetch: (lat, lng, dests) async => {
          restAreaKey(sameWay): {'distance_m': 6100, 'duration_s': 300},
        });
    expect(all.last.area.name, '먼 쉼터');
    expect(all.last.distanceText, startsWith('직선 '));
  });

  test('거리는 가까워도 오래 걸리면 뒤로 — 시간 순 (11/09 천안 부근 실제 값)', () async {
    final near = await withRoadDistance(me, candidates, n: 3, fetch: (lat, lng, dests) async => {
          restAreaKey(opposite): {'distance_m': 19100, 'duration_s': 31 * 60}, // 연곡: 가깝지만 31분
          restAreaKey(sameWay): {'distance_m': 22100, 'duration_s': 18 * 60}, // 원곡: 멀지만 18분
          restAreaKey(far): {'distance_m': 21000, 'duration_s': 18 * 60}, // 같은 18분이면 짧은 쪽 먼저
        });
    expect(near.map((c) => c.area.name), ['먼 쉼터', '같은 방향 쉼터', '반대편 쉼터']);
  });

  test('시간을 구한 쉼터가 먼저, 못 구한 쉼터는 뒤에 직선 거리 순', () async {
    final near = await withRoadDistance(me, candidates, n: 3, fetch: (lat, lng, dests) async => {
          restAreaKey(far): {'distance_m': 30000, 'duration_s': 25 * 60},
        });
    expect(near.map((c) => c.area.name), ['먼 쉼터', '반대편 쉼터', '같은 방향 쉼터']);
  });

  test('서버 실패 · 빈 결과 · 늦은 답 → 직선 거리 그대로', () async {
    Future<List<String>> names(RoadDistanceFetcher f) async =>
        (await withRoadDistance(me, candidates, n: 2, fetch: f, timeout: const Duration(milliseconds: 200)))
            .map((c) => c.area.name)
            .toList();
    const straight = ['반대편 쉼터', '같은 방향 쉼터'];
    expect(await names((_, _, _) async => throw Exception('서버 꺼짐')), straight);
    expect(await names((_, _, _) async => {}), straight);
    expect(await names((_, _, _) => Future.delayed(const Duration(seconds: 1), () => {})), straight);
    expect(await names((_, _, _) async => {restAreaKey(sameWay): {'distance_m': 'x'}}), straight); // 모양이 다름
  });

  test('도로 거리 없으면 음성은 직선 거리 · 분 없음', () {
    expect(candidates.first.voice, '가까운 반대편 쉼터, 서울방향, 약 1킬로미터');
  });
}
