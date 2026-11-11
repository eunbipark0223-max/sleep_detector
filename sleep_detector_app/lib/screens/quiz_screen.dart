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
//   - 퀴즈는 서버가 2분에 한 번만 낸다 (VOICE_QUIZ_GAP_SEC)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 8-2
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import '../widgets/owl_says.dart';
import 'warning_screen.dart' show stageTint;

class QuizScreen extends StatefulWidget {
  final VoiceQuiz quiz;

  /// 퀴즈가 시작될 때의 단계 (배경 색)
  final int stage;

  const QuizScreen({super.key, required this.quiz, required this.stage});

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

  @override
  Widget build(BuildContext context) {
    const onColor = AppColors.textPrimary; // (11/11 C) 연한 바탕 위라 진한 글자
    final again = _guide.contains('다시');
    final guideColor = again ? AppColors.rest : AppColors.normal; // 다시 듣는 중이면 주황, 처음이면 초록

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_stage);
      },
      child: Scaffold(
        backgroundColor: stageTint(_stage), // (11/11 C) PPT 색 가이드 + 투명도 (경고 화면과 같게)
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // (11/11 C 초안) 부엉이 얼굴이 위에서 말하고, 아래 말풍선에 문제를 크게 (검정 글자가 가장 잘 보임)
                OwlAbove(owl: 'assets/owl/owl_face${_stage.clamp(0, 3)}.png', text: _quiz.display, owlSize: 210, fontSize: 48),
                const SizedBox(height: 32),
                if (_guide.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: guideColor, width: 4),
                    ),
                    child: Text(
                      _guide,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: guideColor, height: 1.3),
                    ),
                  ),
                const SizedBox(height: 20),
                Text(
                  _heard,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, color: onColor.withValues(alpha: 0.9)),
                ),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: onColor),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
