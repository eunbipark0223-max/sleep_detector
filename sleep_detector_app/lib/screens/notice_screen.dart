// ═══════════════════════════════════════════════════════════════
// screens/notice_screen.dart — 알림 (홈 오른쪽 위 종 버튼) (11/17 C · 11/18 정리)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일] (11/18 사용자 요청 — 알림이 많으면 지저분해서)
//   - 관리자가 조치를 완료한 경고만 알림으로: '관리자가 조치를 완료했어요'
//   - 아직 안 본 알림 = 연한 남색 바탕 + 왼쪽 남색 점 + 굵은 제목 (화면을 열면 모두 '봄' 으로 저장)
//   - 누르면 경고 상세 (event_detail_screen)
// [모양] 아이콘 없이, 흰 카드 하나에 줄 목록
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';
import 'event_detail_screen.dart';

/// (11/18 피드백) 알림은 두 가지만 — 3단계 경고(관리자에게 알림 · 빨간 점) · 그 경고를 관리자가 조치완료(초록 점)
///   1 · 2단계 경고는 알림으로 안 보냄 (너무 많으면 정신없음). 홈 종 숫자도 같은 기준
List<SleepEvent> noticeEvents(List<SleepEvent> events) =>
    events.where((e) => e.stage >= 3).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

class NoticeScreen extends StatefulWidget {
  const NoticeScreen({super.key});

  @override
  State<NoticeScreen> createState() => _NoticeScreenState();
}

class _NoticeScreenState extends State<NoticeScreen> {
  late final Future<(List<SleepEvent>, Set<int>)> _data = _load();

  Future<(List<SleepEvent>, Set<int>)> _load() async {
    final seen = await AuthService.getNoticeSeenIds(); // 열기 전에 본 것 (새 알림 표시용)
    final list = noticeEvents(await ApiService.fetchMyEvents()).take(50).toList();
    await AuthService.saveNoticeSeenIds({...seen, for (final e in list) e.id}); // 이제 다 봤음
    return (list, seen);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('알림'), centerTitle: true),
      body: FutureBuilder<(List<SleepEvent>, Set<int>)>(
        future: _data,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return const _Empty(text: '알림을 불러오지 못했어요');
          final (events, seen) = snap.data!;
          if (events.isEmpty) return const _Empty(text: '새로운 알림이 없어요');
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              WebCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Column(children: [
                    for (var i = 0; i < events.length; i++) ...[
                      if (i > 0) const Divider(height: 1, thickness: 1, color: AppColors.line),
                      _NoticeRow(event: events[i], isNew: !seen.contains(events[i].id)),
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

  @override
  Widget build(BuildContext context) {
    final done = event.status == '조치완료';
    // 조치완료 = 초록 점 '조치완료되었습니다' · 아직 = 빨간 점 '3단계 경고 · 관리자에게 알렸어요'
    final dot = done ? AppColors.normal : AppColors.urgent;
    final title = done ? '조치완료되었습니다' : '3단계 경고 · 관리자에게 알렸어요';
    final what = done ? '관리자가 3단계 경고를 확인하고 해제했어요' : event.reasonLabel;
    return Material(
      color: isNew ? AppColors.navy.withValues(alpha: 0.05) : Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 15, 16, 15),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 아이콘 없이 색 점 하나 (빨강 = 3단계 · 초록 = 조치완료)
            Padding(
              padding: const EdgeInsets.only(left: 6, top: 6),
              child: Container(width: 10, height: 10, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(
                    child: Text(title,
                        style: TextStyle(
                            fontSize: 15.5,
                            fontWeight: isNew ? FontWeight.w700 : FontWeight.w600,
                            color: AppColors.textPrimary)),
                  ),
                  const SizedBox(width: 8),
                  Text(event.createdLabel, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
                const SizedBox(height: 3),
                Text(what, style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
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
