// ═══════════════════════════════════════════════════════════════
// screens/event_detail_screen.dart — 운행 기록 상세 (경고 1건) (11/15 팀장)
// ═══════════════════════════════════════════════════════════════
// [이 화면이 하는 일]
//   - 운행 기록 카드 · 홈 최근 경고를 누르면 열림
//   - 관리자 웹 경고 상세와 같은 내용을 기사님 눈높이로: 졸음 사진 + AI 분석 결과(상황 · 단계 이유 · 법규)
//     + 기사님께 드린 안내 + 음성 퀴즈 · 휴식 · 3단계 응답 기록 + 위치
//   - 관리자용 '권장 조치'(기사에게 연락 …)는 기사님께는 보여 주지 않음
//   - 사진은 GET /events/{id}/photo (로그인한 본인만) — 토큰을 붙여 받아 화면에만 보여 줌 (폰에 저장 안 함)
//
// [모양] (11/17 C · 관리자 웹 경고 상세 팝업과 같게)
//   사진 칸 → 큰 시각 '17:44' + 단계 알약 → 아이콘 줄(위치 · 지도에서 보기) → 남색 AI 분석 카드
//   → 기사님의 대처 → 시간 기록 줄(단계 색 세로 막대)
// ═══════════════════════════════════════════════════════════════
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';

class EventDetailScreen extends StatefulWidget {
  final SleepEvent event;
  const EventDetailScreen({super.key, required this.event});

  @override
  State<EventDetailScreen> createState() => _EventDetailScreenState();
}

class _EventDetailScreenState extends State<EventDetailScreen> {
  static const Color _bg = AppColors.background;
  late final Future<Uint8List?> _photo =
      widget.event.photoUrl == null ? Future.value(null) : ApiService.fetchEventPhoto(widget.event.photoUrl!);

  SleepEvent get e => widget.event;
  Map<String, dynamic> get r => e.report;

  String _s(dynamic v) => v is String ? v.trim() : '';

  // 관리자용 문장의 '기사에게 · 기사의' 를 기사님께 맞게 (관리자 웹 personal() 과 같은 뜻)
  String _forDriver(String text) => text
      .replaceAll(RegExp(r'(?<![가-힣])기사(?:님)?(?:에게|께)'), '기사님께')
      .replaceAll(RegExp(r'(?<![가-힣])기사(?:님)?의'), '기사님의');

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// 큰 시각 '17:44'
  String get _time {
    final t = e.createdAt.toLocal();
    if (t.year < 2000) return '--:--';
    return '${_two(t.hour)}:${_two(t.minute)}';
  }

  /// 시각 옆 작은 날짜 '11/17'
  String get _date {
    final t = e.createdAt.toLocal();
    if (t.year < 2000) return '';
    return '${t.month}/${t.day}';
  }

  @override
  Widget build(BuildContext context) {
    final s = e.stage.clamp(0, 3);
    final situation = _forDriver(_s(r['situation']).isNotEmpty ? _s(r['situation']) : e.summary);
    final reason = _forDriver(_s(r['stage_reason']));
    final regulation = _s(r['regulation']);
    final quiz = e.drivingQuiz;
    final rest = e.rest;
    final wake = r['wake'] is Map ? Map<String, dynamic>.from(r['wake']) : null;
    final eye = r['eye'] is Map ? Map<String, dynamic>.from(r['eye']) : null;
    final closedSec = eye?['closed_sec'];
    final hasPlace = e.latitude != null && e.longitude != null;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('경고 기록', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
        ]),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: AppColors.line),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          WebCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 졸음 사진 (관리자 웹과 같은 사진) — 없으면 연회색 칸에 '캡처 사진이 없어요'
                ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: FutureBuilder<Uint8List?>(
                      future: _photo,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const ColoredBox(
                              color: AppColors.field, child: Center(child: CircularProgressIndicator()));
                        }
                        final bytes = snap.data;
                        if (bytes == null) {
                          return const ColoredBox(
                            color: AppColors.field,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.photo_camera, size: 30, color: Color(0xFF8A90A6)),
                                SizedBox(height: 8),
                                Text('캡처 사진이 없어요', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
                              ],
                            ),
                          );
                        }
                        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),

                // 큰 시각 · 날짜 · 오른쪽 단계 알약
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(_time,
                        style: const TextStyle(
                            fontSize: 30, height: 1.1, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_date, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                    ),
                    // 남은 자리를 다 배지에 줌 (Spacer 와 나눠 쓰면 배지 자리가 반으로 줄어 넘쳤음)
                    const SizedBox(width: 12),
                    Expanded(
                      child: Align(alignment: Alignment.centerRight, child: StageBadge(stage: s, text: e.reasonLabel)),
                    ),
                  ],
                ),

                // 위치 줄 — 관리자 웹처럼 아이콘 + '지도에서 보기' 파란 글씨
                if (hasPlace) ...[
                  const SizedBox(height: 12),
                  const Divider(height: 1, thickness: 1, color: AppColors.line),
                  InkWell(
                    onTap: () => launchUrl(
                        Uri.parse('https://map.kakao.com/link/map/경고 위치,${e.latitude},${e.longitude}'),
                        mode: LaunchMode.externalApplication),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Icon(Icons.location_on, size: 19, color: AppColors.textSecondary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('경고가 난 곳',
                                style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                            const SizedBox(height: 3),
                            Text('지도에서 보기',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                          ]),
                        ),
                      ]),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 14),

          // AI 분석 결과 — 관리자 웹처럼 남색으로 꽉 찬 카드 + 흰 글씨
          Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(22)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('AI 분석 결과',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white)),
                // (11/16 사용자 요청 16) '눈 감김 시간은 짧았어요' 대신 실제 눈 감은 시간으로
                _aiRow(
                    '무슨 일이 있었나요?',
                    closedSec is num && closedSec > 0
                        ? situation.replaceAll(RegExp(r'눈 감(김|긴) 시간은 짧았어요\.?'),
                            '눈 감긴 시간은 ${closedSec.toStringAsFixed(1)}초였어요.')
                        : situation),
                _aiRow('왜 이 단계인가요?', reason),
                if (closedSec is num && closedSec > 0) _aiRow('눈을 감은 시간', '약 ${closedSec.toStringAsFixed(1)}초'),
                _aiRow('참고한 법규', regulation),
                _aiRow('기사님께 전달한 안내', e.guidance),
              ],
            ),
          ),

          // 기록: 퀴즈 · 3단계 응답 · 휴식
          if (quiz.isNotEmpty || wake != null || (rest != null && rest['started'] != null)) ...[
            const SizedBox(height: 14),
            WebCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('기사님의 대처',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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

          // 시간 기록 한 줄 (관리자 웹 팝업 맨 아래)
          const SizedBox(height: 14),
          WebCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            child: TimelineRow(time: _time, stage: s, title: e.reasonLabel),
          ),
        ],
      ),
    );
  }

  // 남색 AI 카드 안 한 줄 — 위 작은 연한 글씨(질문) · 아래 흰 글씨(답)
  Widget _aiRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65))),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
