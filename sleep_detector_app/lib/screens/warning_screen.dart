// ═══════════════════════════════════════════════════════════════
// screens/warning_screen.dart — 경고 화면 (1·2·3단계) + 운전 중 음성 퀴즈
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0 (음성 · 퀴즈는 P1)
// 수업 원본: road_hazard_app/lib/screens/detect_result_screen.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - 단계별 색 · 아이콘 · 큰 글씨 한 줄 + AI 안내 카드(보라) + [규정 보기]
//   - 소리 순서: 🔔 알람 → 고정 문구(1단계 '일어나세요' / 2단계 '계속 졸고 있습니다. 가까운 졸음쉼터로 이동하세요') → driverVoice
//   - 운전 중 음성 퀴즈 (부품 A): voiceQuiz.speak 읽기 + display 크게 → 7초 듣기
//   -   화면: 문제 그대로 + '🎤 듣는 중이에요' + 말하는 글자 실시간 → submitAnswer → message 읽기
//   -   → nextQuiz 가 오면 한 번 더 → stage 로 색 갱신 (stageUp 이면 한 단계 위)
//   - 3단계: 관리자 조치완료 전까지 30초마다 '관리자에게 알렸습니다. 정차해 주세요.'
//   - 2단계 [정차했어요] → rest_screen
//
// [주의]
//   - 화면 터치로 답하지 않는다 (답은 말로만)
//   - drive_screen 위에 겹쳐 뜨는 위젯 — 별도 화면으로 이동하지 않음
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'dart:async';

import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import 'rest_screen.dart';

class WarningScreen extends StatefulWidget {
  final SleepResponse response; // 서버가 보내 준 결과

  const WarningScreen({super.key, required this.response});

  @override
  State<WarningScreen> createState() => _WarningScreenState();
}

class _WarningScreenState extends State<WarningScreen> {
  late int _stage; // 지금 화면의 단계 (정차 후 돌려받은 단계로 바뀜)
  Timer? _repeat; // 3단계 30초 반복 음성
  String _restMessage = ''; // 휴식 뒤 서버가 준 안내 (예: 주의 단계로 다시 출발합니다). 있으면 이전 단계의 요약 · 안내 · 음성 보고 대신 보여 준다

  @override
  void initState() {
    super.initState();
    _stage = widget.response.stage;
    _speakWarning();
  }

  @override
  void dispose() {
    VoiceService.stop(); // 말하기 멈춤
    _repeat?.cancel(); // 3단계 반복 멈춤
    super.dispose();
  }

  // 🔔 알람 → 고정 문구(1·2단계) → 기사 음성 보고 → (3단계) 30초마다 반복
  Future<void> _speakWarning() async {
    await VoiceService.alarm(); // 시작음
    if (!mounted) return;
    // 1·2단계 고정 문구 (3단계는 고정 문구 없이 음성 보고만 — 기획안 8-7)
    if (_stage == 1) await VoiceService.speak('일어나세요');
    if (_stage == 2) await VoiceService.speak('계속 졸고 있습니다. 가까운 졸음쉼터로 이동하세요');
    if (!mounted) return;
    final voice = widget.response.driverVoice; // 기사 음성 보고 ("최근 10분 동안 2번 졸았습니다…")
    if (voice.isNotEmpty) await VoiceService.speak(voice);
    if (!mounted) return;
    // TODO(퀴즈): D님 quiz_screen 이 올라오면 여기서 엶 (3단계 반복보다 위에 둘 것)
    if (_stage == 3) {
      _repeat = Timer.periodic(const Duration(seconds: 30), (_) {
        VoiceService.speak('관리자에게 알렸습니다. 정차해 주세요.');
      });
    }
  }

  // 단계별 큰 글씨 한 줄
  String get _headline {
    switch (_stage) {
      case 1:
        return '일어나세요';
      case 2:
        return '계속 졸고 있습니다.\n가까운 졸음쉼터로 이동하세요';
      case 3:
        return '관리자에게 알렸습니다.\n안전한 곳에 정차해 주세요.';
      default:
        return '정상 운행 중이에요';
    }
  }

  // 단계별 아이콘
  IconData get _icon {
    switch (_stage) {
      case 1:
        return Icons.notifications_active;
      case 2:
        return Icons.local_cafe;
      case 3:
        return Icons.warning_rounded;
      default:
        return Icons.check_circle;
    }
  }

  // [정차했어요] → D님 RestScreen 으로 갔다가, 닫히면 돌려받은 단계로 색 바꾸기
  Future<void> _goRest() async {
    // RestScreen 은 닫힐 때 서버 응답(Map: stage · status · message)을 돌려줘요.
    // 휴식 시작에 실패해서 닫히면 null 이 와요.
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const RestScreen()),
    );
    if (result == null || !mounted) return;
    final s = result['stage'];
    final newStage = s is num ? s.toInt() : int.tryParse('$s');
    if (newStage == null) return;
    final m = result['message'];
    setState(() {
      _stage = newStage; // 돌려받은 단계로 색 바꾸기
      // 단계가 바뀌었으면 처음 경고의 요약 · 안내 · 음성 보고는 지금 단계와 맞지 않으니 서버 안내로 바꾼다
      if (newStage != widget.response.stage) _restMessage = m is String ? m : '';
    });
  }

  // [규정 보기] — 아래에서 올라오는 창에 규정 목록
  void _showRegulations() {
    final regs = widget.response.regulations;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            const Text('관련 규정',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
            const SizedBox(height: 12),
            if (regs.isEmpty)
              const Text('표시할 규정이 없어요.', style: TextStyle(color: AppColors.textMuted)),
            for (final r in regs)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.cardBorder),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    if (r.source.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(r.source,
                            style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ),
                    const SizedBox(height: 8),
                    Text(r.content,
                        style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.response;
    final bg = AppColors.stage(_stage);
    final fg = AppColors.onStage(_stage);
    final stageChanged = _stage != r.stage; // 휴식 뒤 단계가 바뀌었으면 처음 경고의 글은 숨긴다

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        title: Text('$_stage단계 경고'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 8),
            Icon(_icon, size: 88, color: fg),
            const SizedBox(height: 16),
            // 큰 글씨 한 줄
            Text(
              _headline,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: fg, height: 1.3),
            ),
            const SizedBox(height: 16),
            // 요약
            if (stageChanged && _restMessage.isNotEmpty)
              Text(_restMessage,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fg))
            else if (!stageChanged && r.summary.isNotEmpty)
              Text(r.summary,
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: fg)),
            const SizedBox(height: 20),
            // 안내
            if (!stageChanged && r.guidance.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(r.guidance,
                    style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.4)),
              ),
            const SizedBox(height: 12),
            // 기사 음성 보고 문장 (보라 카드)
            if (!stageChanged && r.driverVoice.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.aiPurple,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('🔊 기사 음성 보고',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
                    const SizedBox(height: 6),
                    Text(r.driverVoice,
                        style: const TextStyle(fontSize: 15, color: Colors.white, height: 1.4)),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            // 버튼들
            OutlinedButton(
              onPressed: _showRegulations,
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(color: fg, width: 2),
                minimumSize: const Size.fromHeight(50),
                textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), // 주황 · 빨강 바탕에서도 글자가 또렷하게
              ),
              child: const Text('규정 보기'),
            ),
            if (_stage == 2) ...[
              const SizedBox(height: 10),
              FilledButton(
                onPressed: _goRest,
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: AppColors.textPrimary,
                  minimumSize: const Size.fromHeight(50),
                ),
                child: const Text('정차했어요'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}