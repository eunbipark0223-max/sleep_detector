// ═══════════════════════════════════════════════════════════════
// screens/notice_screen.dart — 알림 (홈 오른쪽 위 종 버튼) (11/17 C)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일]
//   - 내 졸음 경고 기록(GET /events/my)을 알림 목록으로 — 최신순, 최대 50개
//   - 마지막으로 이 화면을 본 뒤에 생긴 경고는 '새 알림' (왼쪽 파란 점)
//   - 관리자가 처리한 경고는 '관리자 조치 완료' · 쉬고 다시 출발한 경고는 '휴식 완료' 를 같이 보여 줌
//   - 누르면 경고 상세 (event_detail_screen)
//   - 화면을 열면 '본 시각'을 저장 → 홈 종 버튼의 빨간 숫자가 사라짐
// [모양] 애플 설정 · 관리자 웹처럼 흰 카드 하나에 줄 목록
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';
import 'event_detail_screen.dart';

class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  late final Future<(List<SleepEvent>, DateTime?)> _data = _load();

  Future<(List<SleepEvent>, DateTime?)> _load() async {
    final seen = await AuthService.getNoticeSeenAt(); // 이번에 열기 전 본 시각 (새 알림 표시용)
    final events = [...await ApiService.fetchMyEvents()]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    await AuthService.saveNoticeSeenAt(DateTime.now()); // 이제 다 봤음
    return (events.take(50).toList(), seen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('알림'),
        centerTitle: true,
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
      ),
      body: FutureBuilder<(List<SleepEvent>, DateTime?)>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return const _Empty(text: '알림을 불러오지 못했어요');
          final (events, seen) = snap.data!;
          if (events.isEmpty) return const _Empty(text: '새로운 알림이 없어요');
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              WebCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22), // 안 읽은 줄 바탕이 카드 모서리 밖으로 안 나가게
                  child: Column(children: [
                  for (var i = 0; i < events.length; i++) ...[
                    if (i > 0) const Divider(height: 1, thickness: 1, indent: 18, endIndent: 18, color: AppColors.line),
                    _NoticeRow(event: events[i], isNew: seen == null || events[i].createdAt.isAfter(seen)),
                  ],
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _NoticeRow extends StatelessWidget {
  final SleepEvent event;
  final bool isNew;
  const _NoticeRow({required this.event, required this.isNew});

  String get _title {
    final s = event.stage.clamp(0, 3);
    if (event.reason == 'pre_warning') return '졸음 예비 경고가 있었어요';
    return s == 0 ? event.reasonLabel : '$s단계 경고 · ${event.reasonLabel}';
  }

  String? get _status => switch (event.status) {
        '조치완료' => '관리자 조치 완료',
        '휴식완료' => '휴식 완료',
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final s = event.stage.clamp(0, 3);
    final body = event.guidance.trim().isNotEmpty ? event.guidance.trim() : event.summary.trim();
    // (11/17) 안 읽은 알림 = 연한 남색 바탕 + 왼쪽 남색 점 + 굵은 제목
    return Material(
      color: isNew ? AppColors.navy.withValues(alpha: 0.05) : Colors.transparent,
      child: InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 14, 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 새 알림 점
          SizedBox(
            width: 10,
            child: isNew
                ? Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Container(
                        width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle)),
                  )
                : null,
          ),
          const SizedBox(width: 2),
          // 단계 색 동그라미 아이콘
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: AppColors.stageTint(s), shape: BoxShape.circle),
            child: Icon(Icons.warning_rounded, size: 19, color: AppColors.stageInk(s)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(_title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 15, fontWeight: isNew ? FontWeight.w700 : FontWeight.w600, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                Text(event.createdLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
              ],
              if (_status != null) ...[
                const SizedBox(height: 6),
                Text(_status!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.live)),
              ],
            ]),
          ),
        ]),
      ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty({required this.text});
  @override
  Widget build(BuildContext context) => Center(
        child: Text(text, style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
      );
}
