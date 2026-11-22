// ═══════════════════════════════════════════════════════════════
// screens/warning_screen.dart — 경고 화면 (1·2·3단계) + 운전 중 음성 퀴즈
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0 (음성 · 퀴즈는 P1)
//
// [이 파일이 하는 일]
//   - 단계별 색 · 내 얼굴(카메라) · 큰 글씨 한 줄 (11/18 2단계 [규정 보기] · 1 · 3단계 [규정 듣기] 모두 뺌 → 규정은 휴식 화면 · 경고 기록 상세 · 규정 도우미)
//   - 2단계 순서 (11/18 팀장): 🔔 + 'OOO님, 쉼터에서 쉬어 가세요.' → 퀴즈 (필수, 버튼 꺼짐) → 통과하면 쉼터 한 줄 + [가까운 졸음쉼터 안내] · [정차했어요]
//   - 소리 순서: 🔔 알람 → 서버 한 문장 driverVoice ('OOO님, 쉼터에서 쉬어 가세요.' / '… 지금 바로 정차하세요.', 없으면 stage_texts.dart 고정 문구) (11/17)
//   - 운전 중 음성 퀴즈 (부품 A): D 의 quiz_screen 을 띄우고, 돌려받은 단계로 색 갱신 (2번 실패면 한 단계 위 + 알람)
//   - 같은 단계에서 또 졸면 알람 · 음성 보고 없이 낼 퀴즈만 (silent, 기획안 6-6)
//   - 3단계: 관리자 조치완료 전까지 30초마다 알람 + 'OOO님, 지금 바로 정차하세요.' ('관리자에게 알렸어요' 는 화면 큰 글씨, 11/17)
//   - 졸음쉼터 안내 (B 의 rest_area_service): 자동으로 읽지 않음 (11/17) — 2단계 화면에 '📍 가까운 ○○ 졸음쉼터, ○○방향, 약 ○킬로미터' 한 줄
//     + [가까운 졸음쉼터 듣기] → 다시 읽고 지도 화면 (새 창 없음, 3단계는 길안내를 먼저 권하지 않음, 30초 반복은 짧게 그대로)
//   - 2단계 [정차했어요] → 확인 창 (음성 · 1분 뒤 저절로 취소) → rest_screen → [운행 재개] 뒤 운행 화면으로 복귀
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
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../services/rest_area_service.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../stage_texts.dart';
import '../theme.dart';
import '../widgets/stage_layout.dart';
import 'map_screen.dart';
import 'quiz_screen.dart';
import 'rest_screen.dart';
import '../widgets/buddy.dart';

/// "정차하셨나요?" 창을 아무것도 안 누르고 띄워 둘 수 있는 시간 — 지나면 [취소]처럼 닫힌다 (11/10 팀장 · C: 1분)
const int confirmRestSec = 60;

/// [정차했어요] 를 누르면 한 번 더 묻는다 — 휴식은 시작하면 15분 동안 취소할 수 없어서 (잘못 누름 방지)
///   운행 화면의 휴게 배너 · 경고 화면이 같이 쓴다. [네, 정차했어요] 를 누르면 true
///   창이 뜰 때 같은 내용을 음성으로 한 번 읽어 준다 (운전 중이라 화면을 못 볼 수 있어서)
///   confirmRestSec 초 동안 아무것도 안 누르면 저절로 닫힘 (= 취소) — 창을 띄워 둔 채 경고를 피하는 꼼수 막기
Future<bool> confirmRest(BuildContext context) async {
  var open = true;
  Timer? autoClose;
  // (11/16 팀장) 휴식 시간은 서버 값(REST_WAIT_SEC)이라 앱에 '15분'을 박지 않음 — 시연 5초인데 15분이라고 말하던 것
  VoiceService.speak('정차하셨나요? 휴식을 시작하면 쉬는 시간이 끝나야 운행을 다시 시작할 수 있어요.');
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      autoClose ??= Timer(const Duration(seconds: confirmRestSec), () {
        if (open && ctx.mounted) Navigator.pop(ctx, false);
      });
      // (11/18 피드백 · 애플 스타일) 아이폰 기본 알림창 — 가운데 제목 · 설명, 아래 [취소 | 네, 정차했어요] 를 가는 선으로 나눔
      //   운전 중 손가락으로 누르기 쉽게 글자는 아이폰보다 조금 크게
      return CupertinoAlertDialog(
        title: const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('정차하셨나요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        content: const Text('휴식을 시작하면 쉬는 시간이 끝나야\n운행을 다시 시작할 수 있어요',
            style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            textStyle: const TextStyle(fontSize: 18, color: AppColors.textSecondary),
            child: const Text('취소'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
            child: const Text('네, 정차했어요'),
          ),
        ],
      );
    },
  );
  open = false;
  autoClose?.cancel();
  return yes == true;
}


/// 단계 바탕색 — 발표 PPT 색 가이드(테마 색 = AppColors 단계 색) 그대로에 투명도 30% 를 앱 바탕(#F3F5FA) 위에 (11/11)
///   원색 그대로는 화면이 너무 쨍해서 눈이 아프고, 같은 색 부엉이가 바탕에 묻힘 → 같은 색 계열의 연한 바탕 + 진한 글자
///   경고 · 운행 · 퀴즈 화면이 같이 쓴다
///   투명도는 단계마다 다르게 — 같은 30% 면 노랑(주의)과 주황(휴식 권고)이 거의 같아 보여서, 주황을 진하게 (11/11)
///   정상 30% #B8DBCA · 주의 40% #F3D9A2 · 휴식 권고 55% #F2BB86 · 긴급 40% #E9A6A5
const List<double> _stageTintAlpha = [0.30, 0.40, 0.55, 0.40];
Color stageTint(int stage) {
  final s = stage.clamp(0, 3);
  return Color.alphaBlend(AppColors.stage(s).withValues(alpha: _stageTintAlpha[s]), AppColors.background);
}

/// 가까운 졸음쉼터 1곳 음성 문장 — "가까운 ○○ 졸음쉼터, ○○방향, 약 ○킬로미터" (B 의 rest_area_service 문장 그대로)
///   경고 화면(2 · 3단계) · 운행 화면 휴게 띠(2시간 연속 운전)가 같이 쓴다. 위치를 모르거나 5초 안에 못 찾으면 null
Future<String?> nearRestVoice(double? lat, double? lng) async {
  if (lat == null || lng == null) return null;
  try {
    final near = await nearestRestAreasByRoad(lat, lng, n: 1).timeout(const Duration(seconds: 5));
    return near.isEmpty ? null : near.first.voice;
  } catch (_) {
    return null;
  }
}

/// [가까운 졸음쉼터 듣기] — 쉼터 문장을 다시 읽어 주고 B 의 지도 화면을 연다 (목록 · [길찾기] · 반대편 차로면 다른 쉼터)
///   새 창(길안내를 시작할까요?)은 만들지 않음 — 운전 중에 버튼 여러 개짜리 창을 보고 누르지 않게 (11/11 팀장)
Future<void> listenRestMap(BuildContext context, Future<String?> voice) async {
  final v = await voice;
  if (!context.mounted) return;
  if (v != null) VoiceService.speak(v); // 기다리지 않음 — 읽는 동안 지도가 뜸
  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MapScreen()));
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

/// 남색 띠 "졸음인지 확인하고 있어요…" — 졸음 의심을 서버에 보내고 답을 기다리는 동안 (운행 · 경고 화면 같이, 11/12 팀장 UX)
///   서버가 4 ~ 6초 걸리는 동안 화면에 아무 변화가 없어 "안 되나?" 싶던 것을 보여 준다
class CheckingBanner extends StatelessWidget {
  final ValueListenable<bool> checking;

  const CheckingBanner({super.key, required this.checking});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: checking,
      builder: (_, on, _) => !on
          ? const SizedBox.shrink()
          : Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(14)),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                  SizedBox(width: 12),
                  Flexible(
                    child: Text('졸음인지 확인하고 있어요…',
                        style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
    );
  }
}

/// 흰 글자 "서버 확인: 취소" — 서버가 실제로 취소했을 때만 뜬다. 얼굴을 놓쳤다가 다시 잡히면 1초 뒤, 얼굴이 계속 보이면 5초 뒤 사라진다
///   운행 · 경고 화면 맨 아래에 고정 (Scaffold.bottomNavigationBar) — 내용이 길어도 스크롤 없이 보이게, 자리는 비워 둔다
class ServerCancelText extends StatelessWidget {
  final ValueListenable<bool> cancelled;
  final Color color; // (11/15) 운행 화면은 남색 배경이라 흰 글자

  const ServerCancelText({super.key, required this.cancelled, this.color = AppColors.textPrimary});

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
          child: Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text('졸음이 아닌 것으로 확인됐어요',
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.w600)), // 연한 바탕 위라 진한 글자 (11/11)
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

  /// 운행 화면이 서버 답을 기다리는 중 — "졸음인지 확인하고 있어요…" 띠 (운행 중이 아니면 null, 11/12)
  final ValueListenable<bool>? checking;

  /// 운행 화면이 알려 주는 얼굴 위치 — 카메라 칸이 얼굴을 따라가게
  final ValueListenable<Rect?>? faceBox;

  /// 앱을 껐다 켰을 때 쉬는 중이었다면 true — 경고 음성 대신 바로 휴식 화면을 이어 연다 (남은 시간은 서버가 알려 줌)
  final bool resumeRest;

  /// 앞 경고 화면을 바꿔 띄울 때 알람 · 음성을 이만큼 늦게 시작 (앞 화면이 닫히며 소리를 멈추므로, 11/16)
  final int startDelayMs;

  /// 같은 단계에서 또 졸았을 때 true — 알람 · 고정 문구 · 음성 보고를 다시 내지 않고 퀴즈만 (기획안 6-6)
  final bool silent;

  /// 운행 화면이 미리 받아 둔 위치 — 2단계 때 가까운 졸음쉼터를 음성으로 알려 주는 데 씀 (없으면 안내 생략)
  final double? lat;
  final double? lng;

  const WarningScreen(
      {super.key,
      required this.response,
      this.liveStage,
      this.pauseDetect,
      this.camera,
      this.faceLost,
      this.serverCancelled,
      this.checking,
      this.faceBox,
      this.silent = false,
      this.resumeRest = false,
      this.startDelayMs = 0,
      this.lat,
      this.lng});

  @override
  State<WarningScreen> createState() => _WarningScreenState();
}

class _WarningScreenState extends State<WarningScreen> {
  // 졸음 판정 쉬기(pauseDetect)를 지금 누가 쥐고 있는지 — 경고 화면을 바로 바꿔 띄우면 새 화면이 먼저 켜고 앞 화면이 나중에 닫히므로,
  //   앞 화면이 닫히면서 판정을 다시 켜 버리지 않게 마지막으로 켠 화면만 끈다 (11/16)
  static int _pauseOwner = 0;
  static int _seq = 0;
  final int _id = ++_seq;
  late int _stage; // 지금 화면의 단계 (정차 후 돌려받은 단계로 바뀜)
  Timer? _repeat; // 3단계 30초 반복 음성
  String _restMessage = ''; // 휴식 뒤 서버가 준 안내 (예: 주의 단계로 다시 출발합니다). 있으면 이전 단계의 요약 · 안내 · 음성 보고 대신 보여 준다
  bool _voiceDone = false; // 알람 · 음성 · 퀴즈가 다 끝났는지 (버튼은 그 뒤에 켜짐 — 2단계는 퀴즈 필수, 11/18)
  bool _flowStopped = false; // [정차했어요] 를 눌러 음성 · 퀴즈 순서를 그만둠 (휴식 화면 위로 퀴즈가 뜨지 않게)
  bool _keepSpeaking = false; // 닫혀도 말을 끊지 않음 (운행 재개 안내를 끝까지 듣게)
  Future<String?>? _nearRest; // 2 · 3단계 — 가까운 졸음쉼터 안내 문장 (알람이 울리는 동안 미리 찾아 둠, 못 찾으면 null)
  String? _restLine; // (11/17) 찾은 쉼터 문장 — 2단계 화면에 한 줄로

  // (11/15 팀장) 3단계 [깨어 있어요] — 10초 안에 누르는지. 결과는 눌러도 · 안 눌러도 서버(관리자 웹)로
  static const int _wakeSec = 10;
  bool _wakeStarted = false;
  bool _wakePressed = false;
  bool _wakeTimedOut = false;
  int _wakeLeft = _wakeSec;
  DateTime? _wakeStartAt;
  Timer? _wakeTick;

  // 운행 중 2 · 3단계 경고는 뒤로 가기로 끌 수 없다 (2단계는 쉬어야, 3단계는 관리자만 해제). 사진 1장 테스트는 나갈 수 있음
  // (11/18 사용자 요청) 2 · 3단계 경고 화면에도 뒤로 가기(<) 버튼을 다시 — 운행 화면으로 돌아갈 수 있게
  //   (예전엔 반복 음성 · [정차했어요] 가 끊기지 않게 막아 두었음, 11/04)
  bool get _locked => _stage >= 3 && widget.liveStage != null; // (11/19) 3단계는 관리자 해제 전까지 못 나감

  @override
  void initState() {
    super.initState();
    _stage = widget.response.stage;
    if (_stage >= 2 && !widget.silent) _findNearRest(); // 알람 · 고정 문구가 나오는 동안 미리 찾기
    widget.liveStage?.addListener(_onLiveStage);
    _pauseOwner = _id;
    widget.pauseDetect?.value = true; // 알람 · 음성 · 퀴즈가 끝날 때까지 졸음 판정 쉬기
    if (widget.resumeRest) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _goRest(); // 앱을 껐다 켠 뒤 — 쉬던 중이니 알람 없이 바로 휴식 화면
      });
    } else if (widget.startDelayMs > 0) {
      Future.delayed(Duration(milliseconds: widget.startDelayMs), () {
        if (mounted) _speakWarning();
      });
    } else {
      _speakWarning();
    }
  }

  @override
  void dispose() {
    widget.liveStage?.removeListener(_onLiveStage);
    if (_pauseOwner == _id) widget.pauseDetect?.value = false; // 혹시 쉬는 중에 닫혀도 판정은 다시 켠다 (다음 경고 화면이 쥐고 있으면 그대로)
    if (!_keepSpeaking) VoiceService.stop(); // 말하기 멈춤
    _repeat?.cancel(); // 3단계 반복 멈춤
    _repeat = null;
    _wakeTick?.cancel();
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
    if (s == 3 && !_wakeStarted) {
      _stage3Flow(); // (11/15) 3단계로 올라오면 [깨어 있어요] 확인
    } else if (s == 3 && _voiceDone && !_wakePressed) {
      _startRepeat();
    }
  }

  // 3단계 30초 반복 시작 (이미 돌고 있으면 그대로) — 알람 + 고정 문구 (기획안 8-7)
  void _startRepeat() {
    _repeat ??= Timer.periodic(const Duration(seconds: 30), (_) async {
      await VoiceService.alarm();
      if (!mounted || _repeat == null) return;
      await VoiceService.speak('$_voiceName, 지금 바로 정차하세요.'); // (11/17 팀장) 이름 + 할 일만 ('관리자에게 알렸어요' 는 화면에)
    });
  }

  // 🔔 알람 → 고정 문구(1·2단계) → 기사 음성 보고 → (3단계) 30초마다 반복
  //   silent 면 알람 · 문구 · 음성 보고를 건너뛰고 퀴즈부터 (같은 단계에서 또 졸았을 때)
  //   [정차했어요] 를 누르면 _flowStopped → 뒤 순서를 하지 않는다
  Future<void> _speakWarning() async {
    if (_stage == 3 && widget.liveStage != null && !widget.silent) {
      _stage3Flow(); // (11/15) 3단계: 알림음 + 한 문장 + [깨어 있어요] 10초 (퀴즈 · 음성 보고 · 쉼터 읽기 없음)
      return;
    }
    if (!widget.silent) {
      await VoiceService.alarm(); // 시작음
      if (!mounted || _flowStopped) return;
      // (11/16 팀장) 음성은 Agent 한 문장 하나만 — "○○ 기사님, 10분 새 2번 졸았어요. 가까운 쉼터에서 쉬어 가세요." (약 4초)
      //   고정 문구 + 음성 보고를 둘 다 읽던 것을 바꿈 (너무 길었음). 서버 문장이 없으면 고정 문구 (stage_texts.dart)
      final agentVoice = widget.response.driverVoice;
      await VoiceService.speak(agentVoice.isNotEmpty ? agentVoice : StageTexts.voice(_stage));
      if (!mounted || _flowStopped) return;
      // (11/17 팀장) 쉼터는 자동으로 읽지 않음 (음성이 너무 길었음) — 화면에 이름 · 거리를 띄우고, [가까운 졸음쉼터 안내] 를 누르면 읽어 줌
      if (_stage >= 2) _findNearRest();
    } else {
      // 화면이 만들어지는 중에는 퀴즈 화면을 띄울 수 없어서 잠깐 기다린다
      await Future.delayed(const Duration(milliseconds: 300));
      if (!mounted || _flowStopped) return;
    }
    // 운전 중 음성 퀴즈 (D님 QuizScreen) — 서버가 2단계에 들어갈 때마다 보냄 (11/18 2분 간격 뺌)
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
    // 퀴즈 2번 실패로 3단계가 됐으면 [깨어 있어요] 확인으로 (11/15)
    if (_stage == 3 && widget.liveStage != null) {
      if (!_wakeStarted) _stage3Flow();
      return;
    }
    // 알람 · 음성 · 퀴즈가 다 끝났으니 이제부터 졸음 판정 (퀴즈가 없었으면 음성 보고가 끝난 뒤부터)
    widget.pauseDetect?.value = false;
    setState(() => _voiceDone = true);
    // 3단계 30초 반복은 퀴즈가 끝난 뒤에 시작
    if (_stage == 3) _startRepeat();
  }

  // (11/15 팀장) 3단계: 알림음 → 한 문장 → 누를 때까지 알림음 반복 (10초). 결과는 관리자 웹으로
  Future<void> _stage3Flow() async {
    if (_wakeStarted) return;
    setState(() {
      _wakeStarted = true;
      _wakeLeft = _wakeSec;
    });
    _wakeStartAt = DateTime.now();
    _wakeTick = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted || _wakePressed) return t.cancel();
      setState(() => _wakeLeft--);
      if (_wakeLeft <= 0) {
        t.cancel();
        _onWakeTimeout();
      }
    });
    await VoiceService.alarm();
    if (!mounted || _wakePressed) return;
    // (11/16) Agent 한 문장("○○ 기사님, 10분 새 3번 졸았어요. 지금 바로 정차하세요.") + 버튼 안내
    final agentVoice = widget.response.driverVoice;
    await VoiceService.speak(agentVoice.isNotEmpty ? '$agentVoice 깨어 계시면 버튼을 눌러 주세요.' : '$_voiceName, 지금 바로 정차하세요. 깨어 계시면 버튼을 눌러 주세요.');
    while (mounted && !_wakePressed && !_wakeTimedOut) {
      await VoiceService.alarm(); // 누를 때까지 강하게 반복
      await Future.delayed(const Duration(milliseconds: 600));
    }
  }

  // 10초 동안 안 누름 → 관리자 웹 '응답 없음' (3단계 긴급은 이미 가 있음). 30초 반복은 계속
  void _onWakeTimeout() {
    if (_wakePressed) return;
    setState(() {
      _wakeTimedOut = true;
      _voiceDone = true;
    });
    ApiService.sendWake(false, null).ignore();
    widget.pauseDetect?.value = false;
    _startRepeat();
  }

  // [깨어 있어요] — 늦게 눌러도 보냄 (관리자 웹이 '응답 없음' → '깨어 있음 (N초)' 로 바뀜). 반복음은 멈춤
  Future<void> _onWakePressed() async {
    if (_wakePressed) return;
    final start = _wakeStartAt ?? DateTime.now();
    final sec = DateTime.now().difference(start).inMilliseconds / 1000.0;
    _wakeTick?.cancel();
    _repeat?.cancel();
    _repeat = null;
    setState(() {
      _wakePressed = true;
      _voiceDone = true;
    });
    ApiService.sendWake(true, double.parse(sec.toStringAsFixed(1))).ignore();
    widget.pauseDetect?.value = false;
    await VoiceService.stop();
    if (!mounted) return;
    VoiceService.speak('확인했어요. 관리자가 확인하면 정상 화면으로 돌아가요.'); // (11/17 팀장) 버튼 글씨와 같은 말
  }

  // 2 · 3단계 — 가장 빨리 갈 수 있는 졸음쉼터 1곳 문장 미리 찾기 (알람이 울리는 동안)
  void _findNearRest() {
    if (_nearRest != null) return;
    _nearRest = nearRestVoice(widget.lat, widget.lng);
    _nearRest!.then((v) {
      if (mounted && v != null) setState(() => _restLine = v); // 2단계 화면에 쉼터 한 줄 (11/17)
    });
  }

  // [가까운 졸음쉼터 듣기] — 다시 읽어 주고 B 의 지도 화면 (목록 · [길찾기] · 다른 쉼터). 도착하면 [정차했어요]
  void _listenRest() {
    _findNearRest();
    listenRestMap(context, _nearRest!);
  }

  // 단계별 큰 글씨 — 운행 화면 · 홈 화면 · 음성과 같은 문구 (stage_texts.dart, 11/11)
  // (11/16 팀장) 말풍선 = 음성과 같은 Agent 문장 (이름만 빼고 문장마다 줄바꿈)
  //   "김기사님, 10분 새 2번 졸았어요. 가까운 쉼터에서 쉬어 가세요." → "10분 새 2번 졸았어요.(줄바꿈)가까운 쉼터에서 쉬어 가세요."
  //   서버 문장이 없거나, 화면을 연 뒤 단계가 바뀌었으면(관리자 해제 등) 고정 문구 (stage_texts.dart)
  // (11/17 팀장) 음성에서 부르는 이름 — 서버 문장 앞의 'OOO님' 을 그대로 씀 (없으면 '기사님')
  String get _voiceName =>
      RegExp(r'^([^,.]{1,20}님),').firstMatch(widget.response.driverVoice.trim())?.group(1) ?? '기사님';

  String get _headline {
    final v = widget.response.driverVoice.trim();
    // (11/17 팀장) 3단계는 고정 문구 '관리자에게 알렸어요 / 지금 바로 정차하세요' (관리자 알림은 음성 대신 화면으로)
    if (v.isEmpty || _stage != widget.response.stage || _stage < 2 || _stage >= 3) return StageTexts.headline(_stage);
    return v
        .replaceFirst(RegExp(r'^[^,.]{1,20}님,\s*'), '')
        .replaceAll(RegExp(r'\.\s+'), '.\n')
        .replaceFirst(RegExp(r'\.$'), ''); // (11/17) 끝 마침표 빼기 — 운행 화면 고정 문구와 똑같이 보이게
  }

  // 단계별 부엉이 (0 초록 · 1 노랑 · 2 주황 · 3 빨강, 11/09 그림: 장수연님)
  //   큰 그림 = 몸 전체 (카메라가 없을 때), 작은 배지 = 얼굴

  // 맨 위 그림 — 운행 중이면 카메라 화면(내 얼굴) + 오른쪽 아래 부엉이 배지, 카메라가 없으면 큰 부엉이
  Widget _topVisual(Color bg, Color fg) {
    final bigIcon = Center(child: Buddy(stage: _stage, size: 180)); // (11/19) 단계 캐릭터
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
            // (11/18 피드백) 진한 단계 색 테두리는 뺌 — 운행 화면과 같은 둥근 네모만
            ClipRRect(
              borderRadius: BorderRadius.circular(26),
              child: FollowFacePreview(controller: c, face: widget.faceBox),
            ),
            // (11/11 초안) 카메라 위 부엉이 배지는 뺌 — 아래 말풍선 부엉이와 두 마리가 겹치지 않게
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

  // (11/15 팀장) 단계별 제목 — 기사님이 느끼는 상태로 (11/19 화면 위 제목은 뺌 · 되돌릴 때 참고)
  // ignore: unused_element
  String get _title => switch (_stage) {
        2 => '쉬어 가세요',
        3 => '지금 멈추세요',
        _ => '$_stage단계 경고',
      };

  @override
  Widget build(BuildContext context) {
    final r = widget.response;
    // (11/16 R안) 바탕 = 지금 단계의 연한 색 (부엉이가 잘 보이게), 글자는 검정
    final bg = AppColors.stagePastel(_stage);
    const fg = AppColors.textPrimary;
    final stageChanged = _stage != r.stage; // 휴식 뒤 단계가 바뀌었으면 처음 경고의 글은 숨긴다
    final driving = widget.liveStage != null;

    return PopScope(
      canPop: !_locked,
      child: Scaffold(
        backgroundColor: bg,
        bottomNavigationBar: widget.serverCancelled == null
            ? null
            : ServerCancelText(cancelled: widget.serverCancelled!, color: AppColors.textSecondary),
        appBar: AppBar(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          toolbarHeight: 48,
          automaticallyImplyLeading: !_locked,
          // (11/19 사용자 요청) '운행 중' 은 맨 위 '<' 와 같은 줄 가운데
          centerTitle: true,
          title: const Text('운행 중', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        body: SafeArea(
          top: false,
          // (11/15 팀장) 운행 화면과 같은 틀 — 카메라 크기 · 위치 고정, 아래 버튼 자리 고정
          // (11/16 R안) 위에 '● 단계' + 큰 제목, 부엉이 말풍선 대신 큰 글
          child: StageLayout(
            // (11/19 사용자 요청) 위 제목('쉬어 가세요')은 빼고 작은 '● 운행 중' 만 — 단계 · 운전 시간은 아래 카드에
            camRatio: 0.5, // (11/19) 운행 화면과 같은 카메라 크기
            actionsHeight: 176,
            cameraOverlay: (widget.faceLost == null && widget.checking == null)
                ? null
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    if (widget.faceLost != null) CameraBanner(faceLost: widget.faceLost!),
                    if (widget.checking != null) CheckingBanner(checking: widget.checking!),
                  ]),
            camera: _topVisual(bg, fg),
            // 글은 부엉이 말풍선 하나만 — 요약 · 음성 보고 글 · '지켜보고 있어요' 는 뺌 (음성으로 들려줌)
            message: [
              StageMessage(_headline, stage: _stage, info: true),
              // (11/17 팀장) 2단계: 가까운 쉼터 한 줄 (음성으로 자동으로 읽지 않는 대신)
              if (_stage == 2 && _restLine != null) ...[
                const SizedBox(height: 8),
                Text('📍 $_restLine',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: fg)),
              ],
              if (stageChanged && _restMessage.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(_restMessage.replaceAll('.', ''),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fg)),
              ],
            ],
            // 버튼 — 아래 자리 고정. 그 단계에서 할 일만
            actions: [
              // 3단계: 아주 큰 [깨어 있어요] + 남은 시간
              if (_stage >= 3 && driving) ...[
                SizedBox(
                  height: 168,
                  child: ElevatedButton(
                    onPressed: _wakePressed ? null : _onWakePressed,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.card,
                      foregroundColor: const Color(0xFFD62B2B),
                      disabledBackgroundColor: Colors.white.withValues(alpha: 0.85),
                      disabledForegroundColor: const Color(0xFF2E7D4F),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_wakePressed ? '확인했어요' : '깨어 있어요',
                            style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w900)),
                        // (11/17 팀장) 누른 뒤에는 '확인했어요' 만 (안내는 음성으로)
                        if (!_wakePressed) ...[
                          const SizedBox(height: 6),
                          Text(
                              _wakeTimedOut ? '관리자가 곧 연락드려요 · 깨어 있으면 눌러 주세요' : '$_wakeLeft초 안에 눌러 주세요',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
              // 2단계: 쉼터 안내 + 정차했어요 — 둘 다 퀴즈가 끝난 뒤 켜짐 (11/18 팀장: 퀴즈는 필수, 규정 보기는 뺌 → 휴식 화면)
              if (_stage == 2) ...[
                // (11/16 R안) [가까운 졸음쉼터 안내] 흰 버튼 + [정차했어요] 남색 꽉 찬 버튼
                // (11/19 사용자 요청) 두 버튼 아이콘 시작선을 맞춤 — 같은 폭 칸 안에 [아이콘 · 글] 을 왼쪽부터
                FilledButton(
                  onPressed: _voiceDone ? _listenRest : null,
                  style: stageButton('white', height: 60),
                  child: const _IconLabel(icon: Icons.location_on_rounded, text: '가까운 졸음쉼터 안내'), // 쉼터 = 위치 마커
                ),
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: _voiceDone
                      ? () async {
                          if (await confirmRest(context) && mounted) _goRest();
                        }
                      : null,
                  style: stageButton('navy'), // 이 단계에서 가장 중요한 행동
                  child: const _IconLabel(icon: Icons.local_parking_rounded, text: '정차했어요'), // (11/19) 애플 'P' 주차 표시
                ),
              ],
              // (11/18 팀 결정) 1 · 3단계 [규정 듣기] 뺌 — 경고 화면은 깨우기 · 멈추기만. 규정은 휴식 화면 · 경고 기록 상세 · 규정 도우미에서
            ],
          ),
        ),
      ),
    );
  }
}

/// (11/19) 버튼 안 [아이콘 · 글] — 폭 210 칸 안에서 왼쪽부터 → 위아래 버튼의 아이콘 시작선이 같음
class _IconLabel extends StatelessWidget {
  final IconData icon;
  final String text;
  const _IconLabel({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 210,
        child: Row(children: [
          Icon(icon, size: 24),
          const SizedBox(width: 12),
          Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.fade, softWrap: false)),
        ]),
      );
}
