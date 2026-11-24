// ═══════════════════════════════════════════════════════════════
// screens/drive_report_screen.dart — 운행 종료 AI 리포트 (11/16 팀장)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일]
//   - [운행 종료] 뒤 한 번 보여 줌: 오늘 운행을 AI 부엉이가 정리
//     ① AI 요약 (남색 카드) ② 운행 시간 · 졸음 · 휴식 숫자 3칸 ③ 시간표 (언제 몇 단계 · 휴식 · 3단계 응답) ④ 다음 운행 조언
//   - 서버 POST /drive/end 의 report 를 그대로 그림 (숫자는 서버가 센 것, 문장만 AI — 틀리면 서버가 템플릿으로 바꿈)
//   - 서버 답이 없으면(연결 끊김) 이 화면을 띄우지 않고 그냥 홈으로 (drive_screen._confirmEnd)
//   - (11/18 팀장) 서버는 템플릿 문장으로 바로 답하고 AI 문장은 뒤에서 만든다 (ai_pending · report_id)
//       → 이 화면은 템플릿을 먼저 보여 주고, 2초마다 GET /drive/report/{id} 를 물어 AI 문장이 오면 바꿔 끼운다 (최대 40초)
// ═══════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';
import '../widgets/web_ui.dart';
import '../widgets/buddy.dart';
import 'event_detail_screen.dart';
import '../design_tokens.dart';
import '../widgets/owl_says.dart' show keepWords;

class DriveReportScreen extends StatefulWidget {
  final Map<String, dynamic> report;
  const DriveReportScreen({super.key, required this.report});

  @override
  State<DriveReportScreen> createState() => _DriveReportScreenState();
}

class _DriveReportScreenState extends State<DriveReportScreen> {
  late Map<String, dynamic> report = Map<String, dynamic>.from(widget.report);
  Timer? _poll;
  int _tries = 0;
  static const int _maxTries = 20; // 2초 × 20 = 40초까지 기다림 (서버 Agent 마감 30초)

  @override
  void initState() {
    super.initState();
    final id = report['report_id'];
    if (report['ai_pending'] == true && id is String && id.isNotEmpty) {
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _checkAi(id));
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  // AI 문장이 오면 요약 · 조언만 바꿔 끼운다 (숫자 · 시간표는 그대로). 실패 · 시간 초과면 템플릿 그대로
  Future<void> _checkAi(String id) async {
    if (++_tries > _maxTries) {
      _poll?.cancel();
      return;
    }
    try {
      final r = await ApiService.fetchDriveReport(id);
      if (!mounted || r['done'] != true) return;
      _poll?.cancel();
      if (r['is_real'] != true) return;
      setState(() {
        report = {...report, 'summary': r['summary'], 'advice': r['advice'], 'is_real': true};
      });
    } catch (_) {
      // 한 번 못 받아도 다음에 다시 물어봄
    }
  }

  static const Color _bg = AppColors.background; // (11/18 피드백) 다른 화면과 같은 흰 바탕
  static const List<String> _stageNames = ['정상', '주의', '휴식 권고', '긴급'];
  static const double _side = 20; // 다른 탭과 같은 좌우 여백 (시작점 · 끝점)

  int _i(String k) => (report[k] is num) ? (report[k] as num).toInt() : 0;
  String _s(String k) => report[k] is String ? (report[k] as String).trim() : '';

  String get _driveText {
    final m = _i('drive_min');
    if (m < 1) return '1분 미만';
    final h = m ~/ 60, mm = m % 60;
    if (h == 0) return '$mm분';
    return mm == 0 ? '$h시간' : '$h시간 $mm분';
  }

  // (11/18 피드백 · 애플 스타일) 흰 바탕 · 다른 탭과 같은 좌우 여백 20 · 내용이 길어지면 스크롤
  //   ① 캐릭터(왼쪽 고정) | 세로선 | '○○님, 수고하셨어요' + 시간  ② 요약 글
  //   ③ 운행 시간 · 졸음 · 휴식 — 카드 하나에 세로선으로 나눔  ④ 오늘 있었던 일  ⑤ 다음 운행 조언  ⑥ [확인했어요]
  //   글은 마침표 없이 (noDot) · '부엉이 정리' 표시는 뺌
  @override
  Widget build(BuildContext context) {
    final timeline = (report['timeline'] is List ? report['timeline'] as List : const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final top = _i('max_stage').clamp(0, 3);
    final sleeps = _i('sleep_count');

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        elevation: 0,
        centerTitle: true,
        automaticallyImplyLeading: true, // (11/18 피드백) 다른 화면과 같은 '<' 뒤로 가기
        title: const Text('오늘 운행 리포트'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(_side, 16, _side, 28), // (11/18) 위아래 넉넉하게
                children: [
                  // ① (11/19 사용자 요청 · Headspace '오늘의 명상' 카드) 노랑 그라데이션 카드 · 오른쪽에 웃는 해 캐릭터
                  //   위 작은 날짜 '11/19' · 아래 큰 글 '수고하셨어요 / 김기사 기사님' (운행 시각 줄은 뺌)
                  // (11/23 사용자 요청) 글 끝 바로 옆에 캐릭터 · 두 줄 (줄 사이 한 칸 · 마지막에 마침표)
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(color: AppleGray.separator),
                      gradient: LinearGradient(colors: [Colors.white, AppIllust.softTint[2]]),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${DateTime.now().month}/${DateTime.now().day}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const SizedBox(height: 10),
                      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Flexible(
                          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('수고하셨어요',
                                style: TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: AppColors.textPrimary)),
                            const SizedBox(height: 4),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('$_callName.',
                                  maxLines: 1,
                                  style: const TextStyle(fontSize: 24, height: 1.25, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: AppColors.textPrimary)),
                            ),
                          ]),
                        ),
                        const SizedBox(width: 10),
                        const Buddy(stage: 2, size: 52, breathe: false),
                      ]),
                    ]),
                  ),
                  const SizedBox(height: 22),
                  // ② 요약 글
                  if (_s('summary').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20), // (11/23 사용자 요청) 위 카드 안 글과 같은 시작선
                      child: Text(keepWords(noDot(_s('summary'))), style: const TextStyle(fontSize: 15.5, height: 1.55, color: AppColors.textSecondary)),
                    ),
                  const SizedBox(height: 26),
                  // ③ 숫자 — 카드 하나 · 세로 구분선
                  WebCard(
                    padding: const EdgeInsets.symmetric(vertical: 20),
                    child: IntrinsicHeight(
                      child: Row(children: [
                        _stat('운행 시간', _driveText, AppColors.textPrimary),
                        const VerticalDivider(width: 1, thickness: 1, indent: 6, endIndent: 6, color: AppColors.line),
                        // 졸음 0번 = 초록 (졸음이 없었음) · 있으면 그날 가장 높은 단계 색
                        _stat('졸음', '$sleeps번', sleeps == 0 ? AppColors.normal : AppColors.stage(top)),
                        const VerticalDivider(width: 1, thickness: 1, indent: 6, endIndent: 6, color: AppColors.line),
                        _stat('휴식', '${_i('rest_count')}번', AppColors.textPrimary),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // ④ 오늘 있었던 일
                  const _Heading(icon: Icons.schedule_rounded, text: '오늘 있었던 일'),
                  WebCard(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                    child: timeline.isEmpty
                        ? const Text('경고 없이 운행했어요 👍', style: TextStyle(fontSize: 15, color: AppColors.textSecondary))
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (var i = 0; i < timeline.length; i++)
                              InkWell(
                                onTap: () => _openReport(timeline[i]['event_id']),
                                child: _row(timeline[i], last: i == timeline.length - 1),
                              ),
                            // (11/23 사용자 요청) 홈 운행 기록과 같은 안내 — 카드 맨 아래
                            const Padding(
                              padding: EdgeInsets.only(top: 16),
                              child: Text('› 를 누르면 AI 분석 보고서를 볼 수 있어요', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
                            ),
                          ]),
                  ),
                  const SizedBox(height: 32),
                  // ⑤ 다음 운행 조언
                  const _Heading(icon: Icons.lightbulb_outline_rounded, text: '다음 운행 조언'),
                  WebCard(
                    padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                    child: Text(keepWords(noDot(_s('advice'))),
                        style: const TextStyle(fontSize: 15.5, height: 1.55, color: AppColors.textPrimary)),
                  ),
                ],
              ),
            ),
            // ⑥ 다른 화면과 같은 남색 알약 버튼 · 같은 좌우 여백
            Padding(
              padding: const EdgeInsets.fromLTRB(_side, 8, _side, 20),
              child: AuthButton(text: '확인했어요', height: AppSize.button, color: const Color(0xFF2E9E5B), onPressed: () => Navigator.of(context).pop()) /* (11/23) 초록 */,
            ),
          ],
        ),
      ),
    );
  }

  // (11/19 사용자 요청) 줄을 누르면 그 경고의 AI 보고서
  Future<void> _openReport(dynamic id) async {
    if (id is! num) return;
    try {
      final events = await ApiService.fetchMyEvents();
      final e = events.where((x) => x.id == id.toInt()).firstOrNull;
      if (e == null || !mounted) return;
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: e)));
    } catch (_) {}
  }

  // 부르는 말 — 서버 이름이 '김기사' 면 '김기사 기사님', 이미 '…님' 으로 끝나면 그대로 (예전엔 '김기사 기사님님' 이 됐음)
  String get _callName {
    final n = _s('name');
    if (n.isEmpty) return '기사님';
    return n.endsWith('님') ? n : '$n 기사님';
  }

  Widget _stat(String label, String value, Color color) {
    return Expanded(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: color)),
      ]),
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
              // (11/18 팀장) 운행 기록 타임라인과 같은 점 — 흰 테두리 + 옅은 고리
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.card, width: 2),
                  boxShadow: [BoxShadow(color: c.withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 1.5)],
                ),
              ),
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
                  // (11/23 사용자 요청) 앱 전체와 같은 이름 — 주의 · 휴식 권고 · 긴급 (음성 응답 없음만 그대로)
                  Text('${t['reason']}'.contains('응답') ? '음성 응답 없음' : const ['정상', '주의', '휴식 권고', '긴급'][s],
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
          const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron), // (11/23) 홈처럼 줄 끝 ›
        ],
      ),
    );
  }
}

/// 묶음 위 작은 제목 — 남색 아이콘 + 회색 글자 (아이폰 설정처럼)
class _Heading extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Heading({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Row(children: [
          Icon(icon, size: 16, color: AppColors.navy),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
      );
}
