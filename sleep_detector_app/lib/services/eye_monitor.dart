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
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - processFrame(CameraImage image, CameraDescription camera)
//   - onSuspect(reason, closedSec, perclos, eyeOpenProb, CameraImage frame)  ← drive_screen 이 받는 콜백
//   - onCheckCamera()  ← drive_screen 이 받는 콜백
//   - analyzeFile(String path) → 눈 뜸 확률
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
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import '../config.dart';
import '../utils/camera_image_utils.dart';

class _FrameRecord {
  final DateTime time;
  final bool isClosed;
  _FrameRecord(this.time, this.isClosed);
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
  final void Function(double? eyeOpenProb, double perclos)? onFrameResult;

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
        enableContours: false,
        enableLandmarks: false,
        enableTracking: false,
      ),
    );
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

      final faces = await _detector.processImage(inputImage);
      final now = DateTime.now();

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
      final bool isClosed = avgProb < threshold;

      // 2. PERCLOS 30초 윈도우 갱신 ("모름" 제외)
      _history.add(_FrameRecord(now, isClosed));
      final cutoff =
      now.subtract(const Duration(seconds: AppConfig.perclosWindowSec));
      _history.removeWhere((r) => r.time.isBefore(cutoff));

      final double currentPerclos = _calculatePerclos();
      onFrameResult?.call(avgProb, currentPerclos);

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
          final jpg = CameraImageUtils.toJpg(
            _lastClosedFrame!,
            rotation: _lastCamera?.sensorOrientation ?? 270,
          );
          onSuspect?.call(
              'microsleep', currentClosedSec, currentPerclos, avgProb, jpg);
        }
      } else {
        // 눈을 다시 뜨면 미세수면 플래그 및 타이머 리셋
        _closedStartTime = null;
        _microsleepTriggered = false;
      }

      // 4. 피로 누적 (PERCLOS: 30초 중 15% 이상) 체크
      final bool hasEnoughWindow = _history.isNotEmpty &&
          now.difference(_history.first.time).inSeconds >= 10;

      if (hasEnoughWindow && currentPerclos >= AppConfig.perclosThreshold) {
        if (!_perclosTriggered && !_microsleepTriggered) {
          _perclosTriggered = true; // 기준 아래로 내려갔다 다시 넘어야 셈
          final targetFrame = _lastClosedFrame ?? image;
          final jpg = CameraImageUtils.toJpg(
            targetFrame,
            rotation: cam.sensorOrientation,
          );
          onSuspect?.call('perclos', currentClosedSec, currentPerclos,
              _lastEyeOpenProb, jpg);
        }
      } else if (currentPerclos < AppConfig.perclosThreshold) {
        _perclosTriggered = false;
      }
    } catch (e) {
      // 프레임 오류 무시
    } finally {
      _busy = false;
    }
  }

  void _handleUnknown(DateTime now) {
    _unknownStartTime ??= now;
    final unknownSec =
        now.difference(_unknownStartTime!).inMilliseconds / 1000.0;
    onFrameResult?.call(null, _calculatePerclos());

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