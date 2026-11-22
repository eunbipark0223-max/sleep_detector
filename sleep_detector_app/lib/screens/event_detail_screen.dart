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
import '../widgets/owl_says.dart' show keepWords;
import '../widgets/web_ui.dart';
import '../widgets/buddy.dart';
import '../design_tokens.dart';
import 'package:geocoding/geocoding.dart';
import '../services/drive_log.dart';
import '../rest_regulations.dart';
import 'regulation_screen.dart' show showRegulationSheet;

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

  // (11/19 사용자 요청) 이 경고가 몇 번째 운행인지 — '운행 1 · 15:08 ~ 16:08'
  late final Future<String?> _drive = () async {
    try {
      final events = await ApiService.fetchMyEvents();
      final spans = await DriveLog.load();
      for (final g in groupDrives(events, spans)) {
        if (g.events.any((x) => x.id == e.id)) {
          String hm(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';
          final to = g.end == null ? '운행 중' : hm(g.end!);
          final range = g.end != null && hm(g.start) == to ? to : '${hm(g.start)} ~ $to';
          return '운행 ${g.number} · $range';
        }
      }
    } catch (_) {}
    return null;
  }();

  // (11/19 사용자 요청) '위치' 대신 실제 주소 — '경기도 성남시 분당구 …' (폰의 주소 찾기, 못 찾으면 '위치')
  late final Future<String> _addr = () async {
    if (e.latitude == null || e.longitude == null) return '위치';
    try {
      final list = await Geocoding(locale: const Locale('ko', 'KR')).placemarkFromCoordinates(e.latitude!, e.longitude!);
      if (list.isEmpty) return '위치';
      final p = list.first;
      final parts = <String>[];
      for (final x in [p.administrativeArea, p.locality, p.subLocality, p.thoroughfare, p.subThoroughfare]) {
        final t = (x ?? '').trim();
        if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
      }
      return parts.isEmpty ? '위치' : parts.join(' ');
    } catch (_) {
      return '위치';
    }
  }();

  // (11/19 사용자 요청) 기사님께 필요 없는 괄호 설명 빼기 — '(단계는 올리지 않고 …)' · '(모의)'
  static String _clean(String t) => t
      .replaceAll(RegExp(r'\s*\([^)]*단계는[^)]*\)'), '')
      .replaceAll(RegExp(r'\s*\(모의\)'), '')
      .trim();
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
    final reason = _clean(_forDriver(_s(r['stage_reason'])));
    final regulation = _clean(_s(r['regulation']));
    final quiz = e.drivingQuiz;
    final rest = e.rest;
    final wake = r['wake'] is Map ? Map<String, dynamic>.from(r['wake']) : null;
    final eye = r['eye'] is Map ? Map<String, dynamic>.from(r['eye']) : null;
    final closedSec = eye?['closed_sec'];
    final hasPlace = e.latitude != null && e.longitude != null;

    // (11/19 사용자 요청 · Headspace) AI 보고서 — 맨 위 그라데이션 카드(그 단계 색 · 표정) → 사진 → 위치
    //   → AI 분석(흰 카드 · 질문마다 작은 아이콘) → 기사님의 대처
    final answers = <(IconData, String, String)>[
      (
        Icons.visibility_outlined,
        '무슨 일이 있었나요?',
        closedSec is num && closedSec > 0
            ? situation.replaceAll(RegExp(r'눈 감(김|긴) 시간은 짧았어요\.?'), '눈 감긴 시간은 ${closedSec.toStringAsFixed(1)}초였어요')
            : situation
      ),
      (Icons.trending_up_rounded, '왜 이 단계인가요?', reason),
      if (closedSec is num && closedSec > 0) (Icons.timer_outlined, '눈을 감은 시간', '약 ${closedSec.toStringAsFixed(1)}초'),
      (Icons.gavel_rounded, '참고한 법규', regulation),
      (Icons.record_voice_over_outlined, '기사님께 전달한 안내', e.guidance),
    ].where((x) => x.$3.trim().isNotEmpty).toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        surfaceTintColor: _bg,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: true,
        title: const Text('AI 보고서', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ① 그라데이션 카드 — 날짜 · 시각 / 큰 이유 / 단계 알약
          HsCard(
            stage: s,
            minHeight: 150,
            orb: 168,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$_date · $_time', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xB31C2033))),
              // 몇 번째 운행 · 몇 시부터 몇 시까지
              FutureBuilder<String?>(
                future: _drive,
                builder: (_, snap) => snap.data == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(snap.data!, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0x991C2033))),
                      ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(e.reasonLabel,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.7, color: AppColors.textPrimary)),
              ),
              const SizedBox(height: 12),
              StageBadge(stage: s),
            ]),
          ),
          const SizedBox(height: 14),

          // ② 사진 — 둥근 칸 (없으면 연한 칸에 안내)
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: AspectRatio(
              aspectRatio: 4 / 3,
              child: FutureBuilder<Uint8List?>(
                future: _photo,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const ColoredBox(color: AppleGray.fill, child: Center(child: CircularProgressIndicator()));
                  }
                  final bytes = snap.data;
                  if (bytes == null) {
                    return const ColoredBox(
                      color: AppleGray.fill,
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.photo_camera_outlined, size: 30, color: AppColors.textMuted),
                        SizedBox(height: 8),
                        Text('캡처 사진이 없어요', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
                      ]),
                    );
                  }
                  return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
                },
              ),
            ),
          ),

          // ③ 위치 — 애플 목록 한 줄
          if (hasPlace) ...[
            const SizedBox(height: 14),
            WebCard(
              padding: EdgeInsets.zero,
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.card),
                onTap: () => launchUrl(Uri.parse('https://map.kakao.com/link/map/경고 위치,${e.latitude},${e.longitude}'),
                    mode: LaunchMode.externalApplication),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 10, 14),
                  child: Row(children: [
                    _iconChip(Icons.location_on_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _addr,
                        builder: (_, snap) => Text(snap.data ?? '위치',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('지도에서 보기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.navy)),
                    const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron),
                  ]),
                ),
              ),
            ),
          ],

          // ④ AI 분석 — 흰 카드 · 질문마다 작은 아이콘 · 사이 얇은 선
          if (answers.isNotEmpty) ...[
            const SizedBox(height: 24),
            _heading(null, 'AI 분석', stage: s),
            WebCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (var i = 0; i < answers.length; i++) ...[
                  if (i > 0) const Divider(height: 1, thickness: 1, indent: 44, color: AppColors.line),
                  _qa(answers[i].$1, answers[i].$2, answers[i].$3,
                      onTap: answers[i].$2 == '참고한 법규' ? () => showRegulationSheet(context, RestRegulations.list) : null),
                ],
              ]),
            ),
          ],

          // ⑤ 기사님의 대처
          if (quiz.isNotEmpty || wake != null || (rest != null && rest['started'] != null)) ...[
            const SizedBox(height: 24),
            _heading(Icons.directions_car_filled_rounded, '기사님의 대처'),
            WebCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(children: [
                for (final q in quiz)
                  _qa(
                      Icons.mic_none_rounded,
                      '음성 퀴즈',
                      '“${q['asked'] ?? ''}” → ${_s(q['heard']).isEmpty ? '대답 없음' : q['heard']}'
                          ' · ${q['passed'] == true ? '통과' : '실패'}'
                          '${q['answer_sec'] is num ? ' (${(q['answer_sec'] as num).toStringAsFixed(1)}초)' : ''}',
                      plain: true),
                if (wake != null)
                  _qa(Icons.touch_app_outlined, '깨어 있어요 버튼',
                      wake['pressed'] == true ? '눌렀어요${wake['sec'] is num ? ' (${(wake['sec'] as num).round()}초)' : ''}' : '누르지 않았어요',
                      plain: true),
                if (rest != null && rest['started'] != null)
                  _qa(
                      Icons.local_cafe_outlined,
                      '휴식',
                      '${rest['started']} 정차 → ${rest['resumed'] != null ? '${rest['resumed']} 운행 재개' : '휴식 중'}'
                          '${rest['minutes'] != null ? ' (${rest['minutes']}분)' : ''}',
                      plain: true),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  // 묶음 위 제목 — 작은 남색 아이콘 + 굵은 글
  Widget _heading(IconData? icon, String text, {int? stage}) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Row(children: [
          if (stage != null) Buddy(stage: stage, size: 20, breathe: false) else Icon(icon, size: 18, color: AppColors.navy),
          const SizedBox(width: 6),
          Text(text, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary)),
        ]),
      );

  // 동그란 연한 남색 칸 안 아이콘
  Widget _iconChip(IconData icon) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.08), shape: BoxShape.circle),
        child: Icon(icon, size: 17, color: AppColors.navy),
      );

  // 질문 한 줄 — 왼쪽 아이콘 · 위 작은 회색 질문 · 아래 답
  Widget _qa(IconData icon, String label, String value, {bool plain = false, VoidCallback? onTap}) => InkWell(
        onTap: onTap,
        child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _iconChip(icon),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
              const SizedBox(height: 4),
              Text(keepWords(noDot(plain ? value : _plain(value))),
                  style: const TextStyle(fontSize: 15.5, height: 1.5, color: AppColors.textPrimary)),
              if (onTap != null)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text('법령 원문 보기 ›', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.navy)),
                ),
            ]),
          ),
        ]),
        ),
      );

  // (11/18 피드백) 어려운 말 → 쉬운 말 (서버 · AI 문장에 섞여 오는 전문 용어)
  static String _plain(String t) => t
      .replaceAllMapped(RegExp(r'PERCLOS\s*\(?([0-9.]+)\s*%\)?', caseSensitive: false), (m) => '눈을 감고 있던 시간 ${m[1]}%')
      .replaceAll(RegExp(r'PERCLOS', caseSensitive: false), '눈을 감고 있던 시간 비율')
      .replaceAll(RegExp(r'\bEAR\b'), '눈 뜬 정도')
      .replaceAll(RegExp(r'microsleep', caseSensitive: false), '아주 짧은 졸음')
      .replaceAll('미세수면', '아주 짧은 졸음(미세수면)');

  // 남색 AI 카드 안 한 줄 (11/19 안 씀 · 되돌릴 때 참고)
  // ignore: unused_element
  Widget _aiRow(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: Colors.white.withValues(alpha: 0.65))),
          const SizedBox(height: 4),
          Text(keepWords(noDot(_plain(value))),
              style: const TextStyle(fontSize: 15, height: 1.45, fontWeight: FontWeight.w600, color: Colors.white)),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _row(String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
          const SizedBox(height: 4),
          Text(keepWords(noDot(value)), style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}
