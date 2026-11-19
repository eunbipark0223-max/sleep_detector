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

  const HomeScreen({
    super.key,
    this.loadEvents,
    this.calibrationBuilder,
    this.driveBuilder,
    this.loadDriveState,
    this.resumeBuilder,
    this.onOpenRecords,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0; // 0 오늘 경고 · 1 이번 주 · 2 긴급
  static const int _driveCount = 3; // (11/19) 처음에 보이는 운행 카드 수
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

  late Future<List<SleepEvent>?> _recent = _fetch();
  late Future<DriveState?> _driveState = _fetchDriveState();
  late Future<List<DriveSpan>> _spans = DriveLog.load(); // (11/19) 폰에 적어 둔 운행 시작 · 종료

  // 앱을 껐다 켰을 때 서버가 기억하는 운행 상태. 못 받으면 (서버 연결 오류 등) null — 배너만 안 뜨고 홈은 그대로
  Future<DriveState?> _fetchDriveState() {
    final future = (widget.loadDriveState ?? _defaultLoadDriveState)()
        .catchError((_) => null);
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
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [Color(0x00000000), Color(0x00000000), Color(0xFF000000)],
          stops: [0, (6 / r.height).clamp(0.0, 1.0), (40 / r.height).clamp(0.0, 1.0)],
        ).createShader(r),
        child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
          const SizedBox(height: 14),
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
              final weekN = events.where(fromWeek).length;
              final urgentN = events.where((e) => e.stage >= 3).length;
              return FutureBuilder<List<DriveSpan>>(
                future: _spans,
                builder: (context, spanSnap) {
                  // (11/19 사용자 요청) 경고를 '운행 한 번'(운행 시작 ~ 운행 종료) 씩 묶어서 보여 줌
                  final all = groupDrives(events, spanSnap.data ?? const []);
                  bool inToday(DriveGroup g) => !g.last.isBefore(dayStart);
                  bool inWeek(DriveGroup g) => !g.last.isBefore(weekStart);
                  final lists = [
                    all.where(inToday).toList().reversed.toList(), // 오늘 — (11/19 사용자 요청) 최신 운행이 맨 위
                    all.where(inWeek).toList().reversed.toList(), // 이번 주 — 최근 운행이 위
                    all.where((g) => g.hasUrgent).toList().reversed.toList(), // 긴급 — 3단계가 있었던 운행
                  ];
                  final shown = lists[_tab];
                  const empties = ['오늘은 운행 기록이 없어요', '이번 주는 운행 기록이 없어요', '긴급 경고가 있었던 운행이 없어요'];
                  final visible = _expanded ? shown.length : shown.length.clamp(0, _driveCount);
                  return WebCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        StatTabs(
                          selected: _tab,
                          onSelect: (i) => setState(() {
                            _tab = i;
                            _expanded = false;
                          }),
                          items: [
                            StatItem('${now.month}/${now.day}', '$todayN', '건'), // (11/19 사용자 요청) '오늘' 대신 날짜만
                            StatItem('이번 주', '$weekN', '건'),
                            StatItem('긴급', '$urgentN', '건', alert: urgentN > 0),
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
                              for (var i = 0; i < visible; i++) ...[
                                if (i > 0) const _CenterLine(),
                                _DriveCard(group: shown[i]),
                              ],
                              // [n개 운행 전체 보기] ↔ [접기] — 그 자리에서 펼치고 접음
                              if (shown.length > _driveCount) ...[
                                const _CenterLine(),
                                TextButton(
                                  onPressed: () => setState(() => _expanded = !_expanded),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.navy,
                                    minimumSize: const Size.fromHeight(44),
                                  ),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(_expanded ? '접기' : '운행 ${shown.length}번 전체 보기',
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
                },
              );
            },
          ),
        ],
      ),
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
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _DriveDetailScreen(group: g))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 18, 4, 18),
        // (11/19 사용자 요청) 운행 줄 높이 모두 같게 — 시간이 길든 짧든 72 로 고정
        child: SizedBox(
          height: 72,
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
            const VerticalDivider(width: 17, thickness: 1, indent: 2, endIndent: 2, color: AppColors.line),
            // 오른쪽 — (11/19 사용자 요청) 운행 기록 타임라인과 같은 단계 링 점 + 아래 큰 숫자
            for (final st in const [1, 2, 3]) Expanded(child: _StageCount(stage: st, count: g.count(st))),
            const Icon(Icons.chevron_right_rounded, size: 16, color: AppleGray.chevron),
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
        decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.navy.withValues(alpha: 0.1)),
        child: Text('$n',
            textAlign: TextAlign.center,
            strutStyle: StrutStyle(fontSize: size * 0.62, height: 1, forceStrutHeight: true),
            style: TextStyle(fontSize: size * 0.62, height: 1, fontWeight: FontWeight.w700, color: AppColors.navy)),
      );
}

/// 단계 하나 — 위 단계 링 점 (운행 기록 '미세수면' 옆 점과 같은 모양) · 아래 큰 숫자 'n건' (0건은 흐리게)
class _StageCount extends StatelessWidget {
  final int stage;
  final int count;
  const _StageCount({required this.stage, required this.count});

  @override
  Widget build(BuildContext context) {
    final zero = count == 0;
    final c = AppColors.stage(stage);
    const names = ['', '주의', '휴식 권고', '위험'];
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      // (11/19 사용자 요청) 링 점 옆에 단계 이름
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: zero ? c.withValues(alpha: 0.45) : c,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.card, width: 2),
          boxShadow: [BoxShadow(color: c.withValues(alpha: zero ? 0.18 : 0.35), blurRadius: 0, spreadRadius: 1.5)],
        ),
      ),
          const SizedBox(width: 5),
          Text(names[stage],
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: zero ? AppleGray.chevron : AppColors.textSecondary)),
        ]),
      ),
      const SizedBox(height: 9),
      Text.rich(
        TextSpan(children: [
          TextSpan(
              text: '$count',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: zero ? AppleGray.chevron : AppColors.textPrimary)),
          TextSpan(
              text: '건',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: zero ? AppleGray.chevron : AppColors.textSecondary)),
        ]),
      ),
    ]);
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
        title: Row(mainAxisSize: MainAxisSize.min, children: [const Text('운행'), const SizedBox(width: 6), _CircleNum(g.number, size: 20)]),
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
            child: Row(children: [for (final st in const [1, 2, 3]) Expanded(child: _StageCount(stage: st, count: g.count(st)))]),
          ),
          const SizedBox(height: 14),
          WebCard(
            padding: EdgeInsets.zero,
            child: events.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 28),
                    child: Center(child: Text('경고 없이 운행했어요', style: TextStyle(fontSize: 14, color: AppColors.textMuted))),
                  )
                : Column(children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) const _CenterLine(),
                      _EventTile(event: events[i]),
                    ],
                  ]),
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
          height: 48,
          contentWidth: 160,
          leading: const Icon(Icons.redo_rounded, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 10),
        AuthButton(
          text: '새로운 운행 시작',
          primary: false,
          onPressed: onNew,
          height: 48,
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
        borderRadius: BorderRadius.circular(18),
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
                borderRadius: BorderRadius.circular(15),
              ),
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
              decoration: BoxDecoration(color: AppIllust.thumb(event.stage.clamp(1, 3)), borderRadius: BorderRadius.circular(14)),
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
          borderRadius: BorderRadius.circular(18),
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
