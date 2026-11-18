// ═══════════════════════════════════════════════════════════════
// screens/quiz_screen.dart — 운전 중 음성 퀴즈 화면 (부품 A — 10/29 확정)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P1
// 수업 원본: (없음, 🔴 신규)
//
// [이 파일이 하는 일]
//   - 서버가 준 퀴즈 1문제를 소리로 읽고(VoiceService.speak) → 말로 대답을 듣고(listen) → 서버에 보내(submitAnswer)
//     결과 안내를 읽는다. 서버가 같은 유형의 새 문제(nextQuiz)를 주면 한 번 더 (최대 2번 기회)
//   - 운전 중이라 버튼 · 입력칸 없음 — 답은 말로만 (기획안 8-1)
//   - 통과해도 단계는 안 내려간다. 2번 실패하면 서버가 단계 +1 · no_response 경고를 저장하고 stage 로 알려 준다
//
// [쓰는 법 — 약속 (C 의 warning_screen 이 부른다)]
//   - final stage = await Navigator.push<int>(context, MaterialPageRoute(builder: (_) => QuizScreen(quiz: r.voiceQuiz!, stage: r.stage)));
//   - 끝나면 마지막 단계(int)를 돌려준다 → 받은 쪽이 그 값으로 경고 화면 색을 바꾼다
//   - 마이크 권한 · 인식기가 없으면(listen 이 null) 서버에 보내지 않고 바로 닫는다 — 실패로 세지 않는다
//   - 뒤로 가기를 눌러도 지금 단계를 돌려주며 닫힌다 (음성도 멈춘다)
//
// [주의]
//   - 말하기 · 듣기는 VoiceService 로만 한다 (flutter_tts / speech_to_text 를 직접 쓰지 않음)
//   - await 뒤에는 항상 mounted 확인, 닫을 때 VoiceService.stop()
//   - 퀴즈는 서버가 2단계에 들어갈 때마다 낸다 (11/18 2분 간격 뺌)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 8-2
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';

class QuizScreen extends StatefulWidget {
  final VoiceQuiz quiz;

  /// 퀴즈가 시작될 때의 단계 (배경 색)
  final int stage;

  /// 디자인 미리보기 전용 (tools/quiz_preview_main.dart) — 읽기 · 듣기를 하지 않고 이 글을 보여 준다. 앱에서는 쓰지 않음
  final String? previewGuide;
  final String? previewHeard;

  const QuizScreen({super.key, required this.quiz, required this.stage, this.previewGuide, this.previewHeard});

  @override
  State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  late VoiceQuiz _quiz = widget.quiz;
  late int _stage = widget.stage;
  String _guide = '';
  String _heard = '';
  String _message = '';

  @override
  void initState() {
    super.initState();
    if (widget.previewGuide != null || widget.previewHeard != null) {
      _guide = widget.previewGuide ?? '';
      _heard = widget.previewHeard ?? '';
      return;
    }
    _run();
  }

  Future<void> _run() async {
    while (mounted) {
      setState(() {
        _guide = '';
        _heard = '';
        _message = '';
      });
      await VoiceService.speak(_quiz.speak);
      if (!mounted) return;
      final heard = await VoiceService.listen(
        type: _quiz.type,
        display: _quiz.display,
        listenSec: _quiz.listenSec,
        onPartial: (t) {
          if (mounted) setState(() => _heard = t);
        },
        onGuide: (g) {
          if (mounted) setState(() => _guide = g);
        },
      );
      if (!mounted) return;
      if (heard == null) break; // 마이크 권한 없음 · 인식기 없음 → 서버에 보내지 않음 (실패로 안 셈)
      try {
        final r = await ApiService.submitAnswer(_quiz.quizId, heard, VoiceService.lastAnswerSec);
        if (!mounted) return;
        setState(() {
          _stage = r.stage;
          _message = r.message;
          _guide = '';
        });
        await VoiceService.speak(r.message);
        if (!mounted) return;
        if (r.nextQuiz != null) {
          _quiz = r.nextQuiz!; // 두 번째 기회 (같은 유형 새 문제)
          continue;
        }
      } catch (e) {
        debugPrint('[quiz] 답 보내기 실패: $e'); // 서버 문제 → 퀴즈만 끝냄
      }
      break;
    }
    if (mounted) Navigator.of(context).pop(_stage);
  }

  @override
  void dispose() {
    VoiceService.stop();
    super.dispose();
  }

  // ── 화면 (11/16 Figma 시안 '졸음운전 감지 앱5' 음성 퀴즈 — 디자인만. 읽기 · 듣기 · 채점 흐름은 위 그대로) ──
  // (11/16 팀장) 운전 중에 뜨는 화면이라 운행 · 경고 화면과 같은 남색 (밤에 흰 화면이 눈부시지 않게)
  static const Color _bg = AppColors.navyDeep; // (11/17 R안 · readdy 퀴즈) 진한 남색
  static const Color _sub = Color(0xFFBEC8E9);

  String get _typeLabel => switch (_quiz.type) {
        'add' => '간단 계산',
        'reverse' => '거꾸로 말하기',
        _ => '따라 말하기',
      };

  @override
  Widget build(BuildContext context) {
    final again = _guide.contains('다시');
    final listening = _guide.isNotEmpty;
    final stateColor = again ? AppColors.rest : const Color(0xFF5FD38D); // 다시 듣는 중이면 주황, 처음이면 초록
    final question = _quiz.type == 'add' ? _quiz.display : '“${_quiz.display}”';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_stage);
      },
      child: Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _bg,
          surfaceTintColor: _bg,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.chevron_left, size: 30),
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).pop(_stage),
          ),
          title: const Text('음성 퀴즈', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 문제 종류 (알약)
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                    child: Text(_typeLabel,
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 22),
                const Text('큰 소리로 말해 주세요',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: _sub)),
                const SizedBox(height: 10),
                // 문제 — 크게
                Text(question,
                    textAlign: TextAlign.center,
                    maxLines: 4,
                    style: const TextStyle(
                        fontSize: 32, height: 1.3, fontWeight: FontWeight.w900, letterSpacing: -0.8, color: Colors.white)),
                const Spacer(),
                // 마이크 (듣는 중이면 물결)
                Center(child: _MicOrbit(active: listening, color: stateColor)),
                const SizedBox(height: 12),
                SizedBox(
                  height: 30,
                  child: listening
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 9, height: 9, decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle)),
                            const SizedBox(width: 7),
                            Text(again ? '다시 한번 말씀해 주세요' : '듣는 중',
                                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: stateColor)),
                          ],
                        )
                      : null,
                ),
                const Spacer(),
                // 들은 글자 · 결과
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_message.isNotEmpty ? '결과' : '들은 글자',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: _sub)),
                      const SizedBox(height: 6),
                      Text(
                        _message.isNotEmpty ? _message : (_heard.isEmpty ? '…' : _heard),
                        style: const TextStyle(fontSize: 21, height: 1.35, fontWeight: FontWeight.w800, color: Colors.white),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 마이크 원 — 흰 가운데 + 듣는 중이면 바깥으로 퍼지는 물결 3겹
class _MicOrbit extends StatefulWidget {
  final bool active;
  final Color color;
  const _MicOrbit({required this.active, required this.color});

  @override
  State<_MicOrbit> createState() => _MicOrbitState();
}

class _MicOrbitState extends State<_MicOrbit> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 200,
      height: 200,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Stack(
          alignment: Alignment.center,
          children: [
            for (var i = 0; i < 3; i++)
              Builder(builder: (_) {
                final t = widget.active ? (_c.value + i / 3) % 1.0 : 0.25 + i * 0.25;
                return Container(
                  width: 96 + 100 * t,
                  height: 96 + 100 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: widget.active ? (1 - t) * 0.45 : 0.10), width: 2),
                  ),
                );
              }),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.mic, size: 44, color: AppColors.navy),
            ),
          ],
        ),
      ),
    );
  }
}
