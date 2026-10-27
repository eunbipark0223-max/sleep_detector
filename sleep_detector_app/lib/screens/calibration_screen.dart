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
// [연결 대기 — 'TODO(연결)' 로 찾을 수 있다]
//   - C 의 voice_service.speak()  (지금 voice_service.dart 는 주석뿐 — 안내가 소리로 나오지 않는다)
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
import '../theme.dart';

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

  bool get _usesCamera => widget.capture == null;

  // TODO(연결): C 의 voice_service 가 생기면 `VoiceService.speak` 로 바꾼다 (지금은 소리 없이 넘어간다)
  static Future<void> _defaultSpeak(String text) async {}

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
        _error = '카메라를 열 수 없어요. 카메라 권한을 확인해 주세요';
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

    final value = threshold ?? AppConfig.eyeClosedProb;
    setState(() {
      _result = threshold == null ? '얼굴을 확인하지 못해 기본 기준으로 시작해요' : '내 눈 기준을 맞췄어요 (${value.toStringAsFixed(2)})';
      _note = serverOk ? '' : '서버 기준은 기본값을 써요';
      _phase = _Phase.finishing;
    });
    await Future<void>.delayed(widget.finishDelay);
    if (!mounted) return;
    Navigator.of(context).pop<double>(value);
  }

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
        appBar: AppBar(title: const Text('내 눈 기준 맞추기'), automaticallyImplyLeading: canLeave),
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: _content()),
            ),
          ),
        ),
      ),
    );
  }

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
          _Preview(controller: _controller),
          const SizedBox(height: 20),
          const Text('정면을 보고 눈을 편하게 뜨세요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text('${widget.photoCount}장을 1초에 1장씩 찍어서 내 눈 기준을 맞춰요.\n폰을 거치대에 고정하고 눌러 주세요.',
              textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
          const SizedBox(height: 24),
          FilledButton(onPressed: _measure, child: const Text('측정 시작')),
          const SizedBox(height: 8),
          TextButton(onPressed: _useDefault, child: const Text('기본 기준으로 시작')),
        ];
      case _Phase.measuring:
        return [
          _Preview(controller: _controller),
          const SizedBox(height: 20),
          const Text('정면을 보고 눈을 편하게 뜨세요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
          const Text('측정이 끝났어요', textAlign: TextAlign.center, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
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
  const _Preview({required this.controller});

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
    return Center(
      child: Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: AppColors.primary, width: 4)),
        child: ClipOval(child: inner),
      ),
    );
  }
}
