// ═══════════════════════════════════════════════════════════════
// tools/eye_live_main.dart — 실시간 눈 판정 시험 화면 (앱과 따로 실행)
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0 (eye_monitor 실제 카메라 확인)
// 수업 원본: (없음, 🔴 신규) — 앱 화면이 아니라 A 시험용. 로그인 · 서버 없이 폰 안에서만 돈다
//
// [실행]  (sleep_detector_app 폴더, 시연 폰 USB 연결)
//   flutter run -t lib/tools/eye_live_main.dart
//
// [하는 일]
//   - 전면 카메라 영상 (drive_screen 과 같은 조건: ResolutionPreset.medium · nv21) → eye_monitor.processFrame
//   - 화면: 눈 뜸 확률 · PERCLOS · 고개 각도 / 평소 각도 / 숙임 · 처리 ms · fps
//   - 신호 기록: 미세수면 · PERCLOS 의심 (감김 초 · 확률 · 사진 크기) · 카메라 확인
//   - 마지막 의심 사진 (서버로 갈 jpg) → 얼굴이 바로 서 있는지 (회전) 확인
//   - [다음 단계] 버튼 → 로그에 '== N. 동작 시작 ==' + 0.5초마다 상태 한 줄 (PC: adb logcat -s flutter -v raw)
//
// [시험 순서]
//   1. 정면 10초 (평소 각도 · 처리 속도 확인)   2. 눈 2초 감기 → 미세수면
//   3. 고개 4초 숙이기 (눈 뜬 채) → 3초에 미세수면    4. 고개를 화면 밖으로 4초 떨구기 → 미세수면 (사진 없음 가능)
//   5. 얼굴을 가리고 4초 → 카메라 확인          6. 계기판 · 내비 보듯 1~2초씩 내려보기 → 신호 없어야 함
//   7. 30초 동안 자주 깜빡이기 / 반쯤 감기 → PERCLOS
//
// [주의]
//   - 얼굴 영상 · 사진은 저장하지 않는다 (화면에만)
//   - 기준값(config.dart)은 이 도구로 바꾸지 않는다
// ═══════════════════════════════════════════════════════════════
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../config.dart';
import '../services/eye_monitor.dart';

void main() => runApp(const MaterialApp(home: EyeLiveScreen(), debugShowCheckedModeBanner: false));

class EyeLiveScreen extends StatefulWidget {
  const EyeLiveScreen({super.key});

  @override
  State<EyeLiveScreen> createState() => _EyeLiveScreenState();
}

class _EyeLiveScreenState extends State<EyeLiveScreen> {
  late final EyeMonitor _eye;
  CameraController? _cam;
  String _error = '';

  double? _prob;
  double _perclos = 0;
  final _log = <String>[];
  Uint8List? _lastJpg;
  DateTime _start = DateTime.now();

  @override
  void initState() {
    super.initState();
    _eye = EyeMonitor(onSuspect: _onSuspect, onCheckCamera: _onCheckCamera, onFrameResult: _onFrame);
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await c.initialize();
      await c.startImageStream((img) => _eye.processFrame(img, front));
      if (!mounted) return;
      setState(() {
        _cam = c;
        _start = DateTime.now();
      });
      _add('시작 · 카메라 ${c.value.previewSize?.width.toInt()}×${c.value.previewSize?.height.toInt()} · 센서 ${front.sensorOrientation}°');
    } catch (e) {
      setState(() => _error = '카메라 열기 실패: $e');
    }
  }

  @override
  void dispose() {
    _cam?.stopImageStream().catchError((_) {});
    _cam?.dispose();
    _eye.close();
    super.dispose();
  }

  String get _t => '${(DateTime.now().difference(_start).inMilliseconds / 1000).toStringAsFixed(1)}s';

  void _add(String s) {
    debugPrint('[eye_live] $_t $s');
    setState(() {
      _log.insert(0, '$_t  $s');
      if (_log.length > 30) _log.removeLast();
    });
  }

  void _onSuspect(String reason, double closedSec, double perclos, double prob, Uint8List? jpg) {
    if (!mounted) return;
    _lastJpg = jpg ?? _lastJpg;
    _add('🚨 $reason · 감김 ${closedSec.toStringAsFixed(1)}초 · PERCLOS ${(perclos * 100).toStringAsFixed(0)}% · '
        '확률 ${prob.toStringAsFixed(2)} · 숙임 ${_eye.isHeadDown ? "예" : "아니오"} · 사진 ${jpg == null ? "없음" : "${jpg.length ~/ 1024}KB"}');
  }

  void _onCheckCamera() {
    if (mounted) _add('📷 카메라를 확인하세요');
  }

  void _onFrame(double? prob, double perclos, double? ear) {
    if (!mounted) return;
    setState(() {
      _prob = prob;
      _perclos = perclos;
    });
    // 0.5초마다 상태 한 줄 (로그에만) → 단계 표시와 맞춰 어떤 동작에서 무엇이 나왔는지 봄
    final now = DateTime.now();
    if (now.difference(_lastStateLog).inMilliseconds >= 500) {
      _lastStateLog = now;
      final x = _eye.lastHeadX, base = _eye.headBase;
      debugPrint('[eye_live] $_t 상태 확률 ${prob?.toStringAsFixed(2) ?? "모름"} · PERCLOS ${(perclos * 100).toStringAsFixed(0)}% · '
          '고개 ${x?.toStringAsFixed(1) ?? "-"} · 평소 ${base?.toStringAsFixed(1) ?? "-"} · '
          '숙인 정도 ${x != null && base != null ? (base - x).toStringAsFixed(1) : "-"} · ${_eye.isHeadDown ? "숙임" : "-"} · '
          '처리 ${_eye.avgProcessMs.toStringAsFixed(0)}ms ${_eye.processedFps.toStringAsFixed(1)}fps');
    }
  }

  DateTime _lastStateLog = DateTime.now();
  int _step = 0;
  static const _steps = ['정면 10초', '눈 2초 감기', '눈 뜬 채 고개 4초 숙이기', '화면 밖으로 4초 떨구기', '얼굴 가리기 4초', '계기판 잠깐 보기', '30초 자주 깜빡이기'];

  void _nextStep() {
    if (_step >= _steps.length) return;
    _step++;
    _add('== $_step. ${_steps[_step - 1]} 시작 ==');
  }

  @override
  Widget build(BuildContext context) {
    final cam = _cam;
    final x = _eye.lastHeadX, base = _eye.headBase;
    final closed = _prob != null && _prob! < _eye.threshold;
    return Scaffold(
      appBar: AppBar(title: const Text('실시간 눈 판정 시험 (A)')),
      body: _error.isNotEmpty
          ? Center(child: Text(_error))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 220,
                  child: Row(
                    children: [
                      Expanded(child: cam == null ? const Center(child: CircularProgressIndicator()) : CameraPreview(cam)),
                      Expanded(
                        child: _lastJpg == null
                            ? const Center(child: Text('의심 사진\n(서버로 갈 jpg)', textAlign: TextAlign.center))
                            : Image.memory(_lastJpg!, gaplessPlayback: true),
                      ),
                    ],
                  ),
                ),
                Container(
                  color: _eye.isHeadDown ? Colors.orange.shade100 : (closed ? Colors.red.shade100 : Colors.green.shade50),
                  padding: const EdgeInsets.all(8),
                  child: Text(
                    '눈 뜸 확률 ${_prob?.toStringAsFixed(2) ?? "모름"} (기준 ${_eye.threshold.toStringAsFixed(2)}) · '
                    'PERCLOS ${(_perclos * 100).toStringAsFixed(0)}%\n'
                    '고개 ${x?.toStringAsFixed(1) ?? "-"}° · 평소 ${base?.toStringAsFixed(1) ?? "모으는 중"}° · '
                    '숙인 정도 ${x != null && base != null ? (base - x).toStringAsFixed(1) : "-"}° '
                    '(기준 ${AppConfig.headDownDeg.toStringAsFixed(0)}°) · ${_eye.isHeadDown ? "숙임" : "-"}\n'
                    '처리 ${_eye.lastProcessMs}ms (평균 ${_eye.avgProcessMs.toStringAsFixed(0)}) · '
                    '${_eye.processedFps.toStringAsFixed(1)} fps',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FilledButton(
                    onPressed: _step >= _steps.length ? null : _nextStep,
                    child: Text(_step >= _steps.length
                        ? '시험 끝'
                        : '다음: ${_step + 1}. ${_steps[_step]} (누르고 시작)'),
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [for (final l in _log) Text(l, style: const TextStyle(fontSize: 12))],
                  ),
                ),
              ],
            ),
    );
  }
}
