// ═══════════════════════════════════════════════════════════════
// screens/calibration_screen.dart — 개인 기준 측정 (출발 전 정면 5초)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P1
// 수업 원본: road_hazard_app/lib/screens/upload_screen.dart (사진 전송 참고, 🔴 신규)
//
// [이 파일이 하는 일]
//   - '정면을 보고 눈을 편하게 뜨세요' 🔊
//   - 1초에 1장씩 takePicture 5장
//   -   → eye_monitor.calibrate (앱 기준)  +  api_service.sendCalibration (서버 EAR 기준)
//   - 실패하면 기본값으로 운행 시작 → drive_screen
//
// [주의]
//   - 영상 스트림 대신 사진을 찍어 쓰므로 변환 코드가 필요 없음
//   - 찍은 사진은 계산이 끝나면 폰에서도 지운다 (얼굴 사진이라 남기지 않는다. 서버도 계산 뒤 지움)
//
// [쓰는 법 — 약속 (D 가 정함. 받는 쪽이 여기에 맞춘다)]
//   - final threshold = await Navigator.push<double>(context, MaterialPageRoute(builder: (_) => const CalibrationScreen()));
//   - threshold 가 double 이면: 그 값이 이 기사의 '눈 감김 기준' (0.2 ~ 0.4). 측정에 실패하거나 [기본 기준으로 시작] 을 눌러도
//     기본값(AppConfig.eyeClosedProb)을 돌려주므로 받는 쪽은 항상 값을 받는다 → eyeMonitor.threshold = threshold; 한 줄로 적용
//   - null 이면: 측정을 시작하기 전에 뒤로 가기로 나온 것 (= 운행을 시작하지 않는다)
//   - 측정 중에는 뒤로 가기를 막는다 (5초면 끝남)
//   - 서버 기준(EAR)은 이 화면이 서버로 직접 보낸다 — 받는 쪽이 따로 할 일 없음
//
// [연결됨]
//   - 팀장의 VoiceService.speak()  (11/02 — 안내가 소리로 나온다)
//
// [연결 대기]
//   - 홈의 [운행 시작] → 이 화면 → 운행 화면 (C 의 DriveScreen 이 생기면 home_screen 에서 이어 붙인다)
//   - 생성자의 capture · calibrateApp · sendServer · speak · photoCount · interval · finishDelay 는
//     테스트 · 미리보기에서 바꿔 끼우는 입구다 (비우면 전면 카메라 · EyeMonitor · ApiService)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/api_service.dart';
import '../services/eye_monitor.dart';
import '../services/voice_service.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';
import '../widgets/stage_layout.dart';
import '../widgets/buddy.dart';
import 'warning_screen.dart' show ServerCancelText, noCancel;
import '../widgets/owl_says.dart' show keepWords;

class CalibrationScreen extends StatefulWidget {
  /// 사진 1장 찍고 파일 경로를 돌려준다. 비우면 전면 카메라로 찍는다 (이때만 카메라를 열고 미리보기를 보여 준다).
  final Future<String> Function()? capture;

  /// 사진 경로들 → 앱 기준(눈 감김 기준). 비우면 A 의 EyeMonitor.calibrate.
  final Future<double> Function(List<String> paths)? calibrateApp;

  /// 사진 1장을 서버로 보낸다 (서버가 5장을 모아 서버 기준 EAR 을 계산). 비우면 C 의 ApiService.sendCalibration.
  final Future<void> Function(String path)? sendServer;

  /// 안내 문구 읽기 (TTS)
  final Future<void> Function(String text)? speak;

  /// 찍을 사진 수 (기본 5장 = AppConfig.calibSec 초 동안 1초에 1장. 서버도 5장을 기다린다)
  final int photoCount;

  /// 사진 사이 간격 (기본 1초)
  final Duration interval;

  /// '측정 완료' 안내를 보여 주는 시간
  final Duration finishDelay;

  const CalibrationScreen({
    super.key,
    this.capture,
    this.calibrateApp,
    this.sendServer,
    this.speak,
    this.photoCount = AppConfig.calibSec,
    this.interval = const Duration(seconds: 1),
    this.finishDelay = const Duration(milliseconds: 1400),
  });

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

enum _Phase { preparing, cameraFailed, ready, measuring, finishing }

class _CalibrationScreenState extends State<CalibrationScreen> {
  _Phase _phase = _Phase.preparing;
  CameraController? _controller;
  int _shot = 0;
  String _error = '';
  String _result = '';
  String _note = '';
  // 출발 전 측정은 필수 (11/11 팀장) — 얼굴을 못 찾으면 한 번 더 측정을 권하고, 두 번 실패하면 기본 설정으로
  static const int _maxTries = 2;
  int _failures = 0;
  String _retryMessage = ''; // 다시 측정을 권하는 안내 (비어 있으면 처음 측정)

  bool get _usesCamera => widget.capture == null;

  static Future<void> _defaultSpeak(String text) => VoiceService.speak(text);

  static Future<double> _defaultCalibrateApp(List<String> paths) async {
    final monitor = EyeMonitor();
    try {
      return await monitor.calibrate(paths);
    } finally {
      await monitor.close();
    }
  }

  static Future<void> _defaultSendServer(String path) async {
    await ApiService.sendCalibration(await File(path).readAsBytes());
  }

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    if (!_usesCamera) {
      setState(() => _phase = _Phase.ready);
      return;
    }
    setState(() => _phase = _Phase.preparing);
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) throw CameraException('noCamera', '카메라가 없어요');
      final front = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _phase = _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = '카메라를 열 수 없어요\n카메라 권한을 확인해 주세요';
        _phase = _Phase.cameraFailed;
      });
    }
  }

  Future<String> _defaultCapture() async {
    final controller = _controller;
    if (controller == null) throw StateError('카메라가 준비되지 않았어요');
    return (await controller.takePicture()).path;
  }

  Future<void> _say(String text) async {
    try {
      await (widget.speak ?? _defaultSpeak)(text);
    } catch (_) {}
  }

  // 측정에 실패하거나 건너뛰어도 받는 쪽이 항상 값을 받도록 기본값을 돌려준다
  void _useDefault() => Navigator.of(context).pop<double>(AppConfig.eyeClosedProb);

  Future<void> _measure() async {
    if (_phase != _Phase.ready) return;
    setState(() {
      _phase = _Phase.measuring;
      _shot = 0;
    });
    _say('정면을 보고 눈을 편하게 뜨세요');

    final paths = <String>[];
    try {
      for (var i = 0; i < widget.photoCount; i++) {
        if (i > 0) await Future<void>.delayed(widget.interval);
        if (!mounted) return;
        paths.add(await (widget.capture ?? _defaultCapture)());
        if (!mounted) return;
        setState(() => _shot = i + 1);
      }
    } catch (_) {
      // 찍은 데까지만 쓴다 (한 장도 없으면 아래에서 기본값)
    }

    final app = _measureApp(paths);
    final server = _measureServer(paths);
    final threshold = await app;
    final serverOk = await server;
    _deleteFiles(paths); // 얼굴 사진은 계산이 끝나면 지운다
    if (!mounted) return;

    // 얼굴을 못 찾음 → 아직 기회가 있으면 같은 화면으로 돌아가 다시 측정을 권한다 (기본 설정으로 바로 가지 않음, 11/11)
    if (threshold == null && _failures + 1 < _maxTries) {
      _failures++;
      const msg = '얼굴이 잘 보이지 않았어요\n정면을 바라보고 다시 시도해 주세요';
      setState(() {
        _retryMessage = msg;
        _phase = _Phase.ready;
      });
      _say(msg.replaceAll('\n', ' '));
      return;
    }

    final value = threshold ?? AppConfig.eyeClosedProb;
    _value = value;
    setState(() {
      _result = threshold == null ? '얼굴을 확인하지 못해 기본 설정으로 시작해요' : '준비됐어요\n안전 운전하세요'; // 숫자 · 서버 용어는 기사에게 안 보임 (11/11)
      _note = serverOk ? '' : '연결이 불안정해 기본 설정으로 시작해요';
      _phase = _Phase.finishing;
    });
    // (11/23 사용자 요청) 바로 운행으로 넘어가지 않음 — 아래 [운행 시작] 을 눌러야 운행 시작
  }

  double? _value; // (11/23) 측정 결과 — [운행 시작] 때 돌려줌

  // 앱 기준: 실패하면 null (→ 기본값)
  Future<double?> _measureApp(List<String> paths) async {
    if (paths.isEmpty) return null;
    try {
      return await (widget.calibrateApp ?? _defaultCalibrateApp)(paths);
    } catch (_) {
      return null;
    }
  }

  // 서버 기준: 사진을 1장씩 순서대로 보낸다. 하나라도 실패하면 false (서버는 기본값을 쓰므로 운행은 계속 된다)
  Future<bool> _measureServer(List<String> paths) async {
    if (paths.isEmpty) return false;
    try {
      for (final path in paths) {
        await (widget.sendServer ?? _defaultSendServer)(path);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  // 사진 몇 장을 지우는 정도라 동기 방식으로 충분하다 (기다릴 일이 없어서 흐름이 단순해진다)
  void _deleteFiles(List<String> paths) {
    for (final path in paths) {
      try {
        final file = File(path);
        if (file.existsSync()) file.deleteSync();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeave = _phase == _Phase.preparing || _phase == _Phase.cameraFailed || _phase == _Phase.ready;
    return PopScope(
      canPop: canLeave, // 측정 중에는 뒤로 가기로 나갈 수 없다
      child: Scaffold(
        // (11/18 피드백) 카메라가 보이는 단계는 운행 화면과 똑같은 틀(StageLayout) — 제목 · 카메라 칸 · 글 · 버튼 자리가 같음
        // (11/23 사용자 요청) '< 눈 기준 측정' — 제목은 예전 큰 글의 5/6 크기
        appBar: AppBar(
          toolbarHeight: 68, // (11/23 사용자 요청) 규정 도우미 탭 제목과 같은 높이 · 자리
          automaticallyImplyLeading: false, // (11/23 사용자 요청) 제목을 아래 칸과 같은 시작선에 (뒤로는 휴대폰 뒤로 가기)
          titleSpacing: 16, // (11/23 사용자 요청) 탭 제목들과 같은 자리 · 같은 글꼴
          centerTitle: false,
          title: Text('눈 기준 측정', style: AppType.title1.copyWith(color: AppColors.textPrimary)),
        ),
        bottomNavigationBar: ServerCancelText(cancelled: noCancel), // (11/23) 운행 · 경고 화면과 같은 아래 자리
        body: SafeArea(
          top: false,
          child: _cameraPhase
              ? StageLayout(
                  // (11/23 사용자 요청) 카메라 크기 · 위치 = 운행 · 경고 화면과 똑같이 (위 칸 60 · 간격 12 · 카메라 0.5 · 아래 버튼 칸 76)
                  header: _CalStrip(shot: _shot, total: widget.photoCount, done: _phase == _Phase.finishing),
                  headerInset: 0,
                  gap: 12,
                  camRatio: 0.5,
                  actionsHeight: 76,
                  camera: _Preview(controller: _controller, fill: true),
                  // (11/18 팀장) 거치대 안내가 안 보였음 → 카메라 위쪽에 겹쳐서 늘 보이게 (측정 전)
                  cameraOverlay: const Center(child: _MountTip()), // (11/23 사용자 요청) 측정 끝난 뒤에도 같은 안내
                  message: _message(),
                  actions: _actions(),
                )
              : Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: _content()),
                  ),
                ),
        ),
      ),
    );
  }

  bool get _cameraPhase => _phase == _Phase.ready || _phase == _Phase.measuring || _phase == _Phase.finishing;

  // 카메라 아래 글 (운행 화면의 큰 글 자리)
  // (11/18 피드백) 글 시작점 = 카메라 안쪽(둥근 모서리만큼 들어간 곳) = 거치대 알약 글자 시작점 → 왼쪽 12 띄움
  // ignore: unused_field
  static const double _inset = 0; // 틀(StageLayout)이 이미 12 들여씀

  // (11/19 사용자 요청 · Headspace) 카메라 아래 그라데이션 카드 — 작은 '운행 전 준비' · 큰 안내 · (측정 중) 진행 막대
  // (11/23 사용자 요청 · 애플 느낌) 흰 카드 가운데 — 캐릭터 먼저 · 그다음 글 / (측정 중) 아래 진행 막대
  Widget _calCard(String title, {Color? color, Widget? extra}) => Container(
        constraints: const BoxConstraints(minHeight: 150), // (11/23 사용자 요청) 잘 보이게 크게
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppleGray.separator),
          boxShadow: AppShadow.card,
        ),
        child: Column(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Buddy(stage: 0, size: 50, breathe: false),
            const SizedBox(width: 14),
            Flexible(
              child: Text(keepWords(title),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 23, height: 1.35, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: color ?? AppColors.textPrimary)),
            ),
          ]),
          if (extra != null) ...[const SizedBox(height: 14), extra],
        ]),
      );

  List<Widget> _message() {
    switch (_phase) {
      case _Phase.ready:
        return [
          _retryMessage.isNotEmpty
              ? _calCard(_retryMessage, color: AppColors.stageInk(2))
              : _calCard('화면을 정면으로 바라봐 주세요'),
        ];
      case _Phase.measuring:
        return [
          _calCard('그대로 정면을 바라봐 주세요'), // (11/23 사용자 요청) 측정 전과 같은 카드 (진행은 위 단계 칸에)
        ];
      default:
        return [
          _calCard('눈 기준 측정이 끝났어요'), // (11/23 사용자 요청) 아래 안내 글 뺌
        ];
    }
  }

  // 아래 버튼 자리 (운행 화면과 같은 곳)
  List<Widget> _actions() => _phase == _Phase.ready
      ? [AuthButton(text: _failures > 0 ? '다시 측정' : '측정 시작', onPressed: _measure, height: AppSize.button)]
      : _phase == _Phase.finishing
          ? [
              AuthButton(
                text: '운행 시작',
                height: AppSize.button,
                leading: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
                onPressed: () => Navigator.of(context).pop<double>(_value ?? AppConfig.eyeClosedProb),
              ),
            ]
          : const [];

  List<Widget> _content() {
    switch (_phase) {
      case _Phase.preparing:
        return const [
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Text('카메라를 준비하는 중이에요', textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        ];
      case _Phase.cameraFailed:
        return [
          const Icon(Icons.no_photography_outlined, size: 48, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(_error, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          FilledButton(onPressed: _prepare, child: const Text('다시 시도')),
          const SizedBox(height: 8),
          TextButton(onPressed: _useDefault, child: const Text('기본 기준으로 시작')),
        ];
      case _Phase.ready:
        return [
          // (11/18 피드백) '거치대에 고정' 이 중요 — 카메라 위에 눈에 띄는 연한 남색 알약으로
          const _MountTip(),
          const SizedBox(height: 14),
          _Preview(controller: _controller),
          const SizedBox(height: 20),
          if (_retryMessage.isNotEmpty) ...[
            Text(_retryMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.rest, height: 1.4)),
            const SizedBox(height: 12),
          ] else ...[
            // 처음 측정 때만 안내 — 다시 측정할 때는 위 '얼굴이 잘 보이지 않았어요' 문구만 (11/12 팀장)
            const Text('화면을 정면으로 바라봐 주세요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),

          ],
          const SizedBox(height: 24),
          AuthButton(text: _failures > 0 ? '다시 측정' : '측정 시작', onPressed: _measure), // (11/18) 다른 화면과 같은 알약 버튼
          // [기본 기준으로 시작] 은 두지 않는다 — 출발 전 측정은 필수 (반쯤 감은 눈 확인의 기준이 됨, 11/11 팀장)
        ];
      case _Phase.measuring:
        return [
          _Preview(controller: _controller),
          const SizedBox(height: 20),
          const Text('그대로 정면을 바라봐 주세요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: widget.photoCount == 0 ? 0 : _shot / widget.photoCount, minHeight: 10, color: AppColors.primary, backgroundColor: AppColors.cardBorder),
          ),
          const SizedBox(height: 8),
          Text('$_shot / ${widget.photoCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textMuted)),
        ];
      case _Phase.finishing:
        return [
          const Icon(Icons.check_circle_outline, size: 56, color: AppColors.normal),
          const SizedBox(height: 12),
          const Text('눈 기준 측정이 끝났어요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text(_result, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          if (_note.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(_note, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
        ];
    }
  }
}

/// 카메라 미리보기(동그랗게). 카메라를 안 쓰는 경우(테스트 · 미리보기)는 자리표시 아이콘.
class _Preview extends StatelessWidget {
  static const double _size = 240;
  final CameraController? controller;
  final bool fill; // true = 운행 화면처럼 주어진 칸을 꽉 채움 (StageLayout 의 카메라 자리)
  const _Preview({required this.controller, this.fill = false});

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final Widget inner;
    if (ctrl != null && ctrl.value.isInitialized && ctrl.value.previewSize != null) {
      final size = ctrl.value.previewSize!; // 가로 모드 기준이라 세로 화면에서는 가로 · 세로를 바꿔서 쓴다
      inner = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(width: size.height, height: size.width, child: CameraPreview(ctrl)),
      );
    } else {
      inner = const ColoredBox(color: AppColors.cardBorder, child: Icon(Icons.face_retouching_natural, size: 96, color: AppColors.textMuted));
    }
    // (11/18 피드백) 운행 화면처럼 둥근 네모 카메라 칸 (동그라미 대신) · 얇은 남색 테두리
    if (fill) {
      // (11/18 피드백 · 애플 스타일) 굵은 테두리 없이 둥근 네모만 (운행 화면 정상 상태와 같음)
      return ClipRRect(borderRadius: BorderRadius.circular(AppRadius.card), child: SizedBox.expand(child: inner));
    }
    return Center(
      child: Container(
        width: _size,
        height: _size * 1.15,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: ClipRRect(borderRadius: BorderRadius.circular(13), child: inner),
      ),
    );
  }
}

/// 맨 위 — 운행 화면의 StageHeader 와 같은 자리 · 같은 크기 ('● 운행 전 준비' + 큰 제목)
class _CalHeader extends StatelessWidget {
  const _CalHeader();

  @override
  Widget build(BuildContext context) => Padding(
      padding: EdgeInsets.zero, // 틀(StageLayout)이 카메라 안쪽으로 들여씀
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.normal, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          const Text('운행 전 준비', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        const Text('눈 기준 측정',
            style: TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppleGray.softLabel)),
      ]));
}

/// '휴대폰을 거치대에 고정한 뒤 시작해 주세요' — 연한 남색 알약 + 작은 휴대폰 아이콘 (눈에 띄지만 화면을 해치지 않게)
class _MountTip extends StatelessWidget {
  const _MountTip();

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft, // (11/18) 카메라 왼쪽 끝과 같은 시작점
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 9, 16, 9),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(999)), // 카메라 위에서도 잘 읽히게
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.phone_iphone_rounded, size: 18, color: AppColors.navy),
            SizedBox(width: 6),
            Text('휴대폰을 거치대에 고정한 뒤 시작해 주세요',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.navy)),
          ]),
        ),
      );
}

/// (11/23 사용자 요청) 측정 화면 위 칸 — 운행 화면 상태 줄과 같은 자리 · 같은 크기
///   왼쪽 '● 운행 전 준비' / 오른쪽 사진 5장 촬영 단계 (찍을 때마다 남색으로 채워짐 · 끝나면 초록 체크)
class _CalStrip extends StatelessWidget {
  final int shot;
  final int total;
  final bool done;
  const _CalStrip({required this.shot, required this.total, required this.done});

  @override
  Widget build(BuildContext context) => Container(
        height: AppSize.button,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppleGray.separator),
        ),
        child: Row(children: [
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.normal, shape: BoxShape.circle)),
          const SizedBox(width: 7),
          const Text('운행 전 준비', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const Spacer(),
          for (var i = 0; i < total; i++) ...[
            if (i > 0)
              Container(width: 10, height: 2, color: (done || i < shot) ? AppColors.navy : AppleGray.separator),
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: done ? AppColors.normal : (i < shot ? AppColors.navy : Colors.white),
                border: Border.all(color: done ? AppColors.normal : (i < shot ? AppColors.navy : AppleGray.separator), width: 1.5),
              ),
              child: done
                  ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
                  : Text('${i + 1}',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i < shot ? Colors.white : AppColors.textMuted)),
            ),
          ],
        ]),
      );
}
