// ═══════════════════════════════════════════════════════════════
// screens/warning_screen.dart — 경고 화면 (1·2·3단계) + 운전 중 음성 퀴즈
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0 (음성 · 퀴즈는 P1)
// 수업 원본: road_hazard_app/lib/screens/detect_result_screen.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - 단계별 색 · 내 얼굴(카메라) · 큰 글씨 한 줄 + AI 안내 카드(보라) + [규정 듣기]
//   - 소리 순서: 🔔 알람 → 고정 문구(1단계 '일어나세요' / 2단계 '계속 졸고 있습니다. 가까운 졸음쉼터로 이동하세요') → driverVoice
//   - 운전 중 음성 퀴즈 (부품 A): D 의 quiz_screen 을 띄우고, 돌려받은 단계로 색 갱신 (2번 실패면 한 단계 위 + 알람)
//   - 같은 단계에서 또 졸면 알람 · 음성 보고 없이 낼 퀴즈만 (silent, 기획안 6-6)
//   - 3단계: 관리자 조치완료 전까지 30초마다 알람 + '관리자에게 알렸습니다. 정차해 주세요.'
//   - 2단계 [정차했어요] → 확인 창 → rest_screen → [운행 재개] 뒤 운행 화면으로 복귀
//
// [주의]
//   - 화면 터치로 답하지 않는다 (답은 말로만)
//   - 운행 중 2 · 3단계는 뒤로 가기로 끌 수 없다 (2단계는 쉬어야, 3단계는 관리자만 해제)
//   - 운행 화면 위에 띄우는 화면 — 아래 운행 화면이 살아 있어 카메라 · 판정은 계속 (알람 · 음성 · 퀴즈 · 휴식 중에만 판정 쉼)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import 'quiz_screen.dart';
import 'regulation_screen.dart';
import 'rest_screen.dart';

/// [정차했어요] 를 누르면 한 번 더 묻는다 — 휴식은 시작하면 15분 동안 취소할 수 없어서 (잘못 누름 방지)
///   운행 화면의 휴게 배너 · 경고 화면이 같이 쓴다. [네, 정차했어요] 를 누르면 true
Future<bool> confirmRest(BuildContext context) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('정차하셨나요?'),
      content: const Text('휴식을 시작하면 15분 동안 쉬어야 운행을 다시 시작할 수 있어요.',
          style: TextStyle(fontSize: 15, height: 1.4)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('네, 정차했어요')),
      ],
    ),
  );
  return yes == true;
}

/// 얼굴을 따라가는 카메라 칸 — 칸 가운데에 얼굴이 오도록 움직이고, 얼굴 크기에 맞춰 확대한다 (화면 표시만, 판정은 카메라 전체로)
///   face : 세워서 거울처럼 본 화면 기준 얼굴 위치 (0~1 비율). 얼굴을 놓치면 마지막 위치 그대로 (운행 화면이 넘겨 줌)
class FollowFacePreview extends StatelessWidget {
  final CameraController controller;
  final ValueListenable<Rect?>? face;

  const FollowFacePreview({super.key, required this.controller, this.face});

  static const Rect _center = Rect.fromLTRB(0.25, 0.3, 0.75, 0.7); // 얼굴을 찾기 전 기본 위치
  static const double _faceFill = 0.5; // 얼굴 높이가 칸 높이의 이 비율이 되게 (주변을 넉넉히 보여 얼굴이 덜 잘리게)
  static const double _maxZoom = 2.2; // 너무 커져 흐려지지 않게

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (_, box) {
        final bw = box.maxWidth, bh = box.maxHeight;
        final pw = bw, ph = bw * controller.value.aspectRatio; // 세로 화면이라 높이 = 너비 × 가로세로비
        final minScale = max(1.0, bh / ph); // 칸을 빈틈없이 채우는 최소 배율
        return ValueListenableBuilder<Rect?>(
          valueListenable: face ?? _noFace,
          builder: (_, target, child) => TweenAnimationBuilder<Rect?>(
            tween: RectTween(end: target ?? _center),
            duration: const Duration(milliseconds: 400), // 흔들리지 않게 부드럽게
            curve: Curves.easeOut,
            child: child,
            builder: (_, r, child) {
              final f = r ?? _center;
              final scale = (bh * _faceFill / (max(f.height, 0.01) * ph)).clamp(minScale, minScale * _maxZoom);
              final sw = pw * scale, sh = ph * scale;
              return ClipRect(
                child: Stack(
                  children: [
                    Positioned(
                      left: (bw / 2 - f.center.dx * sw).clamp(bw - sw, 0.0),
                      top: (bh / 2 - f.center.dy * sh).clamp(bh - sh, 0.0),
                      width: sw,
                      height: sh,
                      child: child!,
                    ),
                  ],
                ),
              );
            },
          ),
          child: CameraPreview(controller),
        );
      },
    );
  }

  static final ValueNotifier<Rect?> _noFace = ValueNotifier<Rect?>(null);
}

/// 스크롤 없이 한 화면에 담는 배치 — 운행 화면 · 경고 화면이 같이 쓴다 (폰 크기 · 글자 크기 설정이 달라도 그대로)
///   카메라 칸이 남는 자리를 전부 쓰고, 위 · 아래 내용은 자리가 모자라면 같이 줄어든다
class OnePageLayout extends StatelessWidget {
  final Widget? banner; // 카메라 칸 위에 겹쳐 띄움
  final List<Widget> above; // 카메라 위 내용
  final Widget camera;
  final List<Widget> below; // 카메라 아래 내용 (자리가 모자라면 같이 줄어듦)
  final List<Widget> fixedBottom; // 맨 아래 버튼 — 줄어들지 않고 원래 크기 그대로 (11/09 팀장)
  final double aboveMax; // 위 내용이 쓸 수 있는 높이 비율
  final double belowMax; // 아래 내용이 쓸 수 있는 높이 비율

  const OnePageLayout({
    super.key,
    this.banner,
    this.above = const [],
    required this.camera,
    required this.below,
    this.fixedBottom = const [],
    this.aboveMax = 0.25,
    this.belowMax = 0.55,
  });
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: LayoutBuilder(
        builder: (_, box) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (above.isNotEmpty) _fit(above, box.maxWidth, box.maxHeight * aboveMax),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  camera,
                  if (banner != null) Positioned(top: 8, left: 8, right: 8, child: banner!),
                ],
              ),
            ),
            _fit(below, box.maxWidth, box.maxHeight * belowMax),
            ...fixedBottom, // 버튼은 줄이지 않는다 (누르기 쉬운 크기 유지) — 대신 카메라 칸이 그만큼 작아짐
          ],
        ),
      ),
    );
  }

  Widget _fit(List<Widget> children, double width, double maxHeight) {
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topCenter,
        child: SizedBox(
          width: width,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    );
  }
}

/// 검은 배너 "카메라를 확인하세요" — 운행 화면 · 경고 화면이 같이 쓴다
///   단계 색이 무엇이든 눈에 띄게 검은 바탕. 얼굴이 다시 잡히면 운행 화면이 값을 내려서 사라진다
class CameraBanner extends StatelessWidget {
  final ValueListenable<bool> faceLost;

  const CameraBanner({super.key, required this.faceLost});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: faceLost,
      // 카메라 칸 위에 겹쳐 뜬다 (OnePageLayout) — 평소에 빈자리를 차지하지 않고, 떠도 다른 내용이 움직이지 않게
      builder: (_, lost, _) => !lost
          ? const SizedBox.shrink()
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(14)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam_off, color: Colors.white, size: 26),
                  SizedBox(width: 10),
                  Flexible(
                    child: Text('카메라를 확인하세요',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// (11/09 팀장 지시로 지금은 화면에 쓰지 않음 — 시험 때 다시 켜 볼 수 있게 남겨 둠)
/// 흰 글자 "서버 확인: 취소" — 서버가 실제로 취소했을 때만 뜬다. 얼굴을 놓쳤다가 다시 잡히면 1초 뒤, 얼굴이 계속 보이면 5초 뒤 사라진다
///   운행 · 경고 화면 맨 아래에 고정 (Scaffold.bottomNavigationBar) — 내용이 길어도 스크롤 없이 보이게, 자리는 비워 둔다
class ServerCancelText extends StatelessWidget {
  final ValueListenable<bool> cancelled;

  const ServerCancelText({super.key, required this.cancelled});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: cancelled,
      builder: (_, on, _) => SafeArea(
        top: false,
        child: Visibility(
          visible: on,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: const Padding(
            padding: EdgeInsets.only(top: 4, bottom: 8),
            child: Text('서버 확인: 취소',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}

class WarningScreen extends StatefulWidget {
  final SleepResponse response; // 서버가 보내 준 결과

  /// 운행 화면이 알려 주는 지금 단계 (ping). 해제되면 반복 음성을 멈추고, 0단계면 이 화면을 닫는다.
  /// 사진 1장 테스트처럼 운행 중이 아니면 null
  final ValueListenable<int>? liveStage;

  /// 퀴즈 · 휴식 화면을 띄우는 동안 true 로 바꿔 운행 화면의 졸음 판정을 쉬게 한다 (운행 중이 아니면 null)
  final ValueNotifier<bool>? pauseDetect;

  /// 운행 화면의 카메라 — 있으면 맨 위에 내 얼굴(카메라 화면)을 보여 준다 (사진 1장 테스트처럼 없으면 큰 아이콘)
  final ValueListenable<CameraController?>? camera;

  /// 운행 화면이 알려 주는 "카메라를 확인하세요" · "서버 확인: 취소" 상태 (운행 중이 아니면 null)
  final ValueListenable<bool>? faceLost;
  final ValueListenable<bool>? serverCancelled;

  /// 운행 화면이 알려 주는 얼굴 위치 — 카메라 칸이 얼굴을 따라가게
  final ValueListenable<Rect?>? faceBox;

  /// 앱을 껐다 켰을 때 쉬는 중이었다면 true — 경고 음성 대신 바로 휴식 화면을 이어 연다 (남은 시간은 서버가 알려 줌)
  final bool resumeRest;

  /// 같은 단계에서 또 졸았을 때 true — 알람 · 고정 문구 · 음성 보고를 다시 내지 않고 퀴즈만 (기획안 6-6)
  final bool silent;

  const WarningScreen(
      {super.key,
      required this.response,
      this.liveStage,
      this.pauseDetect,
      this.camera,
      this.faceLost,
      this.serverCancelled,
      this.faceBox,
      this.silent = false,
      this.resumeRest = false});

  @override
  State<WarningScreen> createState() => _WarningScreenState();
}

class _WarningScreenState extends State<WarningScreen> {
  late int _stage; // 지금 화면의 단계 (정차 후 돌려받은 단계로 바뀜)
  Timer? _repeat; // 3단계 30초 반복 음성
  String _restMessage = ''; // 휴식 뒤 서버가 준 안내 (예: 주의 단계로 다시 출발합니다). 있으면 이전 단계의 요약 · 안내 · 음성 보고 대신 보여 준다
  bool _voiceDone = false; // 알람 · 음성 · 퀴즈가 다 끝났는지 ([규정 듣기] 는 그 뒤에 켜짐)
  bool _flowStopped = false; // [정차했어요] 를 눌러 음성 · 퀴즈 순서를 그만둠 (휴식 화면 위로 퀴즈가 뜨지 않게)
  bool _readingRegs = false; // 규정을 읽는 중 (30초 반복이 끊지 않게)
  bool _keepSpeaking = false; // 닫혀도 말을 끊지 않음 (운행 재개 안내를 끝까지 듣게)

  // 운행 중 2 · 3단계 경고는 뒤로 가기로 끌 수 없다 (2단계는 쉬어야, 3단계는 관리자만 해제). 사진 1장 테스트는 나갈 수 있음
  bool get _locked => widget.liveStage != null && _stage >= 2;

  @override
  void initState() {
    super.initState();
    _stage = widget.response.stage;
    widget.liveStage?.addListener(_onLiveStage);
    widget.pauseDetect?.value = true; // 알람 · 음성 · 퀴즈가 끝날 때까지 졸음 판정 쉬기
    if (widget.resumeRest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goRest(); // 앱을 껐다 켠 뒤 — 쉬던 중이니 알람 없이 바로 휴식 화면
      });
    } else {
      _speakWarning();
    }
  }

  @override
  void dispose() {
    widget.liveStage?.removeListener(_onLiveStage);
    widget.pauseDetect?.value = false; // 혹시 쉬는 중에 닫혀도 판정은 다시 켠다
    if (!_keepSpeaking) VoiceService.stop(); // 말하기 멈춤
    _repeat?.cancel(); // 3단계 반복 멈춤
    _repeat = null;
    super.dispose();
  }

  // 운행 화면의 ping 이 단계를 바꿔 알려 줌 (1단계 자동 해제 · 관리자 조치완료 · 휴식 완료)
  void _onLiveStage() {
    final s = widget.liveStage!.value;
    if (!mounted || s == _stage) return;
    if (s < 3) {
      _repeat?.cancel(); // 3단계가 풀리면 30초 반복 멈춤
      _repeat = null;
    }
    if (s == 0) {
      // 완전 해제 → 소리 멈추고 경고 화면 닫기 (퀴즈 · 휴식 화면이 위에 떠 있으면 닫지 않음)
      VoiceService.stop();
      if (ModalRoute.of(context)?.isCurrent ?? false) {
        Navigator.of(context).pop();
        return;
      }
    }
    setState(() => _stage = s);
    if (s == 3 && _voiceDone) _startRepeat(); // 음성 · 퀴즈 중이면 끝난 뒤에 시작 (퀴즈 듣기를 끊지 않게)
  }

  // 3단계 30초 반복 시작 (이미 돌고 있으면 그대로) — 알람 + 고정 문구 (기획안 8-7)
  void _startRepeat() {
    _repeat ??= Timer.periodic(const Duration(seconds: 30), (_) async {
      if (_readingRegs) return; // 규정을 듣는 중에는 끊지 않음
      await VoiceService.alarm();
      if (!mounted || _repeat == null || _readingRegs) return;
      await VoiceService.speak('관리자에게 알렸습니다. 정차해 주세요.');
    });
  }

  // 🔔 알람 → 고정 문구(1·2단계) → 기사 음성 보고 → (3단계) 30초마다 반복
  //   silent 면 알람 · 문구 · 음성 보고를 건너뛰고 퀴즈부터 (같은 단계에서 또 졸았을 때)
  //   [정차했어요] 를 누르면 _flowStopped → 뒤 순서를 하지 않는다
  Future<void> _speakWarning() async {
    if (!widget.silent) {
      await VoiceService.alarm(); // 시작음
      if (!mounted || _flowStopped) return;
      // 1·2단계 고정 문구 (3단계는 고정 문구 없이 음성 보고만 — 기획안 8-7)
      if (_stage == 1) await VoiceService.speak('일어나세요');
      if (_stage == 2) await VoiceService.speak('계속 졸고 있습니다. 가까운 졸음쉼터로 이동하세요');
      if (!mounted || _flowStopped) return;
      final voice = widget.response.driverVoice; // 기사 음성 보고 ("최근 10분 동안 2번 졸았습니다…")
      if (voice.isNotEmpty) await VoiceService.speak(voice);
      if (!mounted || _flowStopped) return;
    } else {
      // 화면이 만들어지는 중에는 퀴즈 화면을 띄울 수 없어서 잠깐 기다린다
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || _flowStopped) return;
    }
    // 운전 중 음성 퀴즈 (D님 QuizScreen) — 서버가 2분 간격으로만 보내서 없을 수도 있음
    final quiz = widget.response.voiceQuiz;
    if (quiz != null) {
      final before = _stage;
      final newStage = await Navigator.push<int>(
        context,
        MaterialPageRoute(builder: (_) => QuizScreen(quiz: quiz, stage: _stage)),
      );
      if (!mounted) return;
      // 퀴즈 중에 해제됐으면 (조치완료 · 1단계 자동 해제) 이제 경고 화면을 닫는다
      if (widget.liveStage?.value == 0) {
        VoiceService.stop();
        Navigator.of(context).pop();
        return;
      }
      if (newStage != null) setState(() => _stage = newStage); // 2번 실패하면 단계가 올라옴
      if (newStage != null && newStage > before) {
        await VoiceService.alarm(); // 2번 실패로 단계가 올라감 → 알람 (기획안 8-7)
        if (!mounted || _flowStopped) return;
      }
    }
    // 알람 · 음성 · 퀴즈가 다 끝났으니 이제부터 졸음 판정 (퀴즈가 없었으면 음성 보고가 끝난 뒤부터)
    widget.pauseDetect?.value = false;
    setState(() => _voiceDone = true);
    // 3단계 30초 반복은 퀴즈가 끝난 뒤에 시작
    if (_stage == 3) _startRepeat();
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

  // 맨 위 그림 — 운행 중이면 카메라 화면(내 얼굴) + 오른쪽 아래 단계 아이콘 배지, 카메라가 없으면 큰 아이콘
  Widget _topVisual(Color bg, Color fg) {
    final bigIcon = Center(child: FittedBox(child: Icon(_icon, size: 88, color: fg)));
    final cam = widget.camera;
    if (cam == null) return bigIcon;
    return ValueListenableBuilder<CameraController?>(
      valueListenable: cam,
      builder: (_, c, _) {
        if (c == null || !c.value.isInitialized) return bigIcon;
        // 카메라 칸 크기는 남는 자리에 맞추고 (OnePageLayout), 칸 안에서는 얼굴을 따라간다
        return Stack(
          fit: StackFit.expand,
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(17),
                child: FollowFacePreview(controller: c, face: widget.faceBox),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                child: Icon(_icon, size: 24, color: bg),
              ),
            ),
          ],
        );
      },
    );
  }

  // [정차했어요] → D님 RestScreen 으로 갔다가, 닫히면 돌려받은 단계로 색 바꾸기
  Future<void> _goRest() async {
    // RestScreen 은 닫힐 때 서버 응답(Map: stage · status · message)을 돌려줘요.
    // 휴식 시작에 실패해서 닫히면 null 이 와요.
    _flowStopped = true; // 남은 음성 · 퀴즈는 하지 않음 (쉬러 가는 기사에게 퀴즈를 내지 않게)
    setState(() => _voiceDone = true);
    await VoiceService.stop();
    if (!mounted) return;
    widget.pauseDetect?.value = true; // 휴식 중에는 졸음 판정 쉬기 (기획안: 휴식 중 눈 판정 멈춤)
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(builder: (_) => const RestScreen()),
    );
    widget.pauseDetect?.value = false; // 휴식이 끝나면 다시 판정
    if (result == null || !mounted) return;
    final s = result['stage'];
    final newStage = s is num ? s.toInt() : int.tryParse('$s');
    if (newStage == null) return;
    // 운행 중 휴식이 끝나 1단계 이하면 운행 화면으로 돌아간다 (기획안 8-5). 안내 음성은 끊지 않음
    if (widget.liveStage != null && newStage < 2) {
      _keepSpeaking = true;
      Navigator.of(context).pop(newStage);
      return;
    }
    final m = result['message'];
    setState(() {
      _stage = newStage; // 돌려받은 단계로 색 바꾸기
      // 단계가 바뀌었으면 처음 경고의 요약 · 안내 · 음성 보고는 지금 단계와 맞지 않으니 서버 안내로 바꾼다
      if (newStage != widget.response.stage) _restMessage = m is String ? m : '';
    });
  }

  // [규정 듣기] — 운전 중에는 글을 읽기 어려우니 소리로 읽어 주고, 화면에도 띄운다. 창을 닫으면 읽기도 멈춘다
  Future<void> _showRegulations() async {
    final regs = widget.response.regulations;
    _readingRegs = true;
    _speakRegulations(regs);
    await showRegulationSheet(context, regs); // regulation_screen 의 공용 카드 창
    _readingRegs = false;
    VoiceService.stop(); // 창을 닫으면 읽기도 멈춘다
  }

  // 규정 소리는 지금 단계의 한 문장만 — 조문을 그대로 읽으면 운전 중에 듣기 어려워서 (화면 카드는 원문 그대로, 11/05 팀장 · B 확인)
  Future<void> _speakRegulations(List<Regulation> regs) async {
    if (regs.isEmpty) {
      await VoiceService.speak('관련 규정이 없어요.');
      return;
    }
    await VoiceService.speak(_regulationVoice);
  }

  String get _regulationVoice {
    const more = '자세한 내용은 정차한 뒤 화면에서 확인하세요.';
    switch (_stage) {
      case 2:
        return '화물차와 시외·전세버스 기사는 2시간 연속 운전 후 15분 이상 쉬어야 합니다. $more';
      case 3:
        return '안전한 곳에 바로 정차해 주세요. $more';
      default:
        return '과로로 정상적인 운전이 어려운 상태의 운전은 법으로 금지되어 있습니다. $more';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.response;
    final bg = AppColors.stage(_stage);
    final fg = AppColors.onStage(_stage);
    final stageChanged = _stage != r.stage; // 휴식 뒤 단계가 바뀌었으면 처음 경고의 글은 숨긴다

    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        backgroundColor: bg,
        // "서버 확인: 취소" 글은 기사님 화면에 보여 주지 않는다 (서버 판단 설명, 11/09 팀장)
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          automaticallyImplyLeading: !_locked,
          title: Text('$_stage단계 경고'),
        ),
        body: SafeArea(
          child: OnePageLayout(
            banner: widget.faceLost == null ? null : CameraBanner(faceLost: widget.faceLost!),
            camera: _topVisual(bg, fg),
            below: [
              const SizedBox(height: 12),
              // 큰 글씨 한 줄
              // 글은 줄 수를 정해 둔다 (maxLines) — AI 문장이 길어도 화면이 넘치거나 글자가 너무 작아지지 않게
              Text(
                _headline,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: fg, height: 1.25),
              ),
              const SizedBox(height: 10),
              // 요약
              if (stageChanged && _restMessage.isNotEmpty)
                Text(_restMessage,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fg))
              else if (!stageChanged && r.summary.isNotEmpty)
                Text(r.summary,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: fg)),
              const SizedBox(height: 12),
              // 안내
              if (!stageChanged && r.guidance.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(r.guidance,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, height: 1.4)),
                ),
              const SizedBox(height: 8),
              // 기사 음성 보고 문장 (보라 카드)
              if (!stageChanged && r.driverVoice.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      const SizedBox(height: 4),
                      Text(r.driverVoice,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.35)),
                    ],
                  ),
                ),
              const SizedBox(height: 4),
            ],
            // 버튼들 — 맨 아래 고정, 줄어들지 않음
            fixedBottom: [
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _voiceDone ? _showRegulations : null, // 알람 · 음성 · 퀴즈가 끝난 뒤에 누를 수 있음
                style: OutlinedButton.styleFrom(
                  foregroundColor: fg,
                  disabledForegroundColor: fg.withValues(alpha: 0.5),
                  side: BorderSide(color: fg, width: 2),
                  minimumSize: const Size.fromHeight(50),
                  textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), // 주황 · 빨강 바탕에서도 글자가 또렷하게
                ),
                icon: const Icon(Icons.volume_up_rounded),
                label: const Text('규정 듣기'),
              ),
              if (_stage == 2) ...[
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: () async {
                    if (await confirmRest(context) && mounted) _goRest();
                  },
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
      ),
    );
  }
}