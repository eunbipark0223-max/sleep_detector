// ═══════════════════════════════════════════════════════════════
// screens/map_screen.dart — 가까운 졸음쉼터 지도
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/map_screen.dart (🟡 수정, 카카오맵 WebView)
//
// [이 파일이 하는 일]
//   - 공공데이터 '전국 졸음쉼터 표준데이터' (assets/rest_areas.json) 에서 내 위치와 가까운 5곳
//   - 위: 카카오맵 WebView — 내 위치(파란 점) + 쉼터 마커 (누르면 이름)
//   - 아래: 가까운 순 목록 — 직선 거리로 먼저 보이고, 서버가 도로 거리(카카오모빌리티)를 주면 빨리 도착하는 순(도로 시간)으로 바뀜 (11/09)
//            누르면 지도가 그 쉼터로 이동
//            '경부선 · 부산방향' 을 크게 (고속도로 쉼터는 방향이 있어 가장 가까운 곳이 반대편 차로일 수 있음)
//   - [길찾기] → ① 카카오맵 앱 자동차 길안내 (출발 = 내 위치) ② 앱이 없으면 폰 브라우저로 카카오맵 웹 길찾기
//              ③ 둘 다 안 되면 앱 안 WebView (url_launcher, AndroidManifest <queries> 에 kakaomap · https)
//
// [데이터]
//   - notebooks/rest_areas_json.py 로 포털 CSV → assets/rest_areas.json (인터넷 · API 키 없이 읽음)
//   - 읽기 · 거리 계산은 services/rest_area_service.dart (경고 음성 안내와 같은 코드)
//   - 거리: 도로 거리 (서버 /rest-areas/road-distance → 카카오모빌리티 자동차 길찾기, 키는 서버 .env 에만)
//           서버 · 카카오가 안 되면 직선 거리 (목록 아래 글자로 어느 쪽인지 표시)
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

  /// 도로 거리 묻기. 비워 두면 서버 (/rest-areas/road-distance). 실패하면 직선 거리 그대로.
  final RoadDistanceFetcher? fetchRoad;

  const MapScreen(
      {super.key, this.loadAreas, this.getPosition, this.kakaoJsKey = _kakaoKeyFromEnv, this.openUrl, this.fetchRoad});

  static const String _kakaoKeyFromEnv = String.fromEnvironment('KAKAO_JS_KEY');

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const int _count = 5; // 목록 · 마커 개수

  bool _loading = true;
  bool _roadLoading = false; // 도로 거리를 묻는 중 (목록은 직선 거리로 먼저 보임)
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
      // 1) 직선 거리 목록을 바로 보여 주고  2) 도로 거리가 오면 빨리 도착하는 순으로 바꿈 (안 오면 그대로)
      final candidates = nearestFrom(areas, me, n: roadCandidates);
      final near = candidates.take(_count).toList();
      setState(() {
        _near = near;
        _me = me;
        _selected = null;
        _roadLoading = true;
        _web = widget.kakaoJsKey.isEmpty ? null : _buildMap(me, near);
        _loading = false;
      });
      final byRoad = await withRoadDistance(me, candidates, n: _count, fetch: widget.fetchRoad);
      if (!mounted || _me != me) return; // 그사이 [다시 시도] 로 새로 불렀으면 버림
      final changed = byRoad.any((x) => x.hasRoad);
      setState(() {
        _roadLoading = false;
        if (!changed) return;
        _near = byRoad;
        _selected = null;
        _web = widget.kakaoJsKey.isEmpty ? null : _buildMap(me, byRoad); // 마커 번호를 새 순서에 맞춤
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

  // ── 화면 (11/18 사용자 요청 · 애플 스타일) ───────────────────────────────
  //   제목 '가까운 쉼터' · 아래 시트: [거리순 | 시간순] 탭 → 한 줄 설명 → 쉼터 목록 (모두 같은 좌우 여백 20)
  //   쉼터 한 줄: 순번 · 이름 · '거리 9.3km · 12분' · 오른쪽 [길찾기] (연한 남색 알약)
  //   시간 = B 의 도로 거리 로직 (서버 /rest-areas/road-distance → 카카오모빌리티). 못 구하면 거리만
  static const Color _bg = AppColors.card;
  static const double _side = 20; // 탭 · 설명 · 목록 공통 좌우 여백
  int _sort = 0; // 0 거리순 · 1 시간순

  // 화면에 보일 순서 (지도 마커 번호는 _near 순서 그대로라서 원래 번호를 들고 다님)
  List<int> get _order {
    final idx = [for (var i = 0; i < _near.length; i++) i];
    if (_sort == 0) {
      idx.sort((a, b) => _near[a].bestKm.compareTo(_near[b].bestKm));
    } else {
      idx.sort((a, b) {
        final x = _near[a].roadMin, y = _near[b].roadMin;
        if (x != null && y != null && x != y) return x.compareTo(y);
        if (x != null && y == null) return -1;
        if (x == null && y != null) return 1;
        return _near[a].bestKm.compareTo(_near[b].bestKm);
      });
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        toolbarHeight: 68,
        titleSpacing: _side,
        centerTitle: false,
        title: const Text('가까운 쉼터',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.textPrimary)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorView(message: _error!, onRetry: _load)
              : Stack(
                  children: [
                    // 지도 — 위쪽 전체 (아래 목록 시트가 겹쳐 올라옴)
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 330,
                      child: _web == null ? const _NoKeyView() : WebViewWidget(controller: _web!),
                    ),
                    Positioned(left: 0, right: 0, bottom: 0, height: 360, child: _sheet()),
                  ],
                ),
    );
  }

  Widget _sheet() {
    final order = _order;
    return Container(
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [BoxShadow(color: Color(0x14000000), blurRadius: 16, offset: Offset(0, -2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          Center(
            child: Container(
                width: 36, height: 5, decoration: BoxDecoration(color: const Color(0xFFD5D8DF), borderRadius: BorderRadius.circular(99))),
          ),
          const SizedBox(height: 14),
          // 애플 세그먼트 탭 — 거리순 | 시간순
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _side),
            child: _Segment(
              labels: const ['거리순', '시간순'],
              selected: _sort,
              onSelect: (i) => setState(() => _sort = i),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(_side + 2, 12, _side, 6),
            child: Text(
              _roadLoading
                  ? '걸리는 시간을 확인하고 있어요'
                  : _sort == 0
                      ? '가장 가까운 쉼터 순서대로 보여드려요'
                      : '가장 빨리 도착하는 쉼터 순서대로 보여드려요',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(_side, 4, _side, 16),
              itemCount: order.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, k) => _card(order[k], k + 1),
            ),
          ),
        ],
      ),
    );
  }

  // 쉼터 한 줄 — 순번 · 이름 · 거리 · 시간 · [길찾기]
  Widget _card(int i, int rank) {
    final near = _near[i];
    final a = near.area;
    final selected = _selected == i;
    final dist = '거리 ${near.bestKm.toStringAsFixed(1)}km${near.roadMin == null ? '' : ' · ${near.roadMin}분'}';
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: selected ? AppColors.navy : AppColors.cardBorder, width: selected ? 1.5 : 1),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _focus(i),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: rank == 1 ? AppColors.navy : AppColors.field, shape: BoxShape.circle),
                child: Text('$rank',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: rank == 1 ? Colors.white : AppColors.textSecondary)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(a.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(dist, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 애플 지도 [경로] 버튼처럼 — 연한 남색 알약 + 남색 글자
              TextButton.icon(
                onPressed: () => _openRoute(a),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.navy,
                  backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                icon: const Icon(Icons.directions_car_rounded, size: 16),
                label: const Text('길찾기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 애플 세그먼트 컨트롤 — 연회색 칸 안에서 고른 칸만 흰 알약이 미끄러져 옴
class _Segment extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelect;
  const _Segment({required this.labels, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(10)),
      child: LayoutBuilder(builder: (context, c) {
        final w = c.maxWidth / labels.length;
        return Stack(children: [
          AnimatedPositioned(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            left: w * selected,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(8),
                boxShadow: const [BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 1))],
              ),
            ),
          ),
          Row(children: [
            for (var i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelect(i),
                  child: Center(
                    child: Text(labels[i],
                        style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: i == selected ? FontWeight.w600 : FontWeight.w500,
                            color: i == selected ? AppColors.textPrimary : AppColors.textSecondary)),
                  ),
                ),
              ),
          ]),
        ]);
      }),
    );
  }
}

class _NoKeyView extends StatelessWidget {
  const _NoKeyView();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE9ECF4),
      alignment: Alignment.center,
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 60),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.map_outlined, size: 40, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('지도를 불러오지 못했어요\n아래 목록에서 바로 길찾기를 할 수 있어요',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary)),
        ],
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
  // WebView 크기가 정해지기 전에 범위를 맞추면 지도가 크게 축소됨 (11/09 에뮬레이터에서 일본까지 보임) → 크기가 정해진 뒤 다시 맞춤
  function fit() { map.relayout(); map.setBounds(bounds); }
  setTimeout(fit, 300);
  setTimeout(fit, 1200);
  window.addEventListener('resize', fit);
  window.focusArea = function (i) {
    infos.forEach(function (w) { w.close(); });
    map.panTo(markers[i].getPosition());
    infos[i].open(map, markers[i]);
  };
});
</script>
</body></html>
''';
