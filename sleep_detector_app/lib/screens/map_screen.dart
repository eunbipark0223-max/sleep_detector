// ═══════════════════════════════════════════════════════════════
// screens/map_screen.dart — 가까운 졸음쉼터 지도
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/map_screen.dart (🟡 수정, 카카오맵 WebView)
//
// [이 파일이 하는 일]
//   - 공공데이터 '전국 졸음쉼터 표준데이터' (assets/rest_areas.json) 에서 내 위치와 가까운 5곳
//   - 위: 카카오맵 WebView — 내 위치(파란 점) + 쉼터 마커 (누르면 이름)
//   - 아래: 가까운 순 목록 (직선 거리) — 누르면 지도가 그 쉼터로 이동, [길찾기] → 카카오맵 길찾기 웹 화면
//
// [데이터]
//   - notebooks/rest_areas_json.py 로 포털 CSV → assets/rest_areas.json (인터넷 · API 키 없이 읽음)
//   - 거리는 직선 거리 (도로 거리는 [길찾기] 에서)
//
// [카카오 키]
//   - 지도는 카카오 JavaScript 키가 있어야 그려진다 → flutter run --dart-define=KAKAO_JS_KEY=본인키
//   - 카카오 개발자 콘솔 → 내 앱 → 플랫폼 → Web 사이트 도메인에 http://localhost 등록 (WebView 가 이 주소로 지도를 띄움)
//   - 키가 없으면 지도 자리에 안내만 나오고 목록 · [길찾기] 는 그대로 동작
//   - 🔴 키는 코드 · GitHub · 단톡에 쓰지 않는다
//
// [연결]
//   - Navigator.push(context, MaterialPageRoute(builder: (_) => const MapScreen()));
//   - 아래 생성자의 loadAreas · getPosition 은 테스트 · 미리보기에서 바꿔 끼우는 입구다 (비우면 기본)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:geolocator/geolocator.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme.dart';

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

/// 가까운 순 n곳 (쉼터, 거리 km)
List<(RestArea, double)> nearestAreas(List<RestArea> all, LatLng me, {int n = 5}) {
  final withDist = [for (final a in all) (a, distanceKm(me, (lat: a.lat, lng: a.lng)))];
  withDist.sort((x, y) => x.$2.compareTo(y.$2));
  return withDist.take(n).toList();
}

class MapScreen extends StatefulWidget {
  /// 졸음쉼터 전체 목록. 비워 두면 assets/rest_areas.json.
  final Future<List<RestArea>> Function()? loadAreas;

  /// 내 위치. 위치를 못 얻으면 null. 비워 두면 GPS (geolocator).
  final Future<LatLng?> Function()? getPosition;

  /// 카카오 JavaScript 키. 비워 두면 --dart-define=KAKAO_JS_KEY 값.
  final String kakaoJsKey;

  const MapScreen({super.key, this.loadAreas, this.getPosition, this.kakaoJsKey = _kakaoKeyFromEnv});

  static const String _kakaoKeyFromEnv = String.fromEnvironment('KAKAO_JS_KEY');

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const int _count = 5; // 목록 · 마커 개수

  bool _loading = true;
  String? _error; // 화면에 보여 줄 오류 글
  List<(RestArea, double)> _near = [];
  WebViewController? _web;
  int? _selected;

  static Future<List<RestArea>> _defaultLoad() async {
    final raw = jsonDecode(await rootBundle.loadString('assets/rest_areas.json')) as List;
    return raw.map((e) => RestArea.fromJson(Map<String, dynamic>.from(e as Map))).toList();
  }

  static Future<LatLng?> _defaultPosition() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return null;
    try {
      final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 10)));
      return (lat: p.latitude, lng: p.longitude);
    } catch (_) {
      // 실내 · 터널 등에서 10초 안에 못 잡으면 마지막으로 알던 위치
      final p = await Geolocator.getLastKnownPosition();
      return p == null ? null : (lat: p.latitude, lng: p.longitude);
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final areas = await (widget.loadAreas ?? _defaultLoad)();
      if (areas.isEmpty) throw Exception('졸음쉼터 데이터가 비어 있어요');
      final me = await (widget.getPosition ?? _defaultPosition)();
      if (!mounted) return;
      if (me == null) throw Exception('내 위치를 알 수 없어요. 위치 권한 · GPS 를 켜 주세요');
      final near = nearestAreas(areas, me, n: _count);
      setState(() {
        _near = near;
        _selected = null;
        _web = widget.kakaoJsKey.isEmpty ? null : _buildMap(me, near);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e'.replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  WebViewController _buildMap(LatLng me, List<(RestArea, double)> near) {
    final data = jsonEncode({
      'me': {'lat': me.lat, 'lng': me.lng},
      'areas': [for (final (a, _) in near) {'name': a.name, 'lat': a.lat, 'lng': a.lng}],
    }).replaceAll('</', r'<\/'); // <script> 안에 넣으므로 '</script>' 가 생기지 않게
    // baseUrl = 카카오 콘솔에 등록한 Web 도메인 (http://localhost)
    return WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadHtmlString(_mapHtml(widget.kakaoJsKey, data), baseUrl: 'http://localhost');
  }

  // 목록을 누르면 지도에서 그 쉼터로 이동 + 이름 표시
  void _focus(int i) {
    setState(() => _selected = i);
    _web?.runJavaScript('window.focusArea && window.focusArea($i)');
  }

  void _openRoute(RestArea a) {
    // 카카오맵 길찾기 웹 (키 필요 없음). 도착지 = 쉼터, 출발지 = 카카오맵이 내 위치로 잡음
    final url = 'https://map.kakao.com/link/to/${Uri.encodeComponent(a.name)},${a.lat},${a.lng}';
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RoutePage(title: a.name, url: url)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가까운 졸음쉼터')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : Column(
                  children: [
                    Expanded(flex: 3, child: _web == null ? const _NoKeyView() : WebViewWidget(controller: _web!)),
                    Expanded(flex: 2, child: _list()),
                  ],
                ),
    );
  }

  Widget _list() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 4),
            itemCount: _near.length,
            separatorBuilder: (_, _) => const Divider(height: 1, color: AppColors.cardBorder),
            itemBuilder: (context, i) {
              final (a, km) = _near[i];
              return ListTile(
                selected: _selected == i,
                selectedTileColor: AppColors.rest.withValues(alpha: 0.08),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.rest,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
                title: Text(a.name, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                subtitle: Text(
                  [a.roadText, '직선 ${km.toStringAsFixed(1)}km', if (a.toilet == 'Y') '화장실'].where((s) => s.isNotEmpty).join(' · '),
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                trailing: TextButton(onPressed: () => _openRoute(a), child: const Text('길찾기')),
                onTap: () => _focus(i),
              );
            },
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text('거리는 직선 거리 · 출처: 공공데이터포털 전국졸음쉼터표준데이터',
              style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
        ),
      ],
    );
  }
}

class _NoKeyView extends StatelessWidget {
  const _NoKeyView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.cardBorder.withValues(alpha: 0.4),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: const Text(
        '지도를 보려면 카카오 JavaScript 키가 필요해요\n(flutter run --dart-define=KAKAO_JS_KEY=...)\n아래 목록 · 길찾기는 그대로 쓸 수 있어요',
        textAlign: TextAlign.center,
        style: TextStyle(color: AppColors.textSecondary),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.location_off_outlined, size: 48, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onRetry, child: const Text('다시 시도')),
          ],
        ),
      ),
    );
  }
}

/// 카카오맵 길찾기 웹 화면. 카카오맵 앱을 여는 주소(intent:// · kakaomap://)는 WebView 가 못 열어서 막는다
class _RoutePage extends StatefulWidget {
  final String title;
  final String url;

  const _RoutePage({required this.title, required this.url});

  @override
  State<_RoutePage> createState() => _RoutePageState();
}

class _RoutePageState extends State<_RoutePage> {
  late final WebViewController _web = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(NavigationDelegate(
      onNavigationRequest: (req) => req.url.startsWith('http') ? NavigationDecision.navigate : NavigationDecision.prevent,
    ))
    ..loadRequest(Uri.parse(widget.url));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} 길찾기')),
      body: WebViewWidget(controller: _web),
    );
  }
}

/// 카카오맵 HTML. data = {me: {lat, lng}, areas: [{name, lat, lng}]}
String _mapHtml(String key, String data) => '''
<!doctype html>
<html><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
<style>
  html, body, #map { margin: 0; width: 100%; height: 100%; }
  #err { display: none; padding: 24px; color: #4A5068; font-family: sans-serif; text-align: center; }
  .me { width: 14px; height: 14px; border-radius: 50%; background: #1F6FEB; border: 3px solid #fff; box-shadow: 0 0 4px rgba(0,0,0,.4); }
  .label { padding: 4px 8px; font-size: 12px; white-space: nowrap; }
</style>
<script src="https://dapi.kakao.com/v2/maps/sdk.js?appkey=$key&autoload=false"></script>
</head><body>
<div id="err">지도를 불러오지 못했어요<br>(인터넷 · 카카오 키 · 등록 도메인 http://localhost · 카카오맵 사용 설정 확인)</div>
<div id="map"></div>
<script>
var DATA = $data;
// SDK 를 못 받으면 (키 · 도메인 · 카카오맵 사용 설정 문제) kakao 가 없음 → 안내 글
if (!(window.kakao && kakao.maps)) document.getElementById('err').style.display = 'block';
else kakao.maps.load(function () {
  var me = new kakao.maps.LatLng(DATA.me.lat, DATA.me.lng);
  var map = new kakao.maps.Map(document.getElementById('map'), { center: me, level: 8 });
  var bounds = new kakao.maps.LatLngBounds();
  bounds.extend(me);
  new kakao.maps.CustomOverlay({ map: map, position: me, content: '<div class="me"></div>' });
  var markers = [], infos = [];
  DATA.areas.forEach(function (a, i) {
    var pos = new kakao.maps.LatLng(a.lat, a.lng);
    var m = new kakao.maps.Marker({ map: map, position: pos, title: a.name });
    var info = new kakao.maps.InfoWindow({ content: '<div class="label">' + (i + 1) + '. ' + a.name + '</div>' });
    kakao.maps.event.addListener(m, 'click', function () { window.focusArea(i); });
    markers.push(m); infos.push(info); bounds.extend(pos);
  });
  map.setBounds(bounds);
  window.focusArea = function (i) {
    infos.forEach(function (w) { w.close(); });
    map.panTo(markers[i].getPosition());
    infos[i].open(map, markers[i]);
  };
});
</script>
</body></html>
''';
