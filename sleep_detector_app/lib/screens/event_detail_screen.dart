// ═══════════════════════════════════════════════════════════════
// screens/event_detail_screen.dart — 운행 기록 상세 (경고 1건) (11/15 팀장)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일]
//   - 운행 기록 카드 · 홈 최근 경고를 누르면 열림
//   - 관리자 웹 경고 상세와 같은 내용을 기사님 눈높이로: 졸음 사진 + AI 분석 결과(상황 · 단계 이유 · 법규)
//     + 기사님께 드린 안내 + 음성 퀴즈 · 휴식 · 3단계 응답 기록 + 위치
//   - 관리자용 '권장 조치'(기사에게 연락 …)는 기사님께는 보여 주지 않음
//   - 사진은 GET /events/{id}/photo (로그인한 본인만) — 토큰을 붙여 받아 화면에만 보여 줌 (폰에 저장 안 함)
// ═══════════════════════════════════════════════════════════════
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/owl_says.dart';

class EventDetailScreen extends StatefulWidget {
  final SleepEvent event;
  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  static const Color _bg = Color(0xFFF8F9FC);
  late final Future<Uint8List?> _photo =
      widget.event.photoUrl == null ? Future.value(null) : ApiService.fetchEventPhoto(widget.event.photoUrl!);

  SleepEvent get e => widget.event;
  Map<String, dynamic> get r => e.report;

  String _s(dynamic v) => v is String ? v.trim() : '';

  // 관리자용 문장의 '기사에게 · 기사의' 를 기사님께 맞게 (관리자 웹 personal() 과 같은 뜻)
  String _forDriver(String text) => text
      .replaceAll(RegExp(r'(?<![가-힣])기사(?:님)?(?:에게|께)'), '기사님께')
      .replaceAll(RegExp(r'(?<![가-힣])기사(?:님)?의'), '기사님의');

  String get _dateTime {
    final t = e.createdAt.toLocal();
    if (t.year < 2000) return '시각 없음';
    String two(int n) => n.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? '오전' : '오후';
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '${t.month}월 ${t.day}일 $ampm $h:${two(t.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final s = e.stage.clamp(0, 3);
    final c = AppColors.stage(s);
    final situation = _forDriver(_s(r['situation']).isNotEmpty ? _s(r['situation']) : e.summary);
    final reason = _forDriver(_s(r['stage_reason']));
    final regulation = _s(r['regulation']);
    final quiz = e.drivingQuiz;
    final rest = e.rest;
    final wake = r['wake'] is Map ? Map<String, dynamic>.from(r['wake']) : null;
    final eye = r['eye'] is Map ? Map<String, dynamic>.from(r['eye']) : null;
    final closedSec = eye?['closed_sec'];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text('경고 기록', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
        children: [
          // 머리: 단계 · 시각 · 종류 (남색 카드 + 단계 부엉이)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(20)),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                            color: c.withValues(alpha: 0.22),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.withValues(alpha: 0.6))),
                        child: Text('$s단계 · ${e.stageLabel}',
                            style: TextStyle(
                                fontSize: 14, fontWeight: FontWeight.w800, color: Color.lerp(c, Colors.white, 0.5))),
                      ),
                      const SizedBox(height: 8),
                      Text(_dateTime,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.white)),
                      const SizedBox(height: 2),
                      Text(e.reasonLabel, style: const TextStyle(fontSize: 14, color: Color(0xFFBEC8E9))),
                    ],
                  ),
                ),
                Image.asset(OwlSays.face(s), width: 72, height: 72),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 졸음 사진 (관리자 웹과 같은 사진)
          _card(
            padding: EdgeInsets.zero,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: AspectRatio(
                aspectRatio: 4 / 3,
                child: FutureBuilder<Uint8List?>(
                  future: _photo,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const ColoredBox(
                          color: Color(0xFFEDF0F8), child: Center(child: CircularProgressIndicator()));
                    }
                    final bytes = snap.data;
                    if (bytes == null) {
                      return const ColoredBox(
                        color: Color(0xFFEDF0F8),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.photo_camera_outlined, size: 34, color: AppColors.textMuted),
                            SizedBox(height: 6),
                            Text('사진이 없어요', style: TextStyle(fontSize: 14, color: AppColors.textMuted)),
                          ],
                        ),
                      );
                    }
                    return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // AI 분석 결과
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.smart_toy_outlined, size: 22, color: AppColors.navy),
                    SizedBox(width: 8),
                    Text('AI 분석 결과',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                    SizedBox(width: 6),
                    Text('자동 분석 · 참고용', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ],
                ),
                _row('무슨 일이 있었나요?', situation),
                _row('왜 이 단계인가요?', reason),
                if (closedSec is num && closedSec > 0) _row('눈을 감은 시간', '약 ${closedSec.toStringAsFixed(1)}초'),
                _row('참고한 법규', regulation),
              ],
            ),
          ),

          // 기사님께 드린 안내
          if (e.guidance.isNotEmpty) ...[
            const SizedBox(height: 14),
            _card(
              color: const Color(0xFFEDF0F8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.campaign_outlined, color: AppColors.navy, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('그때 드린 안내',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textSecondary)),
                        const SizedBox(height: 4),
                        Text(e.guidance,
                            style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.textPrimary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          // 기록: 퀴즈 · 3단계 응답 · 휴식
          if (quiz.isNotEmpty || wake != null || (rest != null && rest['started'] != null)) ...[
            const SizedBox(height: 14),
            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('그 뒤 기록',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                  for (final q in quiz)
                    _row(
                        '음성 퀴즈',
                        '“${q['asked'] ?? ''}” → ${_s(q['heard']).isEmpty ? '대답 없음' : q['heard']}'
                            ' · ${q['passed'] == true ? '통과' : '실패'}'
                            '${q['answer_sec'] is num ? ' (${(q['answer_sec'] as num).toStringAsFixed(1)}초)' : ''}'),
                  if (wake != null)
                    _row('깨어 있어요 버튼',
                        wake['pressed'] == true ? '눌렀어요${wake['sec'] is num ? ' (${(wake['sec'] as num).round()}초)' : ''}' : '누르지 않았어요'),
                  if (rest != null && rest['started'] != null)
                    _row('휴식',
                        '${rest['started']} 정차 → ${rest['resumed'] != null ? '${rest['resumed']} 운행 재개' : '휴식 중'}'
                            '${rest['minutes'] != null ? ' (${rest['minutes']}분)' : ''}'),
                ],
              ),
            ),
          ],

          // 위치
          if (e.latitude != null && e.longitude != null) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => launchUrl(
                  Uri.parse('https://map.kakao.com/link/map/경고 위치,${e.latitude},${e.longitude}'),
                  mode: LaunchMode.externalApplication),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.navy,
                backgroundColor: Colors.white,
                side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('경고가 난 곳 지도에서 보기'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16), Color color = Colors.white}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: child,
      );

  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 16, height: 1.45, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
