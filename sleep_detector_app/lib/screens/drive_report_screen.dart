// ═══════════════════════════════════════════════════════════════
// screens/drive_report_screen.dart — 운행 종료 AI 리포트 (11/16 팀장)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일]
//   - [운행 종료] 뒤 한 번 보여 줌: 오늘 운행을 AI 부엉이가 정리
//     ① AI 요약 (남색 카드) ② 운행 시간 · 졸음 · 휴식 숫자 3칸 ③ 시간표 (언제 몇 단계 · 휴식 · 3단계 응답) ④ 다음 운행 조언
//   - 서버 POST /drive/end 의 report 를 그대로 그림 (숫자는 서버가 센 것, 문장만 AI — 틀리면 서버가 템플릿으로 바꿈)
//   - 서버 답이 없으면(연결 끊김) 이 화면을 띄우지 않고 그냥 홈으로 (drive_screen._confirmEnd)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/owl_says.dart';

class DriveReportScreen extends StatelessWidget {
  final Map<String, dynamic> report;
  const DriveReportScreen({super.key, required this.report});

  static const Color _bg = Color(0xFFF8F9FC);
  static const List<String> _stageNames = ['정상', '주의', '휴식 권고', '긴급'];

  int _i(String k) => (report[k] is num) ? (report[k] as num).toInt() : 0;
  String _s(String k) => report[k] is String ? (report[k] as String).trim() : '';

  String get _driveText {
    final m = _i('drive_min');
    if (m < 1) return '1분 미만';
    final h = m ~/ 60, mm = m % 60;
    if (h == 0) return '$mm분';
    return mm == 0 ? '$h시간' : '$h시간 $mm분';
  }

  @override
  Widget build(BuildContext context) {
    final timeline = (report['timeline'] is List ? report['timeline'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final top = _i('max_stage').clamp(0, 3);
    final range = [_s('started'), _s('ended')].where((x) => x.isNotEmpty).join(' ~ ');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: false,
        title: const Text('오늘 운행 리포트', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 16),
                children: [
                  // ① AI 요약 — 남색 카드 + 부엉이
                  Container(
                    padding: const EdgeInsets.fromLTRB(18, 16, 14, 18),
                    decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.auto_awesome, size: 14, color: Color(0xFFCFC3FF)),
                                const SizedBox(width: 4),
                                Text(report['is_real'] == true ? 'AI 부엉이 정리' : '부엉이 정리',
                                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white)),
                              ]),
                            ),
                            const Spacer(),
                            if (range.isNotEmpty)
                              Text(range, style: const TextStyle(fontSize: 13, color: Color(0xFFBEC8E9))),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('${_s('name').isEmpty ? '기사님' : _s('name')}, 수고하셨어요',
                                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                                  const SizedBox(height: 8),
                                  Text(_s('summary'),
                                      style: const TextStyle(fontSize: 16, height: 1.5, color: Color(0xFFE6EAF7))),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Image.asset(OwlSays.face(top), width: 68, height: 68),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // ② 숫자 3칸
                  Row(
                    children: [
                      _stat('운행 시간', _driveText, AppColors.navy),
                      const SizedBox(width: 10),
                      _stat('졸음', '${_i('sleep_count')}번', _i('sleep_count') == 0 ? AppColors.normal : AppColors.stage(top)),
                      const SizedBox(width: 10),
                      _stat('휴식', '${_i('rest_count')}번', AppColors.navy),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // ③ 시간표
                  _card(
                    title: '오늘 있었던 일',
                    child: timeline.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 6),
                            child: Text('경고 없이 운행했어요 👍',
                                style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                          )
                        : Column(children: [
                            for (var i = 0; i < timeline.length; i++) _row(timeline[i], last: i == timeline.length - 1),
                          ]),
                  ),
                  const SizedBox(height: 14),

                  // ④ 다음 운행 조언
                  _card(
                    title: '다음 운행 조언',
                    icon: Icons.lightbulb_outline,
                    child: Text(_s('advice'),
                        style: const TextStyle(fontSize: 16, height: 1.5, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                child: const Text('확인했어요'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Column(
          children: [
            Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, IconData? icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            if (icon != null) ...[Icon(icon, size: 19, color: AppColors.aiPurple), const SizedBox(width: 6)],
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  // 시간표 한 줄: 시각 · 단계 점 · "2단계 휴식 권고 · 눈 감김" (+ 휴식 · 3단계 응답)
  Widget _row(Map<String, dynamic> t, {required bool last}) {
    final s = (t['stage'] is num ? (t['stage'] as num).toInt() : 0).clamp(0, 3);
    final c = AppColors.stage(s);
    final rest = t['rest'] is Map ? Map<String, dynamic>.from(t['rest']) : null;
    final wake = t['wake'] is Map ? Map<String, dynamic>.from(t['wake']) : null;
    final extra = <String>[
      if (rest != null) '${rest['minutes'] ?? 0}분 쉬었어요',
      if (wake != null) wake['pressed'] == true ? '[깨어 있어요] 누름' : '응답 없음 · 관리자 연락',
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 50,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text('${t['time'] ?? ''}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
            ),
          ),
          SizedBox(
            width: 22,
            child: Column(children: [
              const SizedBox(height: 4),
              Container(width: 11, height: 11, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
              if (!last) Expanded(child: Container(width: 2, color: AppColors.cardBorder)),
            ]),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: last ? 0 : 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('$s단계 ${_stageNames[s]} · ${t['reason'] ?? '졸음'}',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  if (extra.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(extra.join(' · '),
                          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
