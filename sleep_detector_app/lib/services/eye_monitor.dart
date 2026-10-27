// ═══════════════════════════════════════════════════════════════
// services/eye_monitor.dart — ML Kit 눈 판정 (앱의 실시간 1차 판정)  ⭐ 핵심
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0 (개인 기준은 P1)
// 수업 원본: (없음, 🔴 신규) google_mlkit_face_detection 예제
//
// [이 파일이 하는 일]
//   - FaceDetector 옵션: enableClassification 켬 · performanceMode fast · minFaceSize 0.15 (윤곽 · 랜드마크 · 추적은 끔)
//   - 프레임마다: 분석 중이면 그 프레임은 버림(_busy) → 두 눈 평균 눈 뜸 확률
//   -   → 감김 / 뜸 / 모름 (확률 null · 얼굴 없음 = 모름, 감김으로 세지 않음)
//   - 연속 감김 1.5초 이상 → 미세수면 의심 (다시 떠야 다음 졸음을 셈)
//   - 최근 30초 PERCLOS 15% 이상 → 피로 누적 의심 (모름은 빼고 계산, 내려갔다 다시 넘어야 셈)
//   - 감긴 프레임을 잠깐 들고 있다가 의심이 확정되면 그 프레임을 넘김 (이미 눈을 뜬 뒤 찍지 않게)
//   - 모름이 3초 이어지면 카메라 확인 신호
//   - 사진 파일 1장 분석 (사진 1장 테스트 · KPI ① 측정) · 개인 기준 측정 (평소 확률 중간값 × 0.5, 0.2~0.4, 실패 시 0.3)
//   - 🆕 (AppConfig.contourEarOn) 눈 윤곽 점 16개로 폰 EAR 계산 — 반쯤 감은 눈은 뜸 확률이 높게 나와서 보완용
//       AppConfig.useContourEar 를 켜면 "뜸 확률 < 기준 또는 EAR < earClosed" 를 감김으로 봄 (시연 폰 확인 뒤에만)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - processFrame(CameraImage image, CameraDescription camera)
//   - onSuspect(reason, closedSec, perclos, eyeOpenProb, Uint8List? jpg)  ← drive_screen 이 받는 콜백
//       jpg = 눈 감긴 순간의 프레임을 eye_monitor 가 이미 jpg 로 바꾼 것 → drive_screen 은 그대로 sendDetect
//       (null 이면 변환 실패 — 사진 없이 보내거나 다음 의심을 기다림)
//   - onCheckCamera()  ← drive_screen 이 받는 콜백
//   - onFrameResult(eyeOpenProb, perclos, ear)  ← (선택) 0단계 화면 표시용, 모름이면 eyeOpenProb · ear = null
//   - analyzeFile(String path) → 눈 뜸 확률
//   - analyzeFileDetail(String path) → EyeReading(눈 뜸 확률 · 폰 EAR · 처리 ms) — 사진 비교 · KPI ① 측정용
//   - lastProcessMs · avgProcessMs · processedFps — 성능 시험용 (ML Kit 이 실제로 도는지 숫자로 확인)
//   - calibrate(List<String> paths) → 개인 기준
//   - currentPerclos (ping 에 실어 보낼 값) · close()
//
// [주의]
//   - 눈만 판단 — 고개 각도 · 미소 확률 · 하품은 쓰지 않는다
//   - C 의 drive_screen 과는 위 함수 이름만 약속하고 서로 파일을 고치지 않는다
//   - 실제 fps 는 폰마다 다름 → 시연 폰에서 측정, 판정은 프레임 수가 아니라 시간(초) 기준
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:math';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../config.dart';
import '../utils/camera_image_utils.dart';

class _FrameRecord {
  final DateTime time;
  final bool isClosed;
  _FrameRecord(this.time, this.isClosed);
}

/// 사진 1장 분석 결과 (analyzeFileDetail)
class EyeReading {
  final double? eyeOpenProb; // 두 눈 평균 눈 뜸 확률 (얼굴 없음 · 모름이면 null)
  final double? ear;         // 폰 EAR (윤곽 꺼짐 · 윤곽 없음이면 null)
  final int ms;              // ML Kit 처리 시간
  EyeReading(this.eyeOpenProb, this.ear, this.ms);

  @override
  String toString() => 'prob=${eyeOpenProb?.toStringAsFixed(3)} ear=${ear?.toStringAsFixed(3)} ${ms}ms';
}

class EyeMonitor {
  late final FaceDetector _detector;
  bool _busy = false;

  // 개인 맞춤 눈 감김 기준 (기본값 0.3)
  double threshold = AppConfig.eyeClosedProb;

  // 상태 추적용 변수
  DateTime? _closedStartTime;
  DateTime? _unknownStartTime;
  bool _microsleepTriggered = false;
  bool _perclosTriggered = false;
  bool _cameraWarnTriggered = false;

  // 최근 30초 PERCLOS 계산용 큐 ("모름" 제외)
  final List<_FrameRecord> _history = [];

  // 감긴 순간의 프레임 임시 보관
  CameraImage? _lastClosedFrame;
  CameraDescription? _lastCamera;
  double _lastEyeOpenProb = 1.0;

  // C의 drive_screen.dart와 약속된 콜백 인터페이스
  final void Function(
      String reason,
      double closedSec,
      double perclos,
      double eyeOpenProb,
      Uint8List? frame,
      )? onSuspect;

  final void Function()? onCheckCamera;
  final void Function(double? eyeOpenProb, double perclos, double? ear)? onFrameResult;

  // 성능 시험용 (분석한 프레임만 셈 — 분석 중이라 버린 프레임은 빠짐)
  int lastProcessMs = 0;
  double avgProcessMs = 0;
  int _processed = 0;
  DateTime? _firstProcessedAt;

  /// 1초에 실제로 분석한 프레임 수 (판정 기준 1.5초 안에 몇 장을 보는지)
  double get processedFps {
    final start = _firstProcessedAt;
    if (start == null || _processed < 2) return 0;
    final sec = DateTime.now().difference(start).inMilliseconds / 1000.0;
    return sec > 0 ? _processed / sec : 0;
  }

  EyeMonitor({
    this.onSuspect,
    this.onCheckCamera,
    this.onFrameResult,
  }) {
    _detector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true, // 눈 뜸 확률 필수
        performanceMode: FaceDetectorMode.fast,
        minFaceSize: AppConfig.minFaceSize,
        enableContours: AppConfig.contourEarOn, // 폰 EAR 용 눈 윤곽 점 (켜면 느려짐 → avgProcessMs 확인)
        enableLandmarks: false,
        enableTracking: false,
      ),
    );
  }

  /// 최근 30초 PERCLOS (drive_screen 이 30초마다 sendPing 에 실어 보냄)
  double get currentPerclos => _calculatePerclos();

  /// 한 눈의 윤곽 점 16개 → EAR. 서버 MediaPipe EAR 과 같은 원리 (세로 2곳 평균 ÷ 가로)
  ///   윤곽은 눈을 한 바퀴 도는 순서 → 눈꼬리 = 정반대(n/2 칸 떨어진) 점 쌍 중 가장 먼 쌍
  ///   눈꼬리에서 앞뒤로 k칸 = 위 · 아래 눈꺼풀 짝
  ///   (6점 EAR 의 p2·p6, p3·p5 처럼 눈 폭의 1/3 · 2/3 위치 → 16점에서는 눈꼬리에서 3칸 · 5칸)
  static double? _eyeEar(FaceContour? contour) {
    final pts = contour?.points;
    if (pts == null || pts.length < 8) return null;
    final n = pts.length;
    int c1 = 0;
    double widest = 0;
    for (int i = 0; i < n ~/ 2; i++) {
      final d = pts[i].distanceTo(pts[i + n ~/ 2]);
      if (d > widest) {
        widest = d;
        c1 = i;
      }
    }
    if (widest < AppConfig.minEyeWidthPx) return null; // 너무 작은 눈은 픽셀 오차가 커서 못 믿음
    final k1 = (n * 3) ~/ 16, k2 = (n * 5) ~/ 16;
    Point<int> p(int i) => pts[i % n];
    final v1 = p(c1 + k1).distanceTo(p(c1 - k1 + n));
    final v2 = p(c1 + k2).distanceTo(p(c1 - k2 + n));
    return (v1 + v2) / (2 * widest);
  }

  /// 두 눈 평균 폰 EAR (윤곽이 없으면 null)
  static double? contourEar(Face face) {
    final l = _eyeEar(face.contours[FaceContourType.leftEye]);
    final r = _eyeEar(face.contours[FaceContourType.rightEye]);
    if (l == null || r == null) return null;
    return (l + r) / 2.0;
  }

  void _recordTime(int ms, DateTime now) {
    lastProcessMs = ms;
    _processed++;
    _firstProcessedAt ??= now;
    avgProcessMs += (ms - avgProcessMs) / _processed;
  }

  /// 실시간 카메라 프레임 분석 (분석 중이면 프레임 버림)
  Future<void> processFrame(CameraImage image, [CameraDescription? camera]) async {
    if (_busy) return;
    _busy = true;

    try {
      final cam = camera ??
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 270,
          );

      final inputImage = CameraImageUtils.toInputImage(image, cam);
      if (inputImage == null) return;

      final watch = Stopwatch()..start();
      final faces = await _detector.processImage(inputImage);
      final now = DateTime.now();
      _recordTime(watch.elapsedMilliseconds, now);

      // 1. 얼굴 없음 또는 눈 확률 null -> "모름" 처리
      if (faces.isEmpty) {
        _handleUnknown(now);
        return;
      }

      final face = faces.first;
      final leftProb = face.leftEyeOpenProbability;
      final rightProb = face.rightEyeOpenProbability;

      if (leftProb == null || rightProb == null) {
        _handleUnknown(now);
        return;
      }

      // 정상 인식 시 "모름" 타이머 초기화
      _unknownStartTime = null;
      _cameraWarnTriggered = false;

      final double avgProb = (leftProb + rightProb) / 2.0;
      final double? ear = AppConfig.contourEarOn ? contourEar(face) : null;
      // 완전히 감음 = 뜸 확률, (useContourEar 켜면) 반쯤 감음 = 폰 EAR
      final bool isClosed = avgProb < threshold ||
          (AppConfig.useContourEar && ear != null && ear < AppConfig.earClosed);

      // 2. PERCLOS 30초 윈도우 갱신 ("모름" 제외)
      _history.add(_FrameRecord(now, isClosed));
      final cutoff =
      now.subtract(const Duration(seconds: AppConfig.perclosWindowSec));
      _history.removeWhere((r) => r.time.isBefore(cutoff));

      final double perclos = _calculatePerclos();
      onFrameResult?.call(avgProb, perclos, ear);

      // 3. 연속 감김 (미세수면: 1.5초 이상) 체크
      double currentClosedSec = 0.0;
      if (isClosed) {
        _closedStartTime ??= now;
        currentClosedSec =
            now.difference(_closedStartTime!).inMilliseconds / 1000.0;

        // 감긴 순간의 프레임 보관
        _lastClosedFrame = image;
        _lastCamera = cam;
        _lastEyeOpenProb = avgProb;

        if (currentClosedSec >= AppConfig.closedSec && !_microsleepTriggered) {
          _microsleepTriggered = true; // 눈을 다시 떠야 다음 미세수면을 셈
          // 같은 감김이 눈 뜬 직후 PERCLOS 로 한 번 더 잡히지 않게 — PERCLOS 도 기준 아래로 내려갔다 다시 넘어야 셈
          _perclosTriggered = true;
          final jpg = CameraImageUtils.toJpg(
            _lastClosedFrame!,
            rotation: _lastCamera?.sensorOrientation ?? 270,
          );
          onSuspect?.call(
              'microsleep', currentClosedSec, perclos, avgProb, jpg);
        }
      } else {
        // 눈을 다시 뜨면 미세수면 플래그 및 타이머 리셋
        _closedStartTime = null;
        _microsleepTriggered = false;
      }

      // 4. 피로 누적 (PERCLOS: 30초 중 15% 이상) 체크
      final bool hasEnoughWindow = _history.isNotEmpty &&
          now.difference(_history.first.time).inSeconds >= 10;

      if (hasEnoughWindow && perclos >= AppConfig.perclosThreshold) {
        if (!_perclosTriggered && !_microsleepTriggered) {
          _perclosTriggered = true; // 기준 아래로 내려갔다 다시 넘어야 셈
          final targetFrame = _lastClosedFrame ?? image;
          final jpg = CameraImageUtils.toJpg(
            targetFrame,
            rotation: cam.sensorOrientation,
          );
          onSuspect?.call('perclos', currentClosedSec, perclos,
              _lastEyeOpenProb, jpg);
        }
      } else if (perclos < AppConfig.perclosThreshold) {
        _perclosTriggered = false;
      }
    } catch (e) {
      // 프레임 하나가 실패해도 다음 프레임은 계속 분석 (원인은 디버그 콘솔에만)
      debugPrint('[eye_monitor] 프레임 분석 실패: $e');
    } finally {
      _busy = false;
    }
  }

  void _handleUnknown(DateTime now) {
    _unknownStartTime ??= now;
    final unknownSec =
        now.difference(_unknownStartTime!).inMilliseconds / 1000.0;
    onFrameResult?.call(null, _calculatePerclos(), null);

    if (unknownSec >= AppConfig.unknownSec && !_cameraWarnTriggered) {
      _cameraWarnTriggered = true;
      onCheckCamera?.call(); // "카메라를 확인하세요"
    }
  }

  double _calculatePerclos() {
    if (_history.isEmpty) return 0.0;
    final closedCount = _history.where((r) => r.isClosed).length;
    return closedCount / _history.length;
  }

  /// 사진 파일 1장의 눈 뜸 확률 반환 (upload_screen.dart 및 KPI ① 측정용)
  Future<double?> analyzeFile(String path) async {
    try {
      final inputImage = InputImage.fromFilePath(path);
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) return null;

      final face = faces.first;
      final left = face.leftEyeOpenProbability;
      final right = face.rightEyeOpenProbability;
      if (left == null || right == null) return null;

      return (left + right) / 2.0;
    } catch (e) {
      return null;
    }
  }

  /// 사진 파일 1장 → 눈 뜸 확률 + 폰 EAR + 처리 시간 (서버 MediaPipe EAR 과 같은 사진으로 비교할 때)
  Future<EyeReading> analyzeFileDetail(String path) async {
    final watch = Stopwatch()..start();
    try {
      final faces = await _detector.processImage(InputImage.fromFilePath(path));
      final ms = watch.elapsedMilliseconds;
      if (faces.isEmpty) return EyeReading(null, null, ms);
      final face = faces.first;
      final l = face.leftEyeOpenProbability, r = face.rightEyeOpenProbability;
      final prob = (l == null || r == null) ? null : (l + r) / 2.0;
      return EyeReading(prob, AppConfig.contourEarOn ? contourEar(face) : null, ms);
    } catch (e) {
      debugPrint('[eye_monitor] 사진 분석 실패: $e');
      return EyeReading(null, null, watch.elapsedMilliseconds);
    }
  }

  /// 출발 시 정면 사진 5장으로 개인 기준 설정 (중간값 * 0.5, 0.2~0.4 제한)
  Future<double> calibrate(List<String> paths) async {
    final List<double> probs = [];
    for (final path in paths) {
      final prob = await analyzeFile(path);
      if (prob != null) probs.add(prob);
    }

    if (probs.isEmpty) {
      threshold = AppConfig.eyeClosedProb; // 실패 시 기본값 0.3
      return threshold;
    }

    probs.sort();
    final int mid = probs.length ~/ 2;
    final double median =
    probs.length.isOdd ? probs[mid] : (probs[mid - 1] + probs[mid]) / 2.0;

    threshold = (median * AppConfig.calibRatio)
        .clamp(AppConfig.calibMin, AppConfig.calibMax);
    return threshold;
  }

  Future<void> close() async {
    await _detector.close();
  }
}