// ═══════════════════════════════════════════════════════════════
// widgets/month_report.dart — MY 탭 '이번 달 운행 분석' (11/19 C · 사용자 요청)
// ═══════════════════════════════════════════════════════════════
// [무엇] Headspace 통계 화면처럼 한 달 기록을 한눈에
//   ① 그라데이션 카드: '11월 · 졸음 경고 n건' + 지난달과 비교
//   ② 숫자 칸 4개: 운행 · 1단계 주의 · 2단계 휴식 권고 · 3단계 위험
//   ③ 시간대 막대: 새벽 · 오전 · 오후 · 저녁 중 언제 졸음이 많았는지
//   ④ 이번 달 정리: 기록으로 만든 짧은 문장 (가장 많은 시간대 · 원인 · 조언)
// [데이터] GET /events/my (경고 기록) + 폰에 적어 둔 운행 시작 · 종료 (drive_log)
//   서버 AI 를 부르지 않고 앱이 기록을 세어서 만든다 (문장은 정해진 규칙)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../services/drive_log.dart';
import '../theme.dart';
import 'buddy.dart';
import 'web_ui.dart';

class MonthReport extends StatefulWidget {
  const MonthReport({super.key});

  @override
  State<MonthReport> createState() => _MonthReportState();
}

class _MonthReportState extends State<MonthReport> {
  late final Future<(List<SleepEvent>, List<DriveSpan>)> _data = _load();

  static Future<(List<SleepEvent>, List<DriveSpan>)> _load() async {
    final ev = await ApiService.fetchMyEvents().catchError((_) => <SleepEvent>[]);
    final sp = await DriveLog.load();
    return (ev, sp);
  }

  static const _slots = ['새벽', '오전', '오후', '저녁']; // 0~6 · 6~12 · 12~18 · 18~24
  static const _slotHours = ['0~6시', '6~12시', '12~18시', '18~24시'];

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<(List<SleepEvent>, List<DriveSpan>)>(
      future: _data,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const SizedBox(height: 120, child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
        }
        final (events, spans) = snap.data!;
        final now = DateTime.now();
        bool inMonth(DateTime t, int y, int m) => t.year == y && t.month == m;
        final mine = events.where((e) => inMonth(e.createdAt.toLocal(), now.year, now.month)).toList();
        final prevM = now.month == 1 ? 12 : now.month - 1;
        final prevY = now.month == 1 ? now.year - 1 : now.year;
        final prev = events.where((e) => inMonth(e.createdAt.toLocal(), prevY, prevM)).length;
        final drives = groupDrives(events, spans).where((g) => inMonth(g.start, now.year, now.month)).length;
        int n(int s) => mine.where((e) => e.stage == s).length;

        // 시간대 · 원인
        final slot = List<int>.filled(4, 0);
        final reasons = <String, int>{};
        for (final e in mine) {
          slot[e.createdAt.toLocal().hour ~/ 6]++;
          reasons[e.reasonLabel] = (reasons[e.reasonLabel] ?? 0) + 1;
        }
        final peak = mine.isEmpty ? -1 : slot.indexOf(slot.reduce((a, b) => a > b ? a : b));
        final topReason = reasons.isEmpty ? null : (reasons.entries.toList()..sort((a, b) => b.value - a.value)).first.key;
        final diff = mine.length - prev;

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _heading('이번 달 운행 분석'),
          // ① 그라데이션 카드
          HsCard(
            stage: 2,
            face: 0,
            minHeight: 140,
            orb: 170,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${now.month}월', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xB32D2C2B))),
              const SizedBox(height: 6),
              Text.rich(TextSpan(children: [
                const TextSpan(text: '졸음 경고 '),
                TextSpan(text: '${mine.length}', style: const TextStyle(fontSize: 30)),
                const TextSpan(text: '건'),
              ]), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              Text(
                prev == 0 && mine.isEmpty
                    ? '아직 기록이 없어요'
                    : diff == 0
                        ? '지난달과 같아요'
                        : '지난달보다 ${diff.abs()}건 ${diff < 0 ? '줄었어요' : '늘었어요'}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xCC2D2C2B)),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          // ② 숫자 칸 4개 (2 x 2)
          Row(children: [
            Expanded(child: _tile(null, '운행', '$drives', '번')),
            const SizedBox(width: 10),
            Expanded(child: _tile(1, '주의', '${n(1)}', '건')),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _tile(2, '휴식 권고', '${n(2)}', '건')),
            const SizedBox(width: 10),
            Expanded(child: _tile(3, '위험', '${n(3)}', '건')),
          ]),
          const SizedBox(height: 22),
          // ③ 시간대 막대
          _heading('졸음이 잦은 시간대'),
          WebCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
            child: Column(children: [
              SizedBox(
                height: 110,
                child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  for (var i = 0; i < 4; i++)
                    Expanded(child: _bar(slot[i], slot.reduce((a, b) => a > b ? a : b), i == peak)),
                ]),
              ),
              const SizedBox(height: 8),
              Row(children: [
                for (var i = 0; i < 4; i++)
                  Expanded(
                    child: Column(children: [
                      Text(_slots[i],
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: i == peak ? FontWeight.w700 : FontWeight.w500,
                              color: i == peak ? AppColors.navy : AppColors.textSecondary)),
                      Text(_slotHours[i], style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                    ]),
                  ),
              ]),
            ]),
          ),
          const SizedBox(height: 22),
          // ④ 이번 달 정리
          _heading('이번 달 정리'),
          WebCard(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final line in _summary(mine.length, peak, topReason, n(3), drives)) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 7),
                      child: Container(
                          width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(line, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary))),
                  ]),
                ),
              ],
            ]),
          ),
        ]);
      },
    );
  }

  /// 기록으로 만든 문장 (마침표 없이 '-요')
  List<String> _summary(int total, int peak, String? reason, int urgent, int drives) {
    if (total == 0) return ['이번 달은 졸음 경고 없이 운행했어요', '지금처럼 2시간마다 쉬어 가세요'];
    return [
      if (peak >= 0) '${_slots[peak]}(${_slotHours[peak]})에 졸음이 가장 많았어요',
      if (reason != null) '가장 많은 경고는 \'$reason\' 이었어요',
      if (urgent > 0) '3단계(위험)까지 간 적이 $urgent번 있어요',
      switch (peak) {
        0 => '새벽 운행 전에는 충분히 자고 출발하세요',
        1 => '오전에도 2시간마다 쉼터에서 쉬어 가세요',
        2 => '점심 뒤 오후 운행 전에 10분 쉬어 가세요',
        _ => '저녁 운행은 짧게 나눠서 쉬어 가세요',
      },
    ];
  }

  Widget _heading(String text) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
      );

  // 숫자 칸 — 흰 둥근 칸 · 위 단계 점 + 이름 · 아래 큰 숫자
  Widget _tile(int? stage, String label, String value, String unit) {
    final c = stage == null ? AppColors.navy : AppColors.stage(stage);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: AppShadow.card,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.card, width: 1.5),
              boxShadow: [BoxShadow(color: c.withValues(alpha: 0.3), spreadRadius: 1.5)],
            ),
          ),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        Text.rich(TextSpan(children: [
          TextSpan(text: value, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          TextSpan(text: unit, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ])),
      ]),
    );
  }

  // 시간대 막대 — 둥근 막대 · 가장 많은 시간대만 남색, 나머지는 연한 남색
  Widget _bar(int v, int max, bool top) {
    final h = max == 0 ? 6.0 : (6 + 72 * v / max);
    return Column(mainAxisAlignment: MainAxisAlignment.end, children: [
      Text('$v', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: top ? AppColors.navy : AppColors.textMuted)),
      const SizedBox(height: 4),
      AnimatedContainer(
        duration: AppMotion.slow,
        curve: AppMotion.curve,
        width: 28,
        height: h,
        decoration: BoxDecoration(
          color: top ? AppColors.navy : AppColors.navy.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    ]);
  }
}
