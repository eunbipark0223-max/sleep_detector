// ═══════════════════════════════════════════════════════════════
// screens/home_screen.dart — 홈
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/home_screen.dart (🟡 버튼 변경)
//
// [이 파일이 하는 일]
//   - [운행 시작] → calibration_screen (내 눈 기준 측정) → drive_screen
//   - [사진 1장 테스트] 는 ≡ 메뉴로 옮김 (main_screen, 11/11 — 기사님 홈에는 운전에 필요한 것만)
//   - [가까운 졸음쉼터] → map_screen (B 의 카카오맵 지도)
//   - 최근 경고 2~3건 (GET /events/my). 운행 · 사진 1장 테스트에서 돌아오면 다시 불러온다
//   - 맨 위 상태 카드: 내 경고 기록으로 가늠한 지금 단계 (currentStage — 3단계는 조치완료 전까지, 2단계는 휴식 전까지, 1단계는 10분)
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
import '../theme.dart';
import '../widgets/owl_says.dart';
import '../widgets/home_ui.dart';
import 'calibration_screen.dart';
import 'drive_screen.dart';

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

  const HomeScreen(
      {super.key, this.loadEvents, this.calibrationBuilder, this.driveBuilder, this.loadDriveState, this.resumeBuilder,
      this.onOpenRecords});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const int _recentCount = 3;

  // 출발 준비: 카메라 · 마이크 권한 (허용하면 초록, 11/12 시안 '졸음운전 감지 앱4'). null = 아직 확인 전
  bool? _camOk;
  bool? _micOk;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPerms();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // 설정 화면 · 권한 창에서 돌아오면 다시 확인
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkPerms();
  }

  Future<void> _checkPerms() async {
    try {
      final cam = await Permission.camera.isGranted;
      final mic = await Permission.microphone.isGranted;
      if (!mounted) return;
      setState(() {
        _camOk = cam;
        _micOk = mic;
      });
    } catch (_) {}
  }

  /// 카메라 · 마이크 · 위치 중 아직 없는 권한을 안내창 → 휴대폰 권한 창으로 받는다.
  /// 안내창을 닫으면 false. 두 번 거절해 휴대폰이 더는 묻지 않으면 앱 설정 화면을 연다.
  Future<bool> _askPermissions() async {
    try {
      const perms = [Permission.camera, Permission.microphone, Permission.locationWhenInUse];
      final need = <Permission>[
        for (final p in perms)
          if (!await p.isGranted) p,
      ];
      if (need.isEmpty) return true;
      if (!mounted) return false;
      final ok = await showPermissionSheet(
        context,
        camera: need.contains(Permission.camera),
        mic: need.contains(Permission.microphone),
        location: need.contains(Permission.locationWhenInUse),
      );
      if (ok != true) return false; // 안내창을 닫음
      final result = await need.request(); // 한 번의 요청 → 시스템 창이 이어서 뜬다
      if (result.values.any((st) => st.isPermanentlyDenied)) await openAppSettings();
    } catch (_) {
      // 권한 확인이 안 되는 폰이어도 계속 (카메라는 측정 화면이 다시 확인)
    } finally {
      await _checkPerms();
    }
    return true;
  }

  late Future<List<SleepEvent>?> _recent = _fetch();
  late Future<DriveState?> _driveState = _fetchDriveState();

  // 앱을 껐다 켰을 때 서버가 기억하는 운행 상태. 못 받으면 (서버 연결 오류 등) null — 배너만 안 뜨고 홈은 그대로
  Future<DriveState?> _fetchDriveState() {
    final future = (widget.loadDriveState ?? _defaultLoadDriveState)().catchError((_) => null);
    return future;
  }

  static Future<DriveState?> _defaultLoadDriveState() => ApiService.fetchDriveState();

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
    });
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
      if (e.status == '조치완료' && (resetAt == null || e.createdAt.isAfter(resetAt))) resetAt = e.createdAt;
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
        1 => age <= const Duration(minutes: 10) && age >= const Duration(minutes: -1),
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
      MaterialPageRoute(builder: (_) => (widget.calibrationBuilder ?? () => const CalibrationScreen())()),
    );
    if (t == null || !mounted) return;
    AuthService.saveEyeThreshold(t).ignore(); // 앱을 껐다 켜고 [이어서 운행]으로 들어올 때 같은 기준을 쓰도록 폰에 저장
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => (widget.driveBuilder ?? (t) => DriveScreen(threshold: t))(t)),
    );
    if (mounted) _reload(); // 운행 중 새로 생긴 경고가 '최근 경고'에 바로 보이게
  }

  // [이어서 운행] — 측정 화면을 건너뛰고 운행 화면으로. 서버가 기억하는 단계 · 휴식을 그대로 이어받는다
  Future<void> _resumeDrive(DriveState state) async {
    final saved = await AuthService.getEyeThreshold(); // 측정할 때 저장해 둔 내 눈 기준 (없으면 null → 기본 기준)
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) => (widget.resumeBuilder ?? (st) => DriveScreen(resume: st, threshold: saved))(state)),
    );
    if (mounted) _reload();
  }

  // ── 화면 (Figma 시안 '졸음운전 감지 앱2' 홈 — 디자인만 바꿈. 배너 · 단계 계산 · 최근 경고 불러오기는 위 함수 그대로) ──
  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
        children: [
          // 앱을 껐다 켠 뒤에도 진행 중인 운행(2 · 3단계 · 휴식 중 · 방금까지 운행)이 있으면 이어서 운행하는 배너
          FutureBuilder<DriveState?>(
            future: _driveState,
            builder: (context, snapshot) {
              final state = snapshot.data;
              if (state == null || !state.active) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ResumeBanner(state: state, onResume: () => _resumeDrive(state)),
              );
            },
          ),
          // 지금 상태 카드 (남색) + [운행 시작]
          FutureBuilder<List<SleepEvent>?>(
            future: _recent,
            builder: (context, snapshot) => HomeStateCard(
              stage: currentStage(snapshot.data),
              onStart: _startDrive,
            ),
          ),
          const SizedBox(height: 18),
          // 출발 준비 (시안 '졸음운전 감지 앱4') — 카메라 · 마이크 권한을 허용하면 그 칸이 초록. 누르면 권한 받기
          HomeReadyRow(camera: _camOk ?? false, voice: _micOk ?? false, onTap: _askPermissions),
          const SizedBox(height: 14),
          // 최근 경고
          HomeSectionHeading(
            title: '최근 경고',
            trailing: widget.onOpenRecords == null
                ? null
                : TextButton(
                    onPressed: widget.onOpenRecords,
                    style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary, minimumSize: const Size(0, 44)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('전체 보기', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        Icon(Icons.chevron_right, size: 18),
                      ],
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          FutureBuilder<List<SleepEvent>?>(
            future: _recent,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return HomeEmptyCard(
                    title: '최근 경고를 불러오지 못했어요', sub: '잠시 뒤 다시 시도해 주세요', actionText: '다시 시도', onAction: _reload);
              }
              final events = snapshot.data;
              if (events == null) return const HomeEmptyCard(title: '최근 경고 불러오기는 준비 중이에요');
              if (events.isEmpty) {
                return const HomeEmptyCard(title: '최근 경고가 없어요', sub: '안전한 운전을 이어가고 있어요');
              }
              final latest = [...events]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
              return Column(children: [for (final e in latest.take(_recentCount)) _EventTile(event: e)]);
            },
          ),
        ],
      ),
    );
  }
}

/// [이어서 운행] 배너 — 서버가 기억하는 진행 중인 운행 (GET /drive/state)
class _ResumeBanner extends StatelessWidget {
  final DriveState state;
  final VoidCallback onResume;
  const _ResumeBanner({required this.state, required this.onResume});

  String get _detail {
    if (state.resting) {
      final min = (state.restLeftSec / 60).ceil();
      return state.restLeftSec <= 0 ? '충분히 쉬었어요. [운행 재개]를 눌러 주세요.' : '쉬는 중이에요 (약 $min분 남음)';
    }
    if (state.stage >= 3) return '관리자가 조치하기 전까지 3단계가 이어져요.';
    if (state.stage == 2) return '쉬어야 2단계가 풀려요.';
    return '운행 중이던 상태 그대로 이어서 운행해요.';
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.stage(state.stage);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: state.stage >= 1 ? color : AppColors.cardBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('진행 중인 운행이 있어요',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_detail, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('이어서 운행'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 최근 경고 한 줄 (시안의 흰 카드 모양 — 모서리 18, 왼쪽 단계 동그라미)
class _EventTile extends StatelessWidget {
  final SleepEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: event.isUrgent ? AppColors.urgent : AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Image.asset(OwlSays.face(event.stage), width: 42, height: 42),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${event.stageLabel} · ${event.reasonLabel}',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(event.summary.isEmpty ? event.status : event.summary,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(event.createdLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
        ],
      ),
    );
  }
}
