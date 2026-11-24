// ═══════════════════════════════════════════════════════════════
// screens/home_screen.dart — 홈
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
//
// [이 파일이 하는 일]
//   - [운행 시작] → calibration_screen (내 눈 기준 측정) → drive_screen
//   - [사진 1장 테스트] 는 ≡ 메뉴로 옮김 (main_screen, 11/11 — 기사님 홈에는 운전에 필요한 것만)
//   - [가까운 졸음쉼터] → map_screen (B 의 카카오맵 지도)
//   - 최근 경고 2~3건 (GET /events/my). 운행 · 사진 1장 테스트에서 돌아오면 다시 불러온다
//   - 맨 위 상태 카드: 서버 GET /drive/state 의 지금 단계 (11/16). 서버에 못 물으면 내 경고 기록으로 가늠한 단계 (currentStage — 3단계는 조치완료 전까지, 2단계는 휴식 전까지, 1단계는 10분)
//
// [연결됨]
//   - 최근 경고 : C 의 ApiService.fetchMyEvents() (GET /events/my). 실패하면 '불러오지 못했어요 + 다시 시도'
//   - [운행 시작]      : D 의 CalibrationScreen → C 의 DriveScreen(threshold: 기준 값)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/drive_status.dart';
import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';
import '../widgets/web_ui.dart';
import '../widgets/home_ui.dart';
import 'calibration_screen.dart';
import 'drive_screen.dart';
import 'event_detail_screen.dart';
import '../widgets/buddy.dart';
import '../services/drive_log.dart';
import 'history_screen.dart' show HistoryEventRow;
import '../widgets/system_status.dart';

// (사진 1장 테스트 · 개발용 숨김은 main_screen 의 ≡ 메뉴로 옮김 — SHOW_DEV_TOOLS, 11/11)

class HomeScreen extends StatefulWidget {
  /// 최근 경고를 가져오는 함수. 비워 두면 기본(_defaultLoad). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Future<List<SleepEvent>?> Function()? loadEvents;

  /// 개인 기준 측정 화면. 비워 두면 진짜 CalibrationScreen (카메라 필요). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Widget Function()? calibrationBuilder;

  /// 운행 화면. 기준 값을 받아 만든다. 비워 두면 진짜 DriveScreen (카메라 필요). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Widget Function(double threshold)? driveBuilder;

  /// 서버가 기억하는 '진행 중인 운행'을 가져오는 함수 (GET /drive/state). 비워 두면 진짜 서버. 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Future<DriveState?> Function()? loadDriveState;

  /// [이어서 운행] 으로 여는 운행 화면. 비워 두면 진짜 DriveScreen(resume: 상태). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Widget Function(DriveState state)? resumeBuilder;

  /// 최근 경고 [전체 보기] — 운행 기록 탭으로 (main_screen 이 넘겨 줌, 디자인 시안 11/12)
  final VoidCallback? onOpenRecords;
  final ValueChanged<int>? onOpenTab; // (11/23 리디자인_3) 바로가기 타일 → 아래 탭 번호로 이동

  const HomeScreen({
    super.key,
    this.loadEvents,
    this.calibrationBuilder,
    this.driveBuilder,
    this.loadDriveState,
    this.resumeBuilder,
    this.onOpenRecords,
    this.onOpenTab,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0; // 0 오늘 경고 · 1 이번 주 · 2 긴급
  static const int _driveCount = 3; // (11/19) 처음에 보이는 운행 카드 수
  bool _scrolled = false; // (11/19) 아래로 내렸는지 — 내렸을 때만 위쪽을 흐리게
  bool _expanded = false; // (11/18 피드백) [n건 전체 보기] 를 누르면 그 자리에서 아래로 펼침 (운행 기록 탭으로 가지 않음)

  // (11/16 팀장) 홈의 '출발 준비 (카메라 · 음성 안내)' 줄은 뺐다 — 권한은 [운행 시작] 때 안내창 → 휴대폰 권한 창으로 받음

  /// 카메라 · 마이크 · 위치 중 아직 없는 권한을 안내창 → 휴대폰 권한 창으로 받는다.
  /// 안내창을 닫으면 false. 두 번 거절해 휴대폰이 더는 묻지 않으면 앱 설정 화면을 연다.
  Future<bool> _askPermissions() async {
    try {
      const perms = [
        Permission.camera,
        Permission.microphone,
        Permission.locationWhenInUse,
      ];
      final need = <Permission>[
        for (final p in perms)
          if (!await p.isGranted) p,
      ];
      if (need.isEmpty) return true;
      // (11/19 사용자 요청) 안내창은 처음 한 번만 — 그 뒤에는 휴대폰 권한 창만 (다시 묻지 않음 상태면 그냥 진행)
      if (await AuthService.getPermAsked()) {
        await need.request();
        return true;
      }
      AuthService.setPermAsked().ignore();
      if (!mounted) return false;
      final ok = await showPermissionSheet(
        context,
        camera: need.contains(Permission.camera),
        mic: need.contains(Permission.microphone),
        location: need.contains(Permission.locationWhenInUse),
      );
      if (ok != true) return false; // 안내창을 닫음
      final result = await need.request(); // 한 번의 요청 → 시스템 창이 이어서 뜬다
      if (result.values.any((st) => st.isPermanentlyDenied))
        await openAppSettings();
    } catch (_) {
      // 권한 확인이 안 되는 폰이어도 계속 (카메라는 측정 화면이 다시 확인)
    }
    return true;
  }

  // (11/23 기업용 리디자인) 시스템 상태 — 휴대폰 권한(카메라 · 마이크 · 위치) · 관제 서버 연결
  List<bool>? _perms;
  bool? _online;
  Future<void> _checkPerms() async {
    try {
      final r = [
        await Permission.camera.isGranted,
        await Permission.microphone.isGranted,
        await Permission.locationWhenInUse.isGranted,
      ];
      if (mounted) setState(() => _perms = r);
    } catch (_) {
      if (mounted) setState(() => _perms = [true, true, true]);
    }
  }

  @override
  void initState() {
    super.initState();
    _checkPerms();
  }

  late Future<List<SleepEvent>?> _recent = _fetch();
  late Future<DriveState?> _driveState = _fetchDriveState();
  late Future<List<DriveSpan>> _spans = DriveLog.load(); // (11/19) 폰에 적어 둔 운행 시작 · 종료

  // 앱을 껐다 켰을 때 서버가 기억하는 운행 상태. 못 받으면 (서버 연결 오류 등) null — 배너만 안 뜨고 홈은 그대로
  Future<DriveState?> _fetchDriveState() {
    final future = (widget.loadDriveState ?? _defaultLoadDriveState)().then<DriveState?>((v) {
      if (mounted) setState(() => _online = true);
      return v;
    }).catchError((_) {
      if (mounted) setState(() => _online = false);
      return null;
    });
    return future;
  }

  static Future<DriveState?> _defaultLoadDriveState() =>
      ApiService.fetchDriveState();

  // 화면(FutureBuilder)이 받기 전에 요청이 먼저 실패해도 '처리 안 된 오류'로 새지 않게 ignore() 를 붙인다
  Future<List<SleepEvent>?> _fetch() {
    final future = (widget.loadEvents ?? _defaultLoad)();
    future.ignore();
    return future;
  }

  /// 최근 경고 (GET /events/my). 화면에는 최신 3건만 보인다. null 이면 '준비 중' 안내, 빈 목록이면 '경고 없음'.
  static Future<List<SleepEvent>?> _defaultLoad() => ApiService.fetchMyEvents();

  // setState 안에서는 값을 돌려주면 안 된다 (Future 를 돌려주면 오류) → 중괄호로 대입만 한다
  void _reload() {
    setState(() {
      _recent = _fetch();
      _driveState = _fetchDriveState();
      _spans = DriveLog.load();
    });
    _checkPerms();
  }

  /// 내 경고 기록으로 지금 단계를 가늠한다 (서버 규칙과 같은 모양, 홈에는 따로 부를 '지금 단계' API 가 없다)
  ///   - 3단계: 관리자가 [조치완료]를 누르기 전까지 · 2단계: 휴식(휴식완료) 또는 조치완료 전까지
  ///   - 조치완료는 모든 단계를 0 으로 되돌린다 (그 경고보다 오래된 경고도 풀림)
  ///   - 1단계: 마지막 졸음 뒤 10분 동안 (그 뒤 자동 해제)
  ///   - 휴식 뒤 1단계로 다시 출발한 시간은 기록에 없어서 0단계로 본다
  ///   - 운행을 끝내도 단계는 이어진다 (서버가 운행 시작 때 2 · 3단계를 유지, 11/03) — 1단계는 10분이면 저절로 풀림
  /// 가장 높은 단계를 돌려준다. 못 받았거나 경고가 없으면 0 (정상).
  static int currentStage(List<SleepEvent>? events, {DateTime? now}) {
    if (events == null) return 0;
    final t = now ?? DateTime.now();
    // 관리자 [조치완료]는 그 기사의 단계를 전부 0 으로 되돌린다 → 조치완료된 경고(와 그보다 오래된 경고)는 세지 않는다
    DateTime? resetAt;
    for (final e in events) {
      if (e.status == '조치완료' &&
          (resetAt == null || e.createdAt.isAfter(resetAt)))
        resetAt = e.createdAt;
    }
    var stage = 0;
    for (final e in events) {
      if (e.status == '조치완료') continue;
      if (resetAt != null && !e.createdAt.isAfter(resetAt)) continue;
      final s = e.stage.clamp(0, 3);
      final age = t.difference(e.createdAt);
      final active = switch (s) {
        3 => true,
        2 => e.status != '휴식완료',
        1 =>
          age <= const Duration(minutes: 10) &&
              age >= const Duration(minutes: -1),
        _ => false,
      };
      if (active && s > stage) stage = s;
    }
    return stage;
  }

  // 측정 화면이 돌려주는 값: 기준 값(double) / null = 시작 전에 뒤로 가기 (운행을 시작하지 않는다)
  // 기준 값은 DriveScreen(threshold: t) 로 넘긴다 (측정을 건너뛰었으면 기본 기준이 들어 있다)
  Future<void> _startDrive() async {
    // 카메라 · 마이크 · 위치 권한이 아직 없으면 시안의 안내창 → [계속] → 휴대폰 권한 창 (11/12 팀장)
    //   이미 다 허용했으면 안내창 없이 바로 측정 화면. 안내창을 닫으면 운행을 시작하지 않음
    if (!await _askPermissions()) return;
    if (!mounted) return;
    final t = await Navigator.of(context).push<double>(
      MaterialPageRoute(
        builder: (_) =>
            (widget.calibrationBuilder ?? () => const CalibrationScreen())(),
      ),
    );
    if (t == null || !mounted) return;
    // 서버에 새 운행 시작을 알린다 — 연속 운전 시간 · 퀴즈 실패 수 · 반쯤 감은 눈 기록을 새로 세고, 0 · 1단계는 정상으로 (2 · 3단계는 서버가 유지).
    //   (11/12 팀장) 지금까지 앱이 /drive/start 를 한 번도 안 불러서 지난 운행의 1단계 · 기록이 이어졌음. 실패해도 운행은 시작 (ping 이 대신 시작함)
    if (widget.driveBuilder == null) {
      try {
        await ApiService.startDrive().timeout(const Duration(seconds: 5));
      } catch (_) {}
      if (!mounted) return;
    }
    await DriveLog.start(); // (11/19) 운행 한 번의 시작 — 홈 리포트 '운행 1 · 운행 2' 를 나누는 기준
    if (!mounted) return;
    AuthService.saveEyeThreshold(
      t,
    ).ignore(); // 앱을 껐다 켜고 [이어서 운행]으로 들어올 때 같은 기준을 쓰도록 폰에 저장
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            (widget.driveBuilder ?? (t) => DriveScreen(threshold: t))(t),
      ),
    );
    if (mounted) _reload(); // 운행 중 새로 생긴 경고가 '최근 경고'에 바로 보이게
  }

  // [이어서 운행] — 측정 화면을 건너뛰고 운행 화면으로. 서버가 기억하는 단계 · 휴식을 그대로 이어받는다
  Future<void> _resumeDrive(DriveState state) async {
    final saved =
        await AuthService.getEyeThreshold(); // 측정할 때 저장해 둔 내 눈 기준 (없으면 null → 기본 기준)
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            (widget.resumeBuilder ??
            (st) => DriveScreen(resume: st, threshold: saved))(state),
      ),
    );
    if (mounted) _reload();
  }

  // ── 화면 (Figma 시안 '졸음운전 감지 앱2' 홈 — 디자인만 바꿈. 배너 · 단계 계산 · 최근 경고 불러오기는 위 함수 그대로) ──
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      // (11/19 사용자 요청) 아래로 스크롤하면 '김기사 기사님' 머리줄 아래에서 카드가 네모나게 뚝 잘리던 것 →
      //   위쪽 28 만큼 부드럽게 사라지게 (선 · 모서리 없이)
      //   (맨 위에 있을 때는 흐려지지 않게 — 내렸을 때만)
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          final down = n.metrics.pixels > 2;
          if (n.depth == 0 && down != _scrolled) setState(() => _scrolled = down);
          return false;
        },
        child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: _scrolled
              ? const [Color(0x00000000), Color(0x00000000), Color(0xFF000000)]
              : const [Color(0xFF000000), Color(0xFF000000), Color(0xFF000000)],
          stops: [0, (6 / r.height).clamp(0.0, 1.0), (40 / r.height).clamp(0.0, 1.0)],
        ).createShader(r),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28), // (11/23 리디자인_2) 탭바가 고정이라 여백만
        children: [
          // 지금 상태 카드 (11/16 R안 · readdy 흰 카드) + 운행 요약 숫자 + 버튼
          FutureBuilder<DriveState?>(
            future: _driveState,
            builder: (context, drive) => FutureBuilder<List<SleepEvent>?>(
              future: _recent,
              builder: (context, snapshot) {
                final st = drive.data;
                final active = st?.active ?? false;
                return HomeStateCard(
                  // (11/16 팀장) 서버가 아는 단계를 먼저 — 아래 [이어서 운행]과 같은 답이라 어긋나지 않음.
                  //   서버에 못 물어봤을 때(연결 끊김)만 경고 기록으로 가늠 (currentStage)
                  stage: st?.stage ?? currentStage(snapshot.data),
                  onStart: _startDrive,
                  idle: !active, // 운행 전이면 '정상' · '안전 운전 중이에요' 없이

                  // 진행 중인 운행이 있으면 운행 시간 · 오늘 졸음 · 휴식 숫자 (readdy 운행 요약)
                  stats: active ? _stats(st!, snapshot.data) : const [],
                  // (11/16 팀장) 진행 중인 운행이 있으면 [운행 시작] 자리에 [이어서 운행] + [새로운 운행 시작]
                  //   (11/16 사용자 요청 3) 두 버튼을 작게
                  resume: active
                      ? _ResumeInCard(
                          state: st!,
                          onResume: () => _resumeDrive(st),
                          onNew: _startDrive,
                        )
                      : null,
                );
              },
            ),
          ),
          const SizedBox(height: 16), // (11/23 사용자 요청) 운행 카드 아래로 시스템 알약 · 여백 넉넉하게
          // (11/23 기업용 리디자인) 맨 위 = 시스템 상태 (Samsara Driver 홈처럼 '장치가 제대로 도는지' 먼저)
          FutureBuilder<DriveState?>(
            future: _driveState,
            builder: (context, d) => SystemStatusCard(
              driving: d.data?.active ?? false,
              checks: [
                SystemCheck(Icons.videocam_outlined, '카메라', _perms?[0], badText: '권한 필요'),
                SystemCheck(Icons.mic_none_rounded, '음성 안내', _perms?[1], badText: '권한 필요'),
                SystemCheck(Icons.location_on_outlined, '위치', _perms?[2], badText: '권한 필요'),
                SystemCheck(Icons.cloud_outlined, '관제 서버', _online, badText: '끊김'),
              ],
            ),
          ),
          // (11/23 사용자 요청) '운행 기록' 제목은 빼고 카드를 위로
          const SizedBox(height: 20),
          // (11/17 관리자 웹 홈) 숫자 칸 3개 (오늘 경고 · 이번 주 · 긴급) — 누른 칸의 경고 목록이 바로 아래에
          FutureBuilder<List<SleepEvent>?>(
            future: _recent,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return HomeEmptyCard(
                  title: '최근 경고를 불러오지 못했어요',
                  sub: '잠시 뒤 다시 시도해 주세요',
                  actionText: '다시 시도',
                  onAction: _reload,
                );
              }
              final events = snapshot.data;
              if (events == null)
                return const HomeEmptyCard(title: '최근 경고 불러오기는 준비 중이에요');
              // (11/17 사용자 요청) 경고가 하나도 없어도 숫자 칸(오늘 · 이번 주 · 긴급 0건)은 그대로 보여 준다
              final now = DateTime.now();
              final dayStart = DateTime(now.year, now.month, now.day);
              final weekStart = dayStart.subtract(Duration(days: now.weekday % 7)); // 일요일부터
              bool fromDay(SleepEvent e) => !e.createdAt.toLocal().isBefore(dayStart);
              bool fromWeek(SleepEvent e) => !e.createdAt.toLocal().isBefore(weekStart);
              final todayN = events.where(fromDay).length;
              var weekN = events.where(fromWeek).length;
              var urgentN = events.where((e) => e.stage >= 3).length;
              return FutureBuilder<List<DriveSpan>>(
                future: _spans,
                builder: (context, spanSnap) {
                  // (11/19 사용자 요청) 경고를 '운행 한 번'(운행 시작 ~ 운행 종료) 씩 묶어서 보여 줌
                  final all = groupDrives(events, spanSnap.data ?? const []);
                  bool inToday(DriveGroup g) => !g.last.isBefore(dayStart);
                  bool inWeek(DriveGroup g) => !g.last.isBefore(weekStart);
                  // (11/23 사용자 요청) 모두 최신이 맨 위 (시작 시각 기준으로 확실히 정렬)
                  int latest(DriveGroup a, DriveGroup b) => b.last.compareTo(a.last);
                  final lists = [
                    all.where(inToday).toList()..sort(latest), // 오늘
                    all.where(inWeek).toList()..sort(latest), // 이번 주 → 아래에서 요일별로 묶음
                    all.where((g) => g.hasUrgent).toList()..sort(latest), // 긴급 — 3단계가 있었던 운행 · 최신순
                  ];
                  // (11/23 사용자 요청) 칸 = 오늘 경고 · 총 운행 시간(표) · 휴식(언제 · 몇 번째 운행 · 몇 시)
                  final today = lists[0];
                  // 끝 기록이 없는 예전 운행은 마지막 경고 시각까지만 (지금 운행 중인 맨 위 운행만 지금까지)
                  var totalMin = 0;
                  final liveG = today.where((g) => g.end == null).fold<DriveGroup?>(null, (p, g) => p == null || g.start.isAfter(p.start) ? g : p);
                  for (final g in today) {
                    totalMin += _DriveTimeTable.minutesOf(g, live: identical(g, liveG));
                  }
                  final totalLabel = '${totalMin ~/ 60}:${(totalMin % 60).toString().padLeft(2, '0')}';
                  final rests = <(String, String, int, int?)>[]; // 시작 · 재개 · 분 · 운행 번호
                  for (final e in events.where(fromDay)) {
                    final r = e.report['rest'];
                    if (r is! Map) continue;
                    final g = all.where((g) => g.events.any((x) => x.id == e.id)).firstOrNull;
                    rests.add(('${r['started'] ?? ''}', '${r['resumed'] ?? ''}', (r['minutes'] is num) ? (r['minutes'] as num).toInt() : 0, g?.number));
                  }
                  rests.sort((a, b) => b.$1.compareTo(a.$1));
                  final shown = today;
                  final rows = <Widget>[
                    if (_tab == 1) ...[
                      if (today.isNotEmpty) _DriveTimeTable(groups: today, totalLabel: totalLabel),
                    ] else if (_tab == 2)
                      for (final (i, r) in rests.indexed) _RestRow(rest: r, header: i == 0)
                    else
                      for (final g in shown) _DriveCard(group: g),
                  ];
                  weekN = totalMin; // 아래 칸 글에 씀
                  urgentN = rests.length;
                  final visible = _expanded ? rows.length : rows.length.clamp(0, _driveCount);
                  // (11/23 사용자 요청) 안내는 카드 밖 아래 — 카드 안 글과 같은 시작선
                  return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _recordCard(context, rows, visible, shown, now, todayN, weekN, urgentN),
                    const Padding(
                      padding: EdgeInsets.only(top: 12, left: 6), // (11/24 사용자 요청) 카드 시작선에서 아주 조금 안쪽
                      child: Text('› 를 누르면 AI 분석 보고서를 볼 수 있어요', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
                    ),
                  ]);
                },
              );
            },
          ),
        ],
      ),
      ),
      ),
    );
  }

  Widget _recordCard(BuildContext context, List<Widget> rows, int visible, List<DriveGroup> shown, DateTime now, int todayN, int weekN, int urgentN) {
    const empties = ['오늘은 운행 기록이 없어요', '오늘은 운행 기록이 없어요', '오늘은 쉰 기록이 없어요'];
                  return WebCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        // (11/23 사용자 요청) 보내 준 사진 — 오늘 · 이번 주 · 긴급 숫자 칸 + 고른 칸 밑줄
                        StatTabs(
                          selected: _tab,
                          onSelect: (i) => setState(() {
                            _tab = i;
                            _expanded = false;
                          }),
                          items: [
                            // (11/23 사용자 요청) 숫자 없이 제목만
                            StatItem('${now.month}/${now.day}', '', ''),
                            const StatItem('총 운행 시간', '', ''),
                            const StatItem('휴식', '', ''),
                          ],
                        ),
                        // (11/18 사용자 요청) 칸을 바꾸면 목록이 옆으로 부드럽게 미끄러짐 · 목록을 옆으로 밀어도 바뀜
                        SlideSwitcher(
                          index: _tab,
                          onSwipe: (d) => setState(() => _tab = (_tab + d).clamp(0, 2)),
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4), // (11/19) 애플 목록 — 줄마다 넉넉한 여백
                            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                              if (shown.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                      child: Text(empties[_tab], style: const TextStyle(fontSize: 14, color: AppColors.textMuted))),
                                ),
                              for (var i = 0; i < visible; i++) rows[i], // (11/19) 줄 사이 선 없음
                              // [n개 운행 전체 보기] ↔ [접기] — 그 자리에서 펼치고 접음
                              if (_tab == 0 && rows.length > _driveCount) ...[
                                const _CenterLine(),
                                TextButton(
                                  onPressed: () => setState(() => _expanded = !_expanded),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.textPrimary, // (11/23) 검정(블랙 네이비) 글씨
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(_expanded ? '접기' : (_tab == 1 ? '${rows.length}일 전체 보기' : '운행 ${rows.length}번 전체 보기'),
                                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                                    const SizedBox(width: 2),
                                    Icon(_expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded, size: 20),
                                  ]),
                                ),
                              ],
                            ]),
                          ),
                        ),
                      ],
                    ),
                  );
  }
}

/// (11/19 사용자 손그림 시안 · 애플 목록) 운행 한 번 = 흰 카드 안 한 줄 (테두리 없음 · 넉넉한 여백)
///   왼쪽(가운데 정렬): '운행_1' · 아래 시간  |  세로선  |  오른쪽: '1단계 | 주의' 둥근 알약 3개 + 아래 큰 숫자  |  ›
class _DriveCard extends StatelessWidget {
  final DriveGroup group;
  const _DriveCard({required this.group});

  static String _hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String timeRange(DriveGroup g) {
    if (g.end == null) return '${_hm(g.start)} ~ 운행 중';
    // 기록 없이 짐작한 운행에 경고가 하나뿐이면 시각 하나만 ('15:24 ~ 15:24' 대신)
    if (_hm(g.start) == _hm(g.end!)) return _hm(g.start);
    return '${_hm(g.start)} ~ ${_hm(g.end!)}';
  }

  @override
  Widget build(BuildContext context) {
    final g = group;
    return InkWell(
      // (11/23 UX) 경고가 하나뿐인 운행은 바로 AI 보고서 — 누르는 단계 줄이기
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => g.events.length == 1 ? EventDetailScreen(event: g.events.first) : _DriveDetailScreen(group: g))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10), // (11/23) state 느낌 — 낮고 단정하게
        child: SizedBox(
          height: 64,
          child: Row(children: [
            // 왼쪽 — '운행_1' · 아래 시간 (가운데 정렬)
            SizedBox(
              width: 66,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('운행',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary)),
                  const SizedBox(width: 5),
                  _CircleNum(g.number),
                ]),
                const SizedBox(height: 5),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(timeRange(g),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted, fontFeatures: [FontFeature.tabularFigures()])),
                ),
              ]),
            ),
            const VerticalDivider(width: 17, thickness: 1, indent: 10, endIndent: 10, color: AppleGray.opaqueSeparator),
            // 오른쪽 — 단계 3칸 격자 (칸 사이 세로선)
            Expanded(child: _StageGrid(g.count)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppleGray.chevron),
          ]),
        ),
      ),
    );
  }
}

/// (11/19) 운행 번호 — 애플 '1.circle.fill' 처럼 작고 동그란 칩 (연한 남색 바탕 · 남색 숫자)
class _CircleNum extends StatelessWidget {
  final int n;
  final double size;
  const _CircleNum(this.n, {this.size = 16});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.navy.withValues(alpha: 0.1)), // (11/23 사용자 요청) 연한 남색 동그라미 · 남색 숫자
        child: Text('$n',
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(fontSize: size * 0.62, height: 1, forceStrutHeight: true),
            style: TextStyle(fontSize: size * 0.62, height: 1, fontWeight: FontWeight.w700, color: AppColors.navy)),
      );
}

/// 단계 하나 — (11/23 state 느낌) 위 작은 점 · 이름 / 아래 숫자 (0 은 흐리게)
class _StageCount extends StatelessWidget {
  final int stage;
  final int count;
  const _StageCount({required this.stage, required this.count});

  @override
  Widget build(BuildContext context) {
    final zero = count == 0;
    final c = AppColors.stage(stage);
    const names = ['', '주의', '휴식 권고', '긴급'];
    return Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.center, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 7, height: 7, decoration: BoxDecoration(color: zero ? c.withValues(alpha: 0.4) : c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(names[stage],
              style: AppType.caption.copyWith(fontWeight: FontWeight.w600, color: zero ? AppleGray.tertiaryLabel : AppColors.textSecondary)), // (11/23 사용자 요청) 글자 색 뺌
        ]),
      ),
      const SizedBox(height: 6),
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$count',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, fontFeatures: AppStatus.figures,
                  color: zero ? AppleGray.chevron : (stage >= 3 ? AppStatus.danger : AppColors.textPrimary))),
          TextSpan(
              text: '건',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: zero ? AppleGray.chevron : AppColors.textSecondary)),
        ]),
      ),
    ]);
  }
}

/// 단계 3칸 — 칸 사이 세로 구분선 (홈 시스템 state 와 같은 격자)
class _StageGrid extends StatelessWidget {
  final int Function(int stage) count;
  const _StageGrid(this.count);
  @override
  Widget build(BuildContext context) => Row(children: [
        for (final st in const [1, 2, 3]) ...[
          if (st > 1) const VerticalDivider(width: 1, thickness: 1, indent: 10, endIndent: 10, color: AppleGray.opaqueSeparator),
          Expanded(child: _StageCount(stage: st, count: count(st))),
        ],
      ]);
}

const _weekNames = ['월', '화', '수', '목', '금', '토', '일'];
String _dayLabel(DateTime d) => '${d.month}/${d.day} (${_weekNames[d.weekday - 1]})';

/// 운행들을 날짜별로 — 최신 날짜가 위 · 날 안에서는 최신 운행이 위
List<(DateTime, List<DriveGroup>)> _byDay(List<DriveGroup> groups) {
  final map = <DateTime, List<DriveGroup>>{};
  for (final g in groups) {
    final t = g.last;
    map.putIfAbsent(DateTime(t.year, t.month, t.day), () => []).add(g);
  }
  final days = map.keys.toList()..sort((a, b) => b.compareTo(a));
  return [for (final d in days) (d, map[d]!..sort((a, b) => b.last.compareTo(a.last)))];
}

/// (11/23 사용자 요청) 이번 주 — 하루 한 줄 (날짜 · 요일 · 운행 횟수 / 단계별 합) · › 누르면 그날 리포트
class _DayCard extends StatelessWidget {
  final DateTime day;
  final List<DriveGroup> groups;
  const _DayCard({required this.day, required this.groups});

  int _sum(int st) => groups.fold(0, (n, g) => n + g.count(st));

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DayReportScreen(day: day, groups: groups))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        child: SizedBox(
          height: 64,
          child: Row(children: [
            SizedBox(
              width: 72,
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(_dayLabel(day),
                    style: AppType.subheadline.copyWith(height: 1.2, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text('운행 ${groups.length}번', style: AppType.caption.copyWith(color: AppColors.textMuted)),
              ]),
            ),
            const VerticalDivider(width: 17, thickness: 1, indent: 10, endIndent: 10, color: AppleGray.opaqueSeparator),
            Expanded(child: _StageGrid(_sum)),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppleGray.chevron),
          ]),
        ),
      ),
    );
  }
}

/// (11/23 사용자 요청) 하루 리포트 — 그날 단계별 합 · 운행 목록 · 경고 타임라인 (최신이 위)
class _DayReportScreen extends StatelessWidget {
  final DateTime day;
  final List<DriveGroup> groups;
  const _DayReportScreen({required this.day, required this.groups});

  @override
  Widget build(BuildContext context) {
    final events = [for (final g in groups) ...g.events]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    int sum(int st) => groups.fold(0, (n, g) => n + g.count(st));
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.only(top: 26, bottom: 12, left: 16), // (11/23 사용자 요청) 카드 안 글과 같은 시작선
          child: Text(t, style: AppType.title3.copyWith(color: AppColors.textPrimary)),
        );
    return Scaffold(
      appBar: AppBar(titleSpacing: 0, centerTitle: false, title: Text('${day.month}월 ${day.day}일 (${_weekNames[day.weekday - 1]}) 리포트')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          // 요약 — 운행 횟수 + 단계별 합 (state 격자)
          WebCard(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6), // (11/23) 위아래 여백 같게
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.navy),
                const SizedBox(width: 6),
                Text('운행 ${groups.length}번 · 경고 ${events.length}건',
                    style: AppType.subheadline.copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
              const SizedBox(height: 10),
              Container(height: 1, color: AppleGray.opaqueSeparator),
              SizedBox(height: 66, child: _StageGrid(sum)), // (11/23) 넘침 고침
            ]),
          ),
          heading('운행'),
          WebCard(
            padding: EdgeInsets.zero,
            child: Column(children: [for (final g in groups) _DriveCard(group: g)]),
          ),
          heading('경고 타임라인'),
          WebCard(
            padding: EdgeInsets.zero,
            child: events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('경고 없이 운행했어요', style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
                  )
                : Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (var i = 0; i < events.length; i++)
                        HistoryEventRow(event: events[i], first: i == 0, last: i == events.length - 1),
                    ]),
                  ),
          ),
          // (11/23 사용자 요청) 마지막 칸 밑 안내 — 카드 안 글 시작선
          const Padding(
            padding: EdgeInsets.only(top: 12, left: 6), // (11/24 사용자 요청) 카드 시작선에서 아주 조금 안쪽
            child: Text('› 를 누르면 AI 분석 보고서를 볼 수 있어요', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
          ),
        ],
      ),
    );
  }
}

/// 운행 한 번의 경고 목록 (카드를 누르면)
class _DriveDetailScreen extends StatelessWidget {
  final DriveGroup group;
  const _DriveDetailScreen({required this.group});

  @override
  Widget build(BuildContext context) {
    final g = group;
    final events = [...g.events]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0, // (11/23 사용자 요청) '<' 바로 옆 왼쪽
        centerTitle: false,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('운행', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          _CircleNum(g.number, size: 22),
        ]),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 12),
            child: Text('${g.start.month}월 ${g.start.day}일 · ${_DriveCard.timeRange(g)}',
                style: AppType.subheadline.copyWith(color: AppColors.textSecondary)),
          ),
          WebCard(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: SizedBox(height: 64, child: _StageGrid(g.count)),
          ),
          const SizedBox(height: 14),
          WebCard(
            padding: EdgeInsets.zero,
            child: events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('경고 없이 운행했어요', style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
                  )
                : Padding(
                    // (11/19 사용자 요청) 운행 기록 탭과 같은 타임라인 — 이 운행의 경고만 · 최신이 위
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(children: [
                      for (var i = 0; i < events.length; i++)
                        HistoryEventRow(
                            event: events[events.length - 1 - i], first: i == 0, last: i == events.length - 1),
                    ]),
                  ),
          ),
        ],
      ),
    );
  }
}

/// 운행 요약 숫자 (11/16 R안 · readdy) — 운행 시간 · 오늘 졸음 · 휴식
List<(String, String)> _stats(DriveState st, List<SleepEvent>? events) {
  final h = st.driveMin ~/ 60, m = st.driveMin % 60;
  final now = DateTime.now();
  final today = (events ?? const <SleepEvent>[])
      .where((e) => e.createdAt.year == now.year && e.createdAt.month == now.month && e.createdAt.day == now.day)
      .length;
  final rest = st.resting ? '${(st.restLeftSec / 60).ceil()}분' : '—';
  return [('$h:${m.toString().padLeft(2, '0')}', '운행 시간'), ('$today회', '졸음'), (rest, st.resting ? '휴식 남음' : '휴식')];
}

/// [이어서 운행] (남색) + [새로운 운행 시작] (회색) — 상태 카드 맨 아래 (11/16 R안, 사용자 요청 3: 버튼 작게)
/// 카드 폭의 88% 가운데 얇은 선 (좌우 6%씩 비움)
class _CenterLine extends StatelessWidget {
  const _CenterLine();
  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, c) => Divider(
            height: 1, thickness: 1, indent: c.maxWidth * 0.06, endIndent: c.maxWidth * 0.06, color: AppColors.line),
      );
}

class _ResumeInCard extends StatelessWidget {
  final DriveState state;
  final VoidCallback onResume;
  final VoidCallback onNew;
  const _ResumeInCard({required this.state, required this.onResume, required this.onNew});

  @override
  Widget build(BuildContext context) {
    // (11/18 사용자 요청) 상태 설명 글(관리자 조치 · 휴식 안내)은 빼고 알림으로. 두 버튼은 같은 크기 · 같은 알약 모양
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // (11/18 사용자 요청) 운행 전과 같은 자리 — 위 [운행 시작] · 아래 [이어서 운행]. 지금 할 일(이어서 운행)이 남색
        // (11/18 피드백) 순서 바꿈 — 지금 할 일 [이어서 운행] 이 위, [새로운 운행 시작] 이 맨 아래
        AuthButton(
          text: '이어서 운행',
          onPressed: onResume,
          height: AppSize.button,
          contentWidth: 160,
          leading: const Icon(Icons.redo_rounded, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 12),
        AuthButton(
          text: '새로운 운행 시작',
          primary: false,
          onPressed: onNew,
          height: AppSize.button,
          contentWidth: 160,
          leading: const Icon(Icons.play_arrow_rounded, size: 22, color: AppColors.textPrimary),
        ),
      ],
    );
  }

}

/// 예전 [이어서 운행] 흰 상자 (안 씀 — 되돌릴 때 참고)
// ignore: unused_element
class _OldResumeInCard extends StatelessWidget {
  final DriveState state;
  final VoidCallback onResume;
  const _OldResumeInCard({required this.state, required this.onResume});

  String get _detail {
    if (state.resting) {
      final min = (state.restLeftSec / 60).ceil();
      return state.restLeftSec <= 0
          ? '충분히 쉬었어요\n[운행 재개]를 눌러 주세요'
          : '쉬는 중이에요 (약 $min분 남음)';
    }
    if (state.stage >= 3) return '관리자가 조치하기 전까지 3단계가 이어져요.';
    if (state.stage == 2) return '쉬어야 2단계가 풀려요.';
    return '운행 중이던 상태 그대로 이어서 운행해요.';
  }

  // (11/16 팀장) 남색 카드 안의 흰 상자 — 바꾸기 전 배너 모양 그대로 (흰 바탕 · 단계 색 테두리) + 남색 [이어서 운행]
  @override
  Widget build(BuildContext context) {
    final color = AppColors.stage(state.stage);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: state.stage >= 1 ? color : AppColors.cardBorder,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '진행 중인 운행이 있어요',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _detail,
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text(
              '이어서 운행',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.navy,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 최근 경고 한 줄 (시안의 흰 카드 모양 — 모서리 18, 왼쪽 단계 동그라미)
// ignore: unused_element
class _EventTile extends StatelessWidget {
  final SleepEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    // (11/15) 누르면 경고 기록 상세 (졸음 사진 + AI 분석 결과)
    // (11/16 R안 · readdy) 왼쪽 단계 색 막대 · 이유(굵게) + 단계 표 · 시각(검정, 사용자 요청 8) · 오른쪽 동그란 꺾쇠
    // (11/17 관리자 웹 홈 목록 한 줄) 왼쪽 이유 · 시각, 오른쪽 '● n단계 | 이름' 알약 + 꺾쇠
    return InkWell(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        child: Row(
          children: [
            // (11/18 피드백) 왼쪽 단계 색 세로선 — 아이폰 캘린더 일정처럼 둥근 막대 (글 시작선은 모두 이 막대 뒤 같은 자리)
            // (11/19 Headspace 목록) 왼쪽 네모 그림 칸 — 반투명 단계 색 바탕 + 작은 동그란 캐릭터
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppIllust.thumb(event.stage.clamp(1, 3)), borderRadius: BorderRadius.circular(AppRadius.card)),
              child: Buddy(stage: event.stage.clamp(1, 3), size: 32, breathe: false),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(event.reasonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(event.createdLabel, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            // (11/18 피드백) 단계 배지 시작점을 줄마다 맞춤 — 같은 폭 칸 안에서 왼쪽부터
            // (11/18 피드백) 단계 배지는 오른쪽 끝 정렬 (꺾쇠 바로 앞 · 줄마다 끝점이 같게)
            StageBadge(stage: event.stage),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron),
          ],
        ),
      ),
    );
  }

  // 예전 흰 카드 한 줄 (안 씀 — 되돌릴 때 참고)
  // ignore: unused_element
  Widget _old(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => EventDetailScreen(event: event)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(
            color: event.isUrgent ? AppColors.urgent : AppColors.cardBorder,
          ),
        ),
        child: Row(
          children: [
            const Buddy(stage: 0, size: 42, breathe: false),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${event.stageLabel} · ${event.reasonLabel}',
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    event.summary.isEmpty ? event.status : event.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              event.createdLabel,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// (11/23 사용자 요청) 총 운행 시간 — 표 (운행 · 시간 · 운행 시간 모두 가운데 정렬) / 맨 아래 합계
class _DriveTimeTable extends StatelessWidget {
  final List<DriveGroup> groups;
  final String totalLabel;
  const _DriveTimeTable({required this.groups, required this.totalLabel});

  // 운행 한 번 시간 — 끝 기록이 있으면 끝까지 · 지금 운행 중이면 지금까지 · 끝 기록이 없는 예전 운행은 마지막 경고까지 (한 번에 최대 10시간)
  static int minutesOf(DriveGroup g, {bool live = false}) {
    final end = g.end ?? (live && DateTime.now().difference(g.start).inHours < 12 ? DateTime.now() : g.last);
    return end.difference(g.start).inMinutes.clamp(0, 600);
  }

  static String _dur(DriveGroup g, {bool live = false}) {
    final m = minutesOf(g, live: live);
    return m < 1 ? '1분 미만' : (m >= 60 ? '${m ~/ 60}시간 ${m % 60}분' : '$m분');
  }

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted);
    const num = [FontFeature.tabularFigures()];
    Widget cell(Widget w) => Expanded(child: Center(child: w));
    final liveI = groups.indexWhere((x) => x.end == null);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        SizedBox(
          height: 32,
          child: Row(children: [cell(const Text('운행', style: head)), cell(const Text('시간', style: head)), cell(const Text('운행 시간', style: head))]),
        ),
        for (final (i, g) in groups.indexed) ...[
          const Divider(height: 1, thickness: 1, color: AppColors.line),
          SizedBox(
            height: 46,
            child: Row(children: [
              cell(Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('운행', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(width: 5),
                _CircleNum(g.number),
              ])),
              cell(FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(_DriveCard.timeRange(g), style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontFeatures: num)),
              )),
              cell(Text(_dur(g, live: i == liveI), style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontFeatures: num))), // (11/24 사용자 요청) 옆 '17:50' 시간 글씨와 같게 · 합계만 굵게
            ]),
          ),
        ],
        const Divider(height: 1, thickness: 1.5, color: AppColors.cardBorder),
        SizedBox(
          height: 48,
          child: Row(children: [
            cell(const Text('합계', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
            const Expanded(child: SizedBox()),
            cell(Text(totalLabel, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.navy, fontFeatures: num))),
          ]),
        ),
      ]),
    );
  }
}

/// (11/23 사용자 요청) 휴식 표 — 휴식 시간 · 운행 · 쉰 시간 (모두 가운데 정렬) · 틀 없는 갈색 커피잔
class _RestRow extends StatelessWidget {
  final (String, String, int, int?) rest;
  final bool header;
  const _RestRow({required this.rest, this.header = false});

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textMuted);
    Widget cell(Widget w) => Expanded(child: Center(child: w));
    final (start, end, min, no) = rest;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(children: [
        if (header)
          SizedBox(
            height: 40,
            child: Row(children: [cell(const Text('시간', style: head)), cell(const Padding(padding: EdgeInsets.only(left: 16), child: Text('운행', style: head))), cell(const Text('총 휴식 시간', style: head))]),
          ),
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        SizedBox(
          height: 52,
          child: Row(children: [
            cell(Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(child: FittedBox( // (11/24) 칸이 좁으면 글자를 줄임 (넘침 고침)
                fit: BoxFit.scaleDown,
                child: Text(end.isEmpty ? '$start 부터' : '$start ~ $end',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, fontFeatures: [FontFeature.tabularFigures()])), // (11/24 사용자 요청) '1번째 운행' 과 같은 글씨
              )),
            ])),
            // (11/24 사용자 요청) 가운데 열을 조금 오른쪽으로
            cell(Padding(padding: const EdgeInsets.only(left: 16), child: Text(no == null ? '—' : '$no번째 운행', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)))),
            cell(Text(min < 1 ? '1분 미만' : '$min분', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary))), // (11/24 사용자 요청) 쉰 시간만 원래대로 (검정)
          ]),
        ),
      ]),
    );
  }
}
