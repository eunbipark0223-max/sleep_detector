// ═══════════════════════════════════════════════════════════════
// screens/map_screen.dart — 가까운 졸음쉼터 지도
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/map_screen.dart (🟡 수정, 카카오맵 WebView)
//
// [이 파일이 하는 일]
//   - 공공데이터 '전국 졸음쉼터 표준데이터' (assets/rest_areas.json) 에서 내 위치와 가까운 5곳
//   - 위: 카카오맵 WebView — 내 위치(파란 점) + 쉼터 마커 (누르면 이름)
//   - 아래: 가까운 순 목록 (직선 거리) — 누르면 지도가 그 쉼터로 이동
//            '경부선 · 부산방향' 을 크게 (고속도로 쉼터는 방향이 있어 가장 가까운 곳이 반대편 차로일 수 있음)
//   - [길찾기] → ① 카카오맵 앱 자동차 길안내 (출발 = 내 위치) ② 앱이 없으면 폰 브라우저로 카카오맵 웹 길찾기
//              ③ 둘 다 안 되면 앱 안 WebView (url_launcher, AndroidManifest <queries> 에 kakaomap · https)
//
// [데이터]
//   - notebooks/rest_areas_json.py 로 포털 CSV → assets/rest_areas.json (인터넷 · API 키 없이 읽음)
//   - 읽기 · 거리 계산은 services/rest_area_service.dart (경고 음성 안내와 같은 코드)
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
//   - 아래 생성자의 loadAreas · getPosition · openUrl 은 테스트 · 미리보기에서 바꿔 끼우는 입구다 (비우면 기본)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/rest_area_service.dart';
import '../theme.dart';

export '../services/rest_area_service.dart' show RestArea, LatLng;

/// [길찾기] 주소 두 개: (카카오맵 앱 자동차 길안내, 카카오맵 웹 길찾기). 내 위치를 알면 둘 다 출발지로 넣음
/// (웹은 출발지가 없으면 기사가 '현위치' 를 한 번 더 눌러야 함)
(Uri, Uri) kakaoRouteUris(RestArea a, LatLng? me) {
  final to = 'to/${Uri.encodeComponent(a.name)},${a.lat},${a.lng}';
  final from = me == null ? '' : 'from/${Uri.encodeComponent('내 위치')},${me.lat},${me.lng}/';
  return (
    Uri.parse('kakaomap://route?${me == null ? '' : 'sp=${me.lat},${me.lng}&'}ep=${a.lat},${a.lng}&by=CAR'),
    Uri.parse('https://map.kakao.com/link/$from$to'),
  );
}

class MapScreen extends StatefulWidget {
  /// 졸음쉼터 전체 목록. 비워 두면 assets/rest_areas.json.
  final Future<List<RestArea>> Function()? loadAreas;

  /// 내 위치. 위치를 못 얻으면 null. 비워 두면 GPS (geolocator).
  final Future<LatLng?> Function()? getPosition;

  /// 카카오 JavaScript 키. 비워 두면 --dart-define=KAKAO_JS_KEY 값.
  final String kakaoJsKey;

  /// 주소를 폰의 다른 앱(카카오맵 · 브라우저)으로 열기. 열었으면 true. 비워 두면 url_launcher.
  final Future<bool> Function(Uri url)? openUrl;

  const MapScreen({super.key, this.loadAreas, this.getPosition, this.kakaoJsKey = _kakaoKeyFromEnv, this.openUrl});

  static const String _kakaoKeyFromEnv = String.fromEnvironment('KAKAO_JS_KEY');

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const int _count = 5; // 목록 · 마커 개수

  bool _loading = true;
  String? _error; // 화면에 보여 줄 오류 글
  List<NearRestArea> _near = [];
  LatLng? _me;
  WebViewController? _web;
  int? _selected;

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
      final areas = await (widget.loadAreas ?? loadRestAreas)();
      if (areas.isEmpty) throw Exception('졸음쉼터 데이터가 비어 있어요');
      final me = await (widget.getPosition ?? _defaultPosition)();
      if (!mounted) return;
      if (me == null) throw Exception('내 위치를 알 수 없어요. 위치 권한 · GPS 를 켜 주세요');
      final near = nearestFrom(areas, me, n: _count);
      setState(() {
        _near = near;
        _me = me;
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

  WebViewController _buildMap(LatLng me, List<NearRestArea> near) {
    final data = jsonEncode({
      'me': {'lat': me.lat, 'lng': me.lng},
      'areas': [for (final n in near) {'name': n.area.name, 'lat': n.area.lat, 'lng': n.area.lng}],
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

  static Future<bool> _defaultOpenUrl(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false; // 열 앱이 없음
    }
  }

  // 앱 안 WebView 는 카카오맵 앱을 못 열어서 (웹 링크가 '앱 설치' 화면으로 감) 폰의 카카오맵 앱 · 브라우저로 넘긴다
  Future<void> _openRoute(RestArea a) async {
    final (app, web) = kakaoRouteUris(a, _me);
    final open = widget.openUrl ?? _defaultOpenUrl;
    if (await open(app) || await open(web)) return;
    if (!mounted) return;
    Navigator.push(context, MaterialPageRoute(builder: (_) => _RoutePage(title: a.name, url: web.toString())));
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
              final NearRestArea(area: a, :km) = _near[i];
              return ListTile(
                selected: _selected == i,
                selectedTileColor: AppColors.rest.withValues(alpha: 0.08),
                leading: CircleAvatar(
                  radius: 14,
                  backgroundColor: AppColors.rest,
                  child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontSize: 13)),
                ),
                // 노선 · 방향을 이름보다 크게 — 가장 가까운 쉼터가 반대편 차로일 수 있음
                title: Text(a.roadText.isEmpty ? a.name : a.roadText,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                subtitle: Text(
                  [if (a.roadText.isNotEmpty) a.name, '직선 ${km.toStringAsFixed(1)}km', if (a.toilet == 'Y') '화장실'].join(' · '),
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
