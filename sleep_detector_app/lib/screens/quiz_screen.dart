// ═══════════════════════════════════════════════════════════════
// screens/quiz_screen.dart — 운전 중 음성 퀴즈 화면 (부품 A — 10/29 확정)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P1
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
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/buddy.dart';
import '../widgets/owl_says.dart' show balancedLines;

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
  String _message = '';

  @override
  void initState() {
    super.initState();
    if (widget.previewGuide != null || widget.previewHeard != null) {
      _guide = widget.previewGuide ?? '';
      return;
    }
    _run();
  }

  Future<void> _run() async {
    while (mounted) {
      setState(() {
        _guide = '';
        _message = '';
      });
      await VoiceService.speak(_quiz.speak);
      if (!mounted) return;
      final heard = await VoiceService.listen(
        type: _quiz.type,
        display: _quiz.display,
        listenSec: _quiz.listenSec,
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
  // (11/18 피드백 · 애플 토큰) 흰 바탕 · 검정 제목 · 회색 설명 · 남색은 마이크에만
  static const Color _bg = AppColors.background;

  String get _typeLabel => switch (_quiz.type) {
        'add' => '간단 계산',
        'reverse' => '거꾸로 말하기',
        _ => '크게 말하기', // (11/19 팀장) 질문 '크게 말하세요' 와 맞춤 (전: 따라 말하기)
      };

  @override
  Widget build(BuildContext context) {
    final again = _guide.contains('다시');
    final listening = _guide.isNotEmpty;
    final stateColor = again ? AppColors.rest : AppColors.normal; // 다시 듣는 중이면 주황, 처음이면 초록
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
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).pop(_stage),
          ),
          title: const Text('음성 퀴즈'),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(AppSpace.l, 4, AppSpace.l, AppSpace.l),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // (11/19 사용자 요청 · Headspace) 단계 알약 + 큰 흰 카드 안에 따라 말할 문장 (운전석에서 한눈에 읽히게 아주 크게)
                // (11/24 사용자 요청 · 애플식) 모든 글 왼쪽 시작선
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(12, 7, 14, 7),
                    decoration: BoxDecoration(color: AppColors.stageTint(_stage), borderRadius: BorderRadius.circular(999)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(color: AppColors.stage(_stage), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 7),
                      Text('${const ['정상', '주의', '휴식 권고', '긴급'][_stage.clamp(0, 3)]} · $_typeLabel',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.stageInk(_stage))),
                    ]),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 26),
                  decoration: BoxDecoration(
                    // (11/23 리디자인_3) 흰색 → 아주 연한 노랑 · 얇은 테두리 · 둥글기 16
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    // (11/24) 흰 카드 · 테두리 없이 부드러운 그림자
                    color: Colors.white,
                    boxShadow: AppShadow.card,
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Buddy(stage: 2, size: 30, breathe: false), // (11/23 사용자 요청) 2단계 주황
                      const SizedBox(width: 10),
                      const Text('크게 말하세요', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xB31C2033))),
                    ]),
                    const SizedBox(height: 16),
                    // (11/24 사용자 요청 · 3단계 카드처럼) 뜻 단위로 한 줄씩 · 줄마다 한 줄 고정 (단어 중간에서 안 끊김) · 왼쪽 시작선
                    for (final (i, line) in balancedLines(question.replaceAll('"', '').replaceAll('“', '').replaceAll('”', '')).indexed) ...[
                      if (i > 0) const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.only(left: 40), // (11/24 사용자 요청) '크게 말하세요' 글자와 같은 시작선
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(line,
                              maxLines: 1,
                              softWrap: false,
                              style: const TextStyle(fontSize: 34, height: 1.3, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.textPrimary)), // (11/24) 조금 크게
                        ),
                      ),
                    ],
                  ]),
                ),
                const Spacer(),
                // 마이크 (듣는 중이면 물결)
                Center(child: _MicOrbit(active: listening, color: stateColor)),
                const SizedBox(height: 12),
                // (11/24 사용자 요청) 남색 점 + '듣는 중' — 카드 안 '크게 말하세요' 와 같은 시작선 · '들은 글자' 칸은 뺌 (결과는 이 줄에)
                SizedBox(
                  height: 30,
                  child: (listening || _message.isNotEmpty)
                      ? Padding(
                          padding: const EdgeInsets.only(left: 20),
                          child: Row(children: [
                            Container(width: 9, height: 9, decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle)),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(listening ? (again ? '다시 한번 말씀해 주세요' : '듣는 중') : _message,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppType.headline.copyWith(color: AppColors.textPrimary)),
                            ),
                          ]),
                        )
                      : null,
                ),
                const Spacer(),
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
                        color: AppColors.navy.withValues(alpha: widget.active ? (1 - t) * 0.35 : 0.06), width: 2),
                  ),
                );
              }),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: AppColors.navy,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 16, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.mic_rounded, size: 42, color: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
