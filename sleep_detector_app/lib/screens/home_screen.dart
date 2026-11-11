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

import '../models/drive_status.dart';
import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../stage_texts.dart';
import '../theme.dart';
import '../widgets/owl_says.dart';
import 'calibration_screen.dart';
import 'drive_screen.dart';
import 'map_screen.dart';
import 'warning_screen.dart' show stageTint;

/// 커피 색 — [가까운 졸음쉼터] 버튼 (바탕 = 갈색 반투명, 커피잔 = 아메리카노 색, 11/11)
const Color _coffee = Color(0xFF8B5A2B);
const Color _americano = Color(0xFF3E2415);

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

  const HomeScreen(
      {super.key, this.loadEvents, this.calibrationBuilder, this.driveBuilder, this.loadDriveState, this.resumeBuilder});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _recentCount = 3;

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

  void _openMap() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
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
          FutureBuilder<List<SleepEvent>?>(
            future: _recent,
            builder: (context, snapshot) => _StatusCard(stage: currentStage(snapshot.data)),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDrive,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('운행 시작'),
          ),
          const SizedBox(height: 10),
          // [가까운 졸음쉼터] — 반투명 갈색 바탕 + 아메리카노 색으로 채운 커피잔 (11/11, 쉼터 = 커피 한 잔)
          // (사진 1장 테스트는 ≡ 메뉴로 옮김 — 팀장 main 의 '개발용 숨김'과 같은 뜻, 11/11)
          OutlinedButton.icon(
            onPressed: _openMap,
            icon: const Icon(Icons.local_cafe, color: _americano, size: 26),
            label: const Text('가까운 졸음쉼터'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: _coffee.withValues(alpha: 0.16),
              foregroundColor: _americano,
              side: BorderSide(color: _coffee.withValues(alpha: 0.45)),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          const Text('최근 경고', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          FutureBuilder<List<SleepEvent>?>(
            future: _recent,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
              }
              if (snapshot.hasError) {
                return _Hint(text: '최근 경고를 불러오지 못했어요', actionText: '다시 시도', onAction: _reload);
              }
              final events = snapshot.data;
              if (events == null) return const _Hint(text: '최근 경고 불러오기는 준비 중이에요');
              if (events.isEmpty) return const _Hint(text: '최근 경고가 없어요');
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
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: state.stage >= 1 ? color : AppColors.cardBorder, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('진행 중인 운행이 있어요',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(_detail, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onResume,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('이어서 운행'),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          ),
        ],
      ),
    );
  }
}

/// 지금 단계 카드. 내 경고 기록으로 가늠한 단계(HomeScreen.currentStage)를 보여 주고, 단계 색은 theme 의 AppColors.stage 를 쓴다.
class _StatusCard extends StatelessWidget {
  final int stage;
  const _StatusCard({required this.stage});

  // 0단계는 출발 안내, 1 ~ 3단계는 경고 화면 · 운행 화면 · 음성과 같은 문구 (stage_texts.dart, 11/11)
  static String _message(int stage) =>
      stage <= 0 ? '출발하기 전에 폰을 거치대에 고정하고\n[운행 시작]을 눌러 주세요.' : StageTexts.headline(stage.clamp(1, 3));

  @override
  Widget build(BuildContext context) {
    // (11/11 C) 원색 바탕이면 같은 색 부엉이가 묻혀서 → 경고 화면과 같게 PPT 색 가이드 + 투명도 (진한 글자)
    final color = stageTint(stage);
    const onColor = AppColors.textPrimary;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(SleepEvent.stageLabels[stage], style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: onColor)), // 단계 이름 크게 (11/11)
          const SizedBox(height: 10),
          // 단계별 부엉이가 말풍선으로 안내 (11/11 C — 부엉이를 앱 시그니처로). 문구는 팀장 stage_texts 기준 (_message)
          OwlSays(owl: OwlSays.body(stage), text: _message(stage), owlSize: 112, fontSize: 19, maxLines: 6),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final SleepEvent event;
  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: event.isUrgent ? AppColors.urgent : AppColors.cardBorder),
      ),
      child: ListTile(
        leading: CircleAvatar(
          radius: 16,
          backgroundColor: AppColors.stage(event.stage),
          child: Text('${event.stage}', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.onStage(event.stage))),
        ),
        title: Text('${event.stageLabel} · ${event.reasonLabel}', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        subtitle: Text(
          event.summary.isEmpty ? event.status : event.summary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Text(event.createdLabel,style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  const _Hint({required this.text, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        children: [
          Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          if (actionText != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}
