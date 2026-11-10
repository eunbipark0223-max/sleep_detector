// ═══════════════════════════════════════════════════════════════
// tools/eye_live_main.dart — 실시간 눈 판정 시험 화면 (앱과 따로 실행)
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0 (eye_monitor 실제 카메라 확인)
// 수업 원본: (없음, 🔴 신규) — 앱 화면이 아니라 A 시험용. 로그인 · 서버 없이 폰 안에서만 돈다
//
// [실행]  (sleep_detector_app 폴더, 시연 폰 USB 연결)
//   flutter run -t lib/tools/eye_live_main.dart
//   카메라 크기 바꾸기: --dart-define=CAM_PRESET=max  (기본 medium = 지금 drive_screen, 11/09 C 브랜치는 max)
//
// [하는 일]
//   - 전면 카메라 영상 (drive_screen 과 같은 조건: ResolutionPreset.medium · nv21, CAM_PRESET 로 바꿈) → eye_monitor.processFrame
//   - 화면: 눈 뜸 확률 · PERCLOS · 고개 각도 / 평소 각도 / 숙임 · 처리 ms · fps
//   - 신호 기록: 미세수면 · PERCLOS 의심 (감김 초 · 확률 · 사진 크기) · 카메라 확인
//   - 마지막 의심 사진 (서버로 갈 jpg) → 얼굴이 바로 서 있는지 (회전) 확인
//   - 0.5초마다 상태 한 줄 (PC: adb logcat -s flutter -v raw)
//   - 프레임마다 [eye_frame] 한 줄 · 동작 버튼 [eye_mark] → tools/eye_replay.py 로 1.5초 · 15% 를 바꿔 경고 횟수 계산
//   - 🆕 (11/09 팀장 측정 요청) 사람 버튼 (a · b · c · d · t) · 상태 버튼 (① 정면 뜸 ② 실눈 ③ 감음 ④ 시선만 아래 ⑤ 숙이고 뜸 · 0 쉼)
//       → [eye_frame] 에 고개 각도 · 평소 각도 · 사람 · 상태가 같이 남음 → python tools/eye_replay.py states <기록>
//       경고는 [eye_alarm] 한 줄 (원인 eye · head · head_resend · perclos · 사진 장수 · JPG 변환 ms)
//       🆕 (11/10) 반쯤 확인 사진은 [eye_half] 한 줄 (시각 ms · 바이트 · 변환 ms · 사람 · 상태) — 서버로는 안 보냄
//
// [측정 순서 (11/09 팀장 요청 1번)]  사람마다 기록 파일 하나 — adb logcat -s flutter -v raw > D:\kpi_raw\phone_log\states_<사람>_<날짜>.txt
//   0. 사람 버튼 고르기 → '0 쉼' 으로 정면 60초 이상 (평소 고개 각도 모으기, 표에서 뺌)
//   1. ① 정면 보고 눈 뜸 10초 → ② 실눈 10초 → ③ 완전히 감음 10초 → ④ 고개 그대로 시선만 아래 10초 → ⑤ 고개 숙이고 눈 뜸 10초
//      상태 사이에는 '0 쉼' 을 눌러 자세를 바꾸고 (바꾸는 동안 프레임은 표에서 빠짐), 자세가 잡히면 다음 상태 버튼
//   2. (측정 2) '0 쉼' 그대로 운전 자세 5분 — 아래 보기 · 고개 돌리기는 동작 버튼 (계기판 · 고개 돌림) 으로 표시
//   PC: python tools/eye_replay.py states <기록 파일>  → 상태별 확률 중간값 · 0.4 / 0.5 미만 비율 · 경고 원인 · fps
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

  // 측정 표시 (11/09) — 사람 · 상태 (0 = 쉼 · 준비, 표에서 뺌)
  static const _people = ['a', 'b', 'c', 'd', 't'];
  static const _states = ['0 쉼', '① 뜸', '② 실눈', '③ 감음', '④ 시선↓', '⑤ 숙임'];
  String _person = 'a';
  int _state = 0;
  static const _preset = String.fromEnvironment('CAM_PRESET', defaultValue: 'medium');

  @override
  void initState() {
    super.initState();
    _eye = EyeMonitor(onSuspect: _onSuspect, onCheckCamera: _onCheckCamera, onFrameResult: _onFrame, onHalfCheck: _onHalfCheck);
    _openCamera();
  }

  Future<void> _openCamera() async {
    try {
      final cams = await availableCameras();
      final front = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cams.first);
      final c = CameraController(front, ResolutionPreset.values.byName(_preset),
          enableAudio: false, imageFormatGroup: ImageFormatGroup.nv21);
      await c.initialize();
      await c.startImageStream((img) => _eye.processFrame(img, front));
      if (!mounted) return;
      setState(() {
        _cam = c;
        _start = DateTime.now();
      });
      _add('시작 · 카메라 $_preset ${c.value.previewSize?.width.toInt()}×${c.value.previewSize?.height.toInt()} · 센서 ${front.sensorOrientation}°');
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
    final jpgs = _eye.lastSuspectJpgs, cause = _eye.lastSuspectCause;
    final sizes = jpgs.map((j) => '${j.length ~/ 1024}KB').join('·');
    final gaps = [for (final t in _eye.lastSuspectTimes) (_eye.lastSuspectTimes.last.difference(t).inMilliseconds / 1000).toStringAsFixed(2)].join('·');
    // 원인별 집계용 한 줄: 시각 ms, reason, 원인, 사진 장수, JPG 변환 ms, 사람, 상태
    debugPrint('[eye_alarm] ${DateTime.now().difference(_start).inMilliseconds},$reason,$cause,${jpgs.length},${_eye.lastJpgMs},$_person,$_state');
    _add('🚨 $reason ($cause) · 감김 ${closedSec.toStringAsFixed(1)}초 · PERCLOS ${(perclos * 100).toStringAsFixed(0)}% · '
        '확률 ${prob.toStringAsFixed(2)} · 숙임 ${_eye.isHeadDown ? "예" : "아니오"} · '
        '사진 ${jpgs.isEmpty ? "없음" : "${jpgs.length}장 $sizes (마지막 장보다 $gaps초 전) · 변환 ${_eye.lastJpgMs}ms"}');
  }

  // 🆕 (11/10) 반쯤 확인 사진 — 시험 앱은 서버로 안 보내고 보낸 시각 · 크기 · 변환 ms 만 남김 (판정은 본 앱 + 서버 [half] 줄)
  void _onHalfCheck(Uint8List jpg) {
    debugPrint('[eye_half] ${DateTime.now().difference(_start).inMilliseconds},${jpg.length},${_eye.lastHalfJpgMs},$_person,$_state');
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
    // 프레임마다 한 줄 (tools/eye_replay.py 가 기준값을 바꿔 다시 계산): 시각 ms, 눈 뜸 확률 (모름은 빈칸), 숙임 0/1, 웃음 확률,
    //   (11/09) 고개 각도 · 평소 각도 (없으면 빈칸) · 사람 · 상태 — 얼굴을 놓친 프레임은 고개 각도가 이전 값이라 빈칸
    final hx = prob == null ? null : _eye.lastHeadX, hb = _eye.headBase;
    debugPrint('[eye_frame] ${DateTime.now().difference(_start).inMilliseconds},${prob?.toStringAsFixed(3) ?? ""},${_eye.isHeadDown ? 1 : 0},'
        '${_eye.lastSmileProb?.toStringAsFixed(3) ?? ""},${hx?.toStringAsFixed(1) ?? ""},${hb?.toStringAsFixed(1) ?? ""},$_person,$_state');
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

  // 거치 시험 중 지금 하는 동작 표시 → 경고가 어떤 동작에서 났는지 맞춰 봄
  static const _marks = ['계기판', '고개 돌림', '하품', '기타'];

  void _mark(String label) {
    debugPrint('[eye_mark] ${DateTime.now().difference(_start).inMilliseconds},$label');
    _add('✏️ $label');
  }

  // 사람 · 상태 바꾸기 → [eye_state] 한 줄 + 다음 프레임부터 [eye_frame] 에 실림
  void _setMeasure(String person, int state) {
    setState(() {
      _person = person;
      _state = state;
    });
    debugPrint('[eye_state] ${DateTime.now().difference(_start).inMilliseconds},$person,$state');
    _add('== 사람 $person · ${_states[state]} ==');
  }

  Widget _chips(List<String> labels, int selected, void Function(int) onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          children: [
            for (int i = 0; i < labels.length; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: i == selected
                      ? FilledButton(
                          style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => onTap(i),
                          child: Text(labels[i], style: const TextStyle(fontSize: 12)))
                      : OutlinedButton(
                          style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                          onPressed: () => onTap(i),
                          child: Text(labels[i], style: const TextStyle(fontSize: 12))),
                ),
              ),
          ],
        ),
      );

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
                _chips([for (final p in _people) p], _people.indexOf(_person), (i) => _setMeasure(_people[i], _state)),
                _chips(_states, _state, (i) => _setMeasure(_person, i)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      for (final m in _marks)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2),
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => _mark(m),
                              child: Text(m, style: const TextStyle(fontSize: 12)),
                            ),
                          ),
                        ),
                    ],
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
