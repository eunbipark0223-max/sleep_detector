// ═══════════════════════════════════════════════════════════════
// screens/home_screen.dart — 홈
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/home_screen.dart (🟡 버튼 변경)
//
// [이 파일이 하는 일]
//   - [운행 시작] → calibration_screen (내 눈 기준 측정) → drive_screen
//   - [사진 1장 테스트] → upload_screen
//   - 최근 경고 2~3건 (GET /events/my)
//
// [연결됨]
//   - 최근 경고 : C 의 ApiService.fetchMyEvents() (GET /events/my). 실패하면 '불러오지 못했어요 + 다시 시도'
//   - [사진 1장 테스트] : C 의 UploadScreen
//   - [운행 시작]      : D 의 CalibrationScreen → C 의 DriveScreen(threshold: 기준 값)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../theme.dart';
import 'calibration_screen.dart';
import 'drive_screen.dart';
import 'upload_screen.dart';

class HomeScreen extends StatefulWidget {
  /// 최근 경고를 가져오는 함수. 비워 두면 기본(_defaultLoad). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Future<List<SleepEvent>?> Function()? loadEvents;

  /// 개인 기준 측정 화면. 비워 두면 진짜 CalibrationScreen (카메라 필요). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Widget Function()? calibrationBuilder;

  /// 운행 화면. 기준 값을 받아 만든다. 비워 두면 진짜 DriveScreen (카메라 필요). 테스트 · 미리보기에서 바꿔 끼우는 입구.
  final Widget Function(double threshold)? driveBuilder;

  const HomeScreen({super.key, this.loadEvents, this.calibrationBuilder, this.driveBuilder});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const int _recentCount = 3;

  late Future<List<SleepEvent>?> _recent = _fetch();

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
    });
  }

  // 측정 화면이 돌려주는 값: 기준 값(double) / null = 시작 전에 뒤로 가기 (운행을 시작하지 않는다)
  // 기준 값은 DriveScreen(threshold: t) 로 넘긴다 (측정을 건너뛰었으면 기본 기준이 들어 있다)
  Future<void> _startDrive() async {
    final t = await Navigator.of(context).push<double>(
      MaterialPageRoute(builder: (_) => (widget.calibrationBuilder ?? () => const CalibrationScreen())()),
    );
    if (t == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => (widget.driveBuilder ?? (t) => DriveScreen(threshold: t))(t)),
    );
    if (mounted) _reload(); // 운행 중 새로 생긴 경고가 '최근 경고'에 바로 보이게
  }

  Future<void> _photoTest() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
    if (mounted) _reload(); // 사진 1장 테스트로 생긴 경고도 마찬가지
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async => _reload(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(stage: 0),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _startDrive,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('운행 시작'),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: _photoTest,
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('사진 1장 테스트'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.cardBorder),
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

/// 지금 단계 카드. 홈에서는 운행 전이라 0단계(정상)만 보이고, 단계 색은 theme 의 AppColors.stage 를 쓴다.
class _StatusCard extends StatelessWidget {
  final int stage;
  const _StatusCard({required this.stage});

  @override
  Widget build(BuildContext context) {
    final color = AppColors.stage(stage);
    final onColor = AppColors.onStage(stage);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(SleepEvent.stageLabels[stage], style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: onColor)),
          const SizedBox(height: 6),
          Text(
            '출발하기 전에 폰을 거치대에 고정하고\n[운행 시작]을 눌러 주세요.',
            style: TextStyle(fontSize: 14, height: 1.4, color: onColor),
          ),
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
