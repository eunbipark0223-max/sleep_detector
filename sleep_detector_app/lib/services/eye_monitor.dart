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
//   - 최근 30초 PERCLOS 15% 이상 → 피로 누적 의심 (모름은 빼고 계산, 내려갔다 다시 넘어야 셈, 직전 의심 뒤 30초 안에는 안 냄)
//   - 감긴 프레임을 잠깐 들고 있다가 의심이 확정되면 그 프레임을 넘김 (이미 눈을 뜬 뒤 찍지 않게)
//   - 모름이 3초 이어지면 카메라 확인 신호
//   - 🆕 (AppConfig.headRuleOn) 고개 숙임이 3초 이어지면 → 미세수면 의심 (reason 그대로 microsleep)
//       평소 각도 = 최근 60초 '눈 뜨고 숙이지 않은' 프레임의 ML Kit headEulerAngleX 중간값, 그보다 6° 이상 숙이면 숙임
//       숙인 채 얼굴을 놓치면 (화면 밖으로 떨굼) 모름이 아니라 숙임으로 계속 셈 — 얼굴이 다시 잡힐 때까지
//       PERCLOS 는 눈 감김만 (고개만 숙인 프레임은 넣지 않음)
//       서버가 취소한 뒤 얼굴이 정상으로 돌아오지 않은 채 6초가 되면 사진 없이 한 번 더 → 서버가 앱 판단대로 확정 (11/04)
//       10/29 시연 폰 시험: 계기판 보기 1.0~2.3초 · 졸아서 숙이기 3.8~7.4초 → 1.5초였을 때 계기판에서 경고 3번 → 3초
//   - 🆕 (AppConfig.smileOpenProb) 웃음 확률이 기준 이상이면 감김으로 세지 않음 ('뜸' 으로 셈, '모름' 아님 → PERCLOS 에도 뜸)
//       크게 웃으면 볼이 올라가 눈이 가늘어져 감김으로 오판 (11/03 웹캠 확인). 졸면서 크게 웃는 경우는 거의 없음
//       (11/09) 웃는 프레임은 고개 숙임 · 평소 각도에도 넣지 않음 — 정면에서 웃을 때 숙임 3초로 잡힘 (11/05 시연 폰, 팀장 요청)
//   - 🆕 (11/09, AppConfig.microsleepPhotos) 눈 감김 미세수면은 감는 동안의 처음 · 가운데 · 마지막 3장을 넘김 (lastSuspectJpgs)
//       고개 숙임 · PERCLOS 는 1장 그대로, 재전송은 사진 없음
//   - 🆕 (11/10, AppConfig.graceAfterWarningSec) 경고 화면에서 돌아온 뒤 (reset) 눈을 한 번이라도 뜬 프레임이 나오면
//       그때부터 10초는 미세수면 · 고개 숙임 의심을 안 냄 (팀장: 경고 뒤 눈 비비기로 단계가 바로 오름)
//       한 번도 안 뜨고 계속 감고 있으면 봐주지 않음 (1.5초 뒤 바로 의심) · PERCLOS 는 30초 창을 다시 채우니 그대로
//       10초 안에 시작된 감김 · 숙임은 계속 셈 → 10초가 끝날 때 아직 감고 · 숙이고 있으면 그때 의심
//   - 🆕 (11/10, AppConfig.eyeResendOn) 눈 감김 의심을 서버가 취소했는데 계속 감고 있으면 → 고개 숙임처럼 사진 없이 한 번 더 (eye_resend)
//   - 🆕 (11/10, AppConfig.halfCheckOn, 기본 꺼짐) 반쯤 감은 눈 확인: 눈을 뜬 상태 (감김 · 숙임 · 웃음 아님) 면 10초마다 사진 1장 → onHalfCheck
//       ML Kit 은 반쯤 감은 눈을 뜸으로 봐서 판정은 서버 EAR (출발 전 뜬 눈 대비) 이 함 — face_service.check_half · sleep_state.add_half
//   - 사진 파일 1장 분석 (사진 1장 테스트 · KPI ① 측정) · 개인 기준 측정 (평소 확률 중간값 × 0.5, 0.2~0.4, 실패 시 기본값 + 예외)
//   - 🆕 (AppConfig.contourEarOn) 눈 윤곽 점 16개로 폰 EAR 계산 — 반쯤 감은 눈은 뜸 확률이 높게 나와서 보완용
//       AppConfig.useContourEar 를 켜면 "뜸 확률 < 기준 또는 EAR < earClosed" 를 감김으로 봄 (시연 폰 확인 뒤에만)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - processFrame(CameraImage image, CameraDescription camera)
//   - onSuspect(reason, closedSec, perclos, eyeOpenProb, Uint8List? jpg)  ← drive_screen 이 받는 콜백
//       jpg = 눈 감긴 순간의 프레임을 eye_monitor 가 이미 jpg 로 바꾼 것 → drive_screen 은 그대로 sendDetect
//       (null 이면 변환 실패 — 사진 없이 보내거나 다음 의심을 기다림)
//   - 🆕 lastSuspectJpgs (List<Uint8List>, 찍은 순서, 없으면 빈 목록) · lastSuspectTimes — onSuspect 를 부르기 직전에 채움
//       onSuspect 의 jpg = 이 목록의 마지막 장 (지금까지와 같은 사진) → 여러 장을 보낼 쪽은 onSuspect 안에서 _eye.lastSuspectJpgs 를 읽음
//       lastSuspectCause = eye(눈 감김) · head(고개 숙임) · head_resend · eye_resend(취소 뒤 재전송) · perclos — reason 은 지금처럼 microsleep · perclos 두 가지
//       lastJpgMs = 그 사진들 JPG 변환에 걸린 시간 합 (화면 쪽에서 돌아서 경고가 그만큼 늦어짐 — 시험 앱이 기록)
//   - onCheckCamera()  ← drive_screen 이 받는 콜백
//   - 🆕 onHalfCheck(Uint8List jpg)  ← (선택, 11/10) 반쯤 확인 사진 1장. drive_screen 은 sendDetect(jpg, reason: 'half') 로 보내고
//       서버가 피로 확정 (isSleep) 일 때만 경고 · 아니면 아무것도 안 띄움 (취소 글자 · serverCancelled 도 부르지 않음)
//   - reset()  ← drive_screen 이 경고 화면이 닫힐 때 부름 (판정 기록 비우기, 개인 기준은 그대로, 11/03 팀장)
//   - serverCancelled()  ← drive_screen 이 서버 취소 응답을 받으면 부름 (안 부르면 한 번 더 보내기가 동작하지 않음)
//   - onFrameResult(eyeOpenProb, perclos, ear)  ← (선택) 0단계 화면 표시용, 모름이면 eyeOpenProb · ear = null
//   - analyzeFile(String path) → 눈 뜸 확률
//   - analyzeFileDetail(String path) → EyeReading(눈 뜸 확률 · 폰 EAR · 처리 ms) — 사진 비교 · KPI ① 측정용
//   - lastFaceBox · lastImageSize — 카메라 칸 표시용 (11/05 C 요청, 판정에는 안 씀)
//   - lastProcessMs · avgProcessMs · processedFps — 성능 시험용 (ML Kit 이 실제로 도는지 숫자로 확인)
//   - calibrate(List<String> paths) → 개인 기준 (얼굴이 잡힌 사진이 3장 미만이면 StateError, 기준은 기본값으로)
//   - currentPerclos (ping 에 실어 보낼 값) · close()
//
// [주의]
//   - 눈 + 고개 숙임으로 판단 — 웃음 확률은 감김 오판을 막는 데만 쓴다 (웃음 · 하품으로 졸음을 판정하지 않음)
//       (10/28 CNN 채택 회의: 고개 숙임은 CNN 으로 해결 안 됨 → 앱 고개 규칙. 고개 좌우 각도는 쓰지 않음)
//   - C 의 drive_screen 과는 위 함수 이름만 약속하고 서로 파일을 고치지 않는다
//   - 실제 fps 는 폰마다 다름 → 시연 폰에서 측정, 판정은 프레임 수가 아니라 시간(초) 기준
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:math';
import 'dart:ui' show Rect, Size;
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

class _Shot {
  final DateTime time;
  final CameraImage image;
  _Shot(this.time, this.image);
}

class _HeadRecord {
  final DateTime time;
  final double x; // ML Kit headEulerAngleX
  _HeadRecord(this.time, this.x);
}

/// 사진 1장 분석 결과 (analyzeFileDetail)
class EyeReading {
  final double? eyeOpenProb; // 두 눈 평균 눈 뜸 확률 (얼굴 없음 · 모름이면 null)
  final double? ear;         // 폰 EAR (윤곽 꺼짐 · 윤곽 없음이면 null)
  final int ms;              // ML Kit 처리 시간
  final double? headX;       // 고개 위아래 각도 (ML Kit headEulerAngleX, 얼굴 없음이면 null) — 고개 숙임 기준 측정용
  final double? headY;       // 고개 좌우 각도 (headEulerAngleY)
  final double? smileProb;   // 웃음 확률 (smilingProbability) — 웃음 기준 측정용
  EyeReading(this.eyeOpenProb, this.ear, this.ms, [this.headX, this.headY, this.smileProb]);

  @override
  String toString() => 'prob=${eyeOpenProb?.toStringAsFixed(3)} ear=${ear?.toStringAsFixed(3)} '
      'x=${headX?.toStringAsFixed(1)} y=${headY?.toStringAsFixed(1)} ${ms}ms';
}

class EyeMonitor {
  late final FaceDetector _detector;
  bool _busy = false;

  // 눈 감김 기준 (기본값 AppConfig.eyeClosedProb, calibrate 하면 개인 기준)
  double threshold = AppConfig.eyeClosedProb;

  // 상태 추적용 변수
  DateTime? _closedStartTime;
  DateTime? _unknownStartTime;
  bool _microsleepTriggered = false;
  bool _perclosTriggered = false;
  // 마지막 미세수면 · PERCLOS 의심 시각 — 이후 30초 창에는 같은 눈 감김이 남아 있으므로 PERCLOS 를 다시 내지 않음
  DateTime? _lastSuspectAt;
  bool _cameraWarnTriggered = false;
  // 🆕 (11/10) 경고 뒤 봐주기 — reset 뒤 첫 '뜸' 프레임에서 _quietUntil = 그 시각 + graceAfterWarningSec
  bool _graceArmed = false;
  DateTime? _quietUntil;
  // 🆕 (11/10) 마지막 반쯤 확인 사진 시각 · 보낸 횟수 · JPG 변환 시간 (시험 앱 기록용)
  DateTime? _lastHalfCheckAt;
  int halfChecks = 0;
  int lastHalfJpgMs = 0;

  // 최근 30초 PERCLOS 계산용 큐 ("모름" 제외)
  final List<_FrameRecord> _history = [];
  // 지금 PERCLOS 창을 채우기 시작한 시각 — 30초가 다 차야 PERCLOS 를 판정 (출발 직후 몇 초로 '15%' 를 내지 않게)
  DateTime? _windowStart;

  // 고개 규칙: 평소 고개 각도 계산용 (눈 뜨고 숙이지 않은 프레임만) · 바로 전 프레임이 숙임이었는지
  final List<_HeadRecord> _headHistory = [];
  bool _headDown = false;
  DateTime? _headStartTime;   // 고개 숙임이 시작된 시각 (고개를 headUpResetSec 동안 들면 null)
  DateTime? _headUpSince;     // 숙임 중 고개를 든 첫 시각 (다시 숙이면 null)
  bool _headTriggered = false; // 이번 숙임으로 이미 의심을 냈는지 (고개를 들어야 다음)
  DateTime? _cancelledAt;      // 고개 숙임 · 눈 감김 의심을 서버가 취소한 시각 (얼굴이 정상으로 돌아오면 null)
  String _cancelCause = 'head'; // 취소된 의심의 원인 (head · eye) → 재전송 시간 · 이름
  bool _cancelFace = false;     // (11/11) 취소된 숙임 의심 사진에 서버가 얼굴을 찾았는지 → 재전송 headResendFaceSec
  /// 🆕 (11/11 팀장) 방금 serverCancelled 가 '고개 숙임 + 얼굴 보임 (눈 뜸으로 취소)' 이었는지
  ///   drive_screen 이 serverCancelled 바로 뒤에 보고 '고개를 들고 앞을 봐 주세요' 를 한 번 말함 (단계 변화 없음)
  bool lastCancelHeadFace = false;
  DateTime? _normalSince;      // 취소 뒤 얼굴이 정상으로 보이기 시작한 시각
  CameraImage? _headFrame;    // 이번 숙임 동안 찍은 마지막 얼굴 프레임 (서버로 갈 사진)
  DateTime? _headFrameAt;
  CameraDescription? _headCamera;

  // 시험 화면용 (tools/eye_live_main.dart) — 판정에는 안 씀
  double? lastHeadX;  // 마지막 프레임 고개 위아래 각도 (얼굴 없음이면 그대로)
  double? headBase;   // 지금 평소 각도 (아직 못 냈으면 null)
  double? lastSmileProb; // 마지막 프레임 웃음 확률 (시험 기록용)

  // 화면 표시용 (drive_screen · warning_screen 카메라 칸이 얼굴을 따라갈 때) — 판정에는 안 씀
  //   ML Kit 이 준 좌표 그대로. 전면 카메라 회전 (센서 270°) · 좌우 반전은 쓰는 쪽에서 맞춘다
  Rect? lastFaceBox;   // 마지막 프레임 얼굴 위치 (얼굴을 놓치면 null)
  Size? lastImageSize; // 마지막 프레임 사진 크기 (회전 전 카메라 프레임 크기)
  bool get isHeadDown => _headDown;

  // 감긴 순간의 프레임 임시 보관
  CameraImage? _lastClosedFrame; // PERCLOS 사진용 (최근 감긴 프레임 1장)
  DateTime? _lastClosedAt;
  // 지금 이어지는 감김 동안 찍은 프레임 (photoGapSec 간격, 미세수면 사진용) — 눈을 뜨거나 의심을 내면 비움
  final List<_Shot> _streakShots = [];
  double _lastEyeOpenProb = 1.0;

  // 🆕 (11/09) 마지막 의심 때 넘긴 사진 (머리말 참고) — drive_screen 은 onSuspect 안에서 읽음
  List<Uint8List> lastSuspectJpgs = const [];
  List<DateTime> lastSuspectTimes = const [];
  String lastSuspectCause = '';
  int lastJpgMs = 0;

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
  // 🆕 (11/10) 반쯤 감은 눈 확인 사진 (머리말 참고)
  final void Function(Uint8List jpg)? onHalfCheck;

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
    this.onHalfCheck,
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
      lastImageSize = Size(image.width.toDouble(), image.height.toDouble());

      final watch = Stopwatch()..start();
      final faces = await _detector.processImage(inputImage);
      final now = DateTime.now();
      _recordTime(watch.elapsedMilliseconds, now);

      // 1. 얼굴 없음 또는 눈 확률 null -> "모름" 처리
      //    (고개 규칙) 바로 전 프레임에서 고개를 숙이고 있었으면 → 숙여서 얼굴을 놓친 것 → 숙임으로 계속 셈
      //    (눈 상태는 모르니 PERCLOS 에는 넣지 않음)
      lastFaceBox = faces.isEmpty ? null : faces.first.boundingBox;
      if (faces.isEmpty) {
        _checkAfterCancel(now, false, null);
        if (AppConfig.headRuleOn && _headDown) {
          _keepNotUnknown();
          _checkHeadDown(now, null, cam, null);
        } else {
          _headUp(now);
          _handleUnknown(now);
        }
        return;
      }

      final face = faces.first;
      final leftProb = face.leftEyeOpenProbability;
      final rightProb = face.rightEyeOpenProbability;

      if (leftProb == null || rightProb == null) {
        _checkAfterCancel(now, false, null);
        // 이미 숙이던 중이면 → 눈 확률은 없어도 고개 각도로 숙임을 이어서 셈 (각도도 없으면 그대로)
        //   눈 확률이 없는 프레임으로 숙임을 새로 시작하지는 않음 — 손으로 얼굴을 가릴 때 각도가 틀어져
        //   숙임으로 잡히고 이어서 얼굴을 놓쳐 미세수면이 됐음 (10/29 시연 폰 시험) → 그때는 '모름' (카메라 확인)
        //   눈 상태를 모르니 평소 각도 기록에는 넣지 않음 (eyesClosed: true)
        final headX = face.headEulerAngleX;
        _headDown = AppConfig.headRuleOn && _headDown && (headX == null || _isHeadDown(headX, now, true, false));
        if (_headDown) {
          _keepNotUnknown();
          _checkHeadDown(now, image, cam, null);
        } else {
          _headUp(now);
          _handleUnknown(now);
        }
        return;
      }

      final double avgProb = (leftProb + rightProb) / 2.0;
      final double? ear = AppConfig.contourEarOn ? contourEar(face) : null;
      lastSmileProb = face.smilingProbability;
      // 크게 웃으면 볼이 올라가 눈이 가늘어짐 → 감김으로 오판 (11/03 웹캠 확인)
      //   졸면서 크게 웃는 경우는 거의 없어서, 웃는 프레임은 감김으로 세지 않음
      final bool smiling = (lastSmileProb ?? 0) >= AppConfig.smileOpenProb;
      // 완전히 감음 = 뜸 확률, (useContourEar 켜면) 반쯤 감음 = 폰 EAR
      final bool eyesClosed = !smiling &&
          (avgProb < threshold || (AppConfig.useContourEar && ear != null && ear < AppConfig.earClosed));
      _headDown = AppConfig.headRuleOn && _isHeadDown(face.headEulerAngleX, now, eyesClosed, smiling);
      // (11/10) 경고 뒤 첫 '뜸' 프레임 → 그때부터 graceAfterWarningSec 봐줌
      if (_graceArmed && !eyesClosed) {
        _graceArmed = false;
        _quietUntil = now.add(Duration(milliseconds: (AppConfig.graceAfterWarningSec * 1000).round()));
      }
      _checkAfterCancel(now, !_headDown && !eyesClosed, avgProb);

      // 눈 감김 · PERCLOS 는 눈만으로 (고개만 숙이고 눈 뜬 프레임은 '뜸')
      _judge(now, eyesClosed, image, cam, avgProb, ear);
      // 고개 숙임은 따로 — headDownSec(3초) 이어져야 의심 (계기판 · 내비를 잠깐 보는 1~2초는 넘김)
      if (_headDown) {
        _checkHeadDown(now, image, cam, avgProb);
      } else {
        _headUp(now);
      }
      _maybeHalfCheck(now, eyesClosed || _headDown || smiling, image, cam);
    } catch (e) {
      // 프레임 하나가 실패해도 다음 프레임은 계속 분석 (원인은 디버그 콘솔에만)
      debugPrint('[eye_monitor] 프레임 분석 실패: $e');
    } finally {
      _busy = false;
    }
  }

  /// 고개 숙임이 이어진 시간 → headDownSec 이상이면 미세수면 의심 (같은 숙임 동안 1번)
  ///   눈 감김 미세수면이 이미 났으면 (같은 졸음) 다시 내지 않음 · 고개 숙임 경고 뒤 눈 감김도 다시 내지 않음
  ///   frame == null : 얼굴을 놓친 프레임 → 서버로 갈 사진은 이번 숙임 동안 찍은 마지막 얼굴 (없으면 사진 없이)
  void _checkHeadDown(DateTime now, CameraImage? frame, CameraDescription cam, double? avgProb) {
    _headUpSince = null;
    if (_headStartTime == null) {
      _headStartTime = now;
      _headFrame = null;
    }
    if (frame != null) {
      _headFrame = frame;
      _headFrameAt = now;
      _headCamera = cam;
    }
    final sec = now.difference(_headStartTime!).inMilliseconds / 1000.0;
    if (sec < AppConfig.headDownSec || _headTriggered || _microsleepTriggered || _quiet(now)) return;

    _headTriggered = true;
    _lastSuspectAt = now;
    _microsleepTriggered = true; // 고개를 든 채 눈을 감고 있어도 같은 졸음 → 미세수면 다시 안 냄 (눈을 떠야 다음)
    _perclosTriggered = true;
    final target = _headFrame;
    _send('microsleep', 'head', sec, _calculatePerclos(), avgProb ?? _lastEyeOpenProb,
        [if (target != null) _Shot(_headFrameAt ?? now, target)], _headCamera?.sensorOrientation ?? 270);
  }

  /// 🆕 (11/10) 경고 뒤 봐주는 시간 안인지 (graceAfterWarningSec)
  bool _quiet(DateTime now) => _quietUntil != null && now.isBefore(_quietUntil!);

  /// 🆕 (11/10) 반쯤 감은 눈 확인 사진 — 눈을 뜬 상태 (감김 · 숙임 · 웃음 아님) 면 halfCheckSec 마다 1장 → onHalfCheck
  ///   감김이 이어지는 중 · 재의심 간격 안이면 안 보냄 (그때는 미세수면 · PERCLOS 가 맡음). 판정은 서버 EAR
  void _maybeHalfCheck(DateTime now, bool notOpen, CameraImage frame, CameraDescription cam) {
    if (!AppConfig.halfCheckOn || onHalfCheck == null) return;
    if (notOpen || _closedStartTime != null) return;
    final last = _lastHalfCheckAt;
    if (last == null) {
      _lastHalfCheckAt = now; // 출발 직후 첫 장도 halfCheckSec 뒤에
      return;
    }
    if (now.difference(last).inMilliseconds < AppConfig.halfCheckSec * 1000) return;
    _lastHalfCheckAt = now;
    final watch = Stopwatch()..start();
    final jpg = CameraImageUtils.toJpg(frame, rotation: cam.sensorOrientation);
    lastHalfJpgMs = watch.elapsedMilliseconds;
    if (jpg == null) return;
    halfChecks++;
    onHalfCheck?.call(jpg);
  }

  /// 의심 사진들을 JPG 로 바꿔 lastSuspect* 에 넣고 onSuspect 호출 (jpg 인자 = 마지막 장, 변환 실패한 장은 뺌)
  void _send(String reason, String cause, double sec, double perclos, double prob, List<_Shot> shots, int rotation) {
    final watch = Stopwatch()..start();
    final jpgs = <Uint8List>[];
    final times = <DateTime>[];
    for (final s in shots) {
      final j = CameraImageUtils.toJpg(s.image, rotation: rotation);
      if (j == null) continue;
      jpgs.add(j);
      times.add(s.time);
    }
    lastJpgMs = watch.elapsedMilliseconds;
    lastSuspectJpgs = jpgs;
    lastSuspectTimes = times;
    lastSuspectCause = cause;
    onSuspect?.call(reason, sec, perclos, prob, jpgs.isEmpty ? null : jpgs.last);
  }

  /// 감김 동안 보관한 프레임 중 시간이 고르게 퍼진 microsleepPhotos 장 (처음 · 마지막 포함, 찍은 순서)
  static List<_Shot> _spread(List<_Shot> shots) {
    final n = AppConfig.microsleepPhotos;
    if (shots.length <= n) return List.of(shots);
    if (n <= 1) return [shots.last];
    final t0 = shots.first.time.millisecondsSinceEpoch;
    final span = shots.last.time.millisecondsSinceEpoch - t0;
    final picked = <int>{};
    for (int i = 0; i < n; i++) {
      final target = t0 + span * i / (n - 1);
      int best = 0;
      for (int k = 1; k < shots.length; k++) {
        if ((shots[k].time.millisecondsSinceEpoch - target).abs() <
            (shots[best].time.millisecondsSinceEpoch - target).abs()) {
          best = k;
        }
      }
      picked.add(best);
    }
    return [for (final k in picked.toList()..sort()) shots[k]];
  }

  /// 서버가 의심을 취소했을 때 drive_screen 이 부름 — 이번 숙임에서 난 의심이면 headResendSec 에 한 번 더 보낼 수 있게
  ///   숙여서 사진에 얼굴이 안 잡히면 서버는 손으로 가린 경우처럼 취소 → 숙인 채 계속 자면 들 때까지 경고가 안 남 (11/04 시연 폰 시험)
  ///   (11/10 팀장, 11/05 빈틈) 눈 감김 의심도 취소 뒤 계속 감고 있으면 한 번 더 (eyeResendOn) — 전에는 눈을 뜨기 전까지 다시 안 보냄
  ///   (11/11 팀장) faceFound = 서버 응답 face_found. 숙임 + 얼굴 보임 → headResendFaceSec (10초), 아니면 headResendSec (6초)
  ///   faceFound 를 안 주면 (null) 얼굴 없음과 같게 6초 — 지금까지와 같음
  void serverCancelled({bool? faceFound}) {
    lastCancelHeadFace = false;
    final eyeStill = AppConfig.eyeResendOn && lastSuspectCause == 'eye' && _closedStartTime != null;
    if (!_headTriggered && !eyeStill) return;
    _cancelCause = eyeStill ? 'eye' : 'head';
    _cancelFace = !eyeStill && faceFound == true;
    lastCancelHeadFace = _cancelFace;
    _cancelledAt = DateTime.now();
    _normalSince = null;
  }

  /// 서버 취소 뒤 얼굴이 정상으로 (고개 들고 눈 뜸) 돌아오지 않은 채 시간이 지나면 사진 없이 한 번 더
  ///   숙임 각도만 보면 얼굴이 화면 밖으로 나갈 때 숙임이 풀려서 재전송이 안 됨 (11/04 시연 폰 시험)
  void _checkAfterCancel(DateTime now, bool normal, double? avgProb) {
    final at = _cancelledAt;
    if (at == null) return;
    if (normal) {
      _normalSince ??= now;
      if (now.difference(_normalSince!).inMilliseconds >= AppConfig.headUpResetSec * 1000) {
        _cancelledAt = null;
      }
      return;
    }
    _normalSince = null;
    final waited = now.difference(at).inMilliseconds / 1000.0;
    // 숙임: 3초 의심 → 취소 → 3초 더 / 눈 감김: 1.5초 의심 → 취소 → 4.5초 더 (둘 다 시작부터 약 6초 + 서버 응답 시간)
    //   (11/11) 숙임 + 얼굴 보임으로 취소 → 3초 의심 → 취소 → 7초 더 (시작부터 약 10초)
    final firstSec = _cancelCause == 'eye' ? AppConfig.closedSec : AppConfig.headDownSec;
    final resendSec = _cancelFace ? AppConfig.headResendFaceSec : AppConfig.headResendSec;
    if (waited < resendSec - firstSec) return;
    _cancelledAt = null;
    _lastSuspectAt = now;
    _send('microsleep', '${_cancelCause}_resend', firstSec + waited, _calculatePerclos(),
        avgProb ?? _lastEyeOpenProb, const [], 270);
  }

  /// 판정 기록을 처음 상태로 (경고 · 퀴즈 · 휴식 화면이 닫히고 운행 화면으로 돌아올 때, drive_screen 이 부름)
  ///   그 화면들이 떠 있는 동안에도 아래 운행 화면 카메라는 돌아서 PERCLOS 30초 창에 눈 감김이 쌓임
  ///   → 돌아오자마자 PERCLOS 의심 → 재개한 1단계가 바로 2단계 (11/03 팀장 확인). 평소 고개 각도도 쉬는 자세로 바뀌어 있어서 같이 비움
  ///   개인 기준(threshold) 은 그대로
  void reset() {
    _closedStartTime = null;
    _unknownStartTime = null;
    _microsleepTriggered = false;
    _perclosTriggered = false;
    _lastSuspectAt = null;
    _cameraWarnTriggered = false;
    // (11/10) 경고 뒤 눈을 비비기만 해도 바로 다음 의심 → 단계가 몇 초 만에 오름 (팀장)
    //   → 돌아온 뒤 첫 '뜸' 프레임부터 graceAfterWarningSec 봐줌 (계속 감고 있으면 안 봐줌)
    _graceArmed = true;
    _quietUntil = null;
    _lastHalfCheckAt = DateTime.now();
    _history.clear();
    _windowStart = null; // PERCLOS 는 다시 30초를 채운 뒤부터 판정
    _headHistory.clear();
    _headDown = false;
    _headStartTime = null;
    _headUpSince = null;
    _headTriggered = false;
    _cancelledAt = null;
    _normalSince = null;
    _headFrame = null;
    _headFrameAt = null;
    _lastClosedFrame = null;
    _lastClosedAt = null;
    _streakShots.clear();
    _lastEyeOpenProb = 1.0;
  }

  /// 숙이지 않은 프레임 — headUpResetSec 동안 계속 들고 있어야 숙임 시간을 처음부터 (한두 프레임 흔들림은 숙임이 이어짐)
  ///   10/29 시연 폰 시험: 떨구는 4초 동안 숙인 정도가 22° → 6.4° → 12° 로 흔들려 기준 6° 아래 1프레임에 타이머가 0 → 경고 안 남
  void _headUp(DateTime now) {
    if (_headStartTime == null) return;
    _headUpSince ??= now;
    if (now.difference(_headUpSince!).inMilliseconds >= AppConfig.headUpResetSec * 1000) {
      _headStartTime = null;
      _headTriggered = false;
      _headUpSince = null;
    }
  }

  /// 숙여서 얼굴을 놓친 프레임 — '모름' (카메라 확인) 으로 세지 않음
  void _keepNotUnknown() {
    _unknownStartTime = null;
    _cameraWarnTriggered = false;
    onFrameResult?.call(null, _calculatePerclos(), null);
  }

  /// 고개 숙임인지 — 평소 각도(최근 headBaseSec 동안 눈 뜨고 숙이지 않은 프레임의 중간값)보다 headDownDeg 이상 숙임
  ///   ML Kit headEulerAngleX 는 숙이면 내려감. 평소 각도를 아직 못 냈으면 (출발 직후) 숙임으로 보지 않음
  ///   웃는 프레임 (smileOpenProb 이상) 은 숙임으로 보지 않고 평소 각도에도 넣지 않음 (11/09 팀장 요청)
  ///     11/05 시연 폰: 정면에서 웃는데 숙임 3초로 잡힘 → 서버 CNN 확정. 기록 다시 계산: 눈 감고 떨구기 경고 그대로 · 웃음 많은 기록 15 → 13번
  bool _isHeadDown(double? headX, DateTime now, bool eyesClosed, bool smiling) {
    if (headX == null) return false;
    final cutoff = now.subtract(const Duration(seconds: AppConfig.headBaseSec));
    _headHistory.removeWhere((r) => r.time.isBefore(cutoff));

    double? base;
    if (_headHistory.length >= AppConfig.headBaseMinFrames) {
      final xs = _headHistory.map((r) => r.x).toList()..sort();
      base = xs[xs.length ~/ 2];
    }
    lastHeadX = headX;
    headBase = base;
    final down = !smiling && base != null && base - headX >= AppConfig.headDownDeg;
    // 숙인 프레임 · 감은 프레임 · 웃는 프레임은 평소 각도에 넣지 않음 (졸면서 숙인 각도가 평소가 되지 않게)
    //   자세를 아예 바꾸면 headBaseSec 뒤 기록이 비고 → 새 자세로 평소 각도를 다시 냄
    if (!down && !eyesClosed && !smiling) _headHistory.add(_HeadRecord(now, headX));
    return down;
  }

  /// 눈 감김 / 뜸 1프레임 판정 → PERCLOS 창 · 미세수면 · PERCLOS 의심 (고개 숙임은 _checkHeadDown 에서 따로)
  void _judge(DateTime now, bool isClosed, CameraImage? frame, CameraDescription cam,
      double? avgProb, double? ear) {
    // 감김 · 뜸이 판정되면 "모름" 타이머 초기화
    _unknownStartTime = null;
    _cameraWarnTriggered = false;

    // 2. PERCLOS 30초 윈도우 갱신 ("모름" 제외)
    final cutoff =
    now.subtract(const Duration(seconds: AppConfig.perclosWindowSec));
    _history.removeWhere((r) => r.time.isBefore(cutoff));
    // 창이 비어 있었으면 (처음 · 얼굴을 30초 넘게 놓침) 여기서부터 다시 30초를 채움
    if (_history.isEmpty) _windowStart = now;
    _history.add(_FrameRecord(now, isClosed));

    final double perclos = _calculatePerclos();
    onFrameResult?.call(avgProb, perclos, ear);

    // 3. 연속 감김 (미세수면: 1.5초 이상) 체크
    double currentClosedSec = 0.0;
    if (isClosed) {
      _closedStartTime ??= now;
      currentClosedSec =
          now.difference(_closedStartTime!).inMilliseconds / 1000.0;

      // 감긴 순간의 프레임 보관 (얼굴을 놓친 프레임은 보관하지 않음 — 서버가 볼 얼굴이 없음)
      if (frame != null) {
        _lastClosedFrame = frame;
        _lastClosedAt = now;
        // 미세수면 사진 후보: photoGapSec 간격으로만 쌓음 (첫 장은 고정, 간격 안에 들어온 프레임은 마지막 장을 새것으로 바꿈)
        //   의심을 이미 냈으면 더 쌓지 않음 → 1.5초 감김 동안 최대 약 8장 (medium 1장 약 0.5MB)
        if (!_microsleepTriggered) {
          final gapMs = (AppConfig.photoGapSec * 1000).round();
          final n = _streakShots.length;
          if (n >= 2 && now.difference(_streakShots[n - 2].time).inMilliseconds < gapMs) {
            _streakShots[n - 1] = _Shot(now, frame);
          } else {
            _streakShots.add(_Shot(now, frame));
          }
          // 경고 뒤 봐주는 시간 (graceAfterWarningSec) 때문에 감김이 1.5초보다 길어지면 마지막 closedSec + 0.5초 것만 들고 있음 (프레임 1장 약 0.5MB)
          final keepMs = ((AppConfig.closedSec + 0.5) * 1000).round();
          while (_streakShots.length > 1 && now.difference(_streakShots.first.time).inMilliseconds > keepMs) {
            _streakShots.removeAt(0);
          }
        }
      }
      if (avgProb != null) _lastEyeOpenProb = avgProb;

      if (currentClosedSec >= AppConfig.closedSec && !_microsleepTriggered && !_quiet(now)) {
        _microsleepTriggered = true; // 눈을 다시 떠야 다음 미세수면을 셈
        if (_headDown) _headTriggered = true; // 숙인 채 눈 감김으로 이미 경고 → 같은 숙임으로 다시 안 냄
        // 같은 감김이 눈 뜬 직후 PERCLOS 로 한 번 더 잡히지 않게 — PERCLOS 도 기준 아래로 내려갔다 다시 넘어야 셈
        _perclosTriggered = true;
        _lastSuspectAt = now;
        // 이번 감김 동안 찍은 프레임만 보냄 — 얼굴을 놓친 채 시작된 감김이면 몇 분 전 사진이 갈 수 있어서 (10/28 팀장 확인)
        //   (11/09) 처음 · 가운데 · 마지막 3장 → 보낸 뒤 바로 비움
        final shots = _spread(_streakShots);
        _streakShots.clear();
        _send('microsleep', 'eye', currentClosedSec, perclos, avgProb ?? _lastEyeOpenProb, shots,
            cam.sensorOrientation);
      }
    } else {
      // 눈을 다시 뜨면 미세수면 플래그 및 타이머 리셋
      //   (_lastClosedFrame 은 PERCLOS 사진용으로 남김 — PERCLOS 15% 면 최근 30초 안의 감긴 프레임이라 오래된 사진이 아님)
      _closedStartTime = null;
      _streakShots.clear();
      _microsleepTriggered = false;
    }

    // 4. 피로 누적 (PERCLOS: 30초 중 15% 이상) 체크
    //   창이 30초 다 찼을 때만 판정 — 가장 오래된 기록으로 재면 30초가 넘은 기록은 지워져서 영영 30초가 안 됨
    final bool hasEnoughWindow = _windowStart != null &&
        now.difference(_windowStart!).inSeconds >= AppConfig.perclosWindowSec;

    // 직전 의심 뒤 30초 안이면 창에 같은 눈 감김이 남아 있음 → 또 세지 않음
    //   11/03 시연 폰 시험: 15% 근처를 오가며 PERCLOS 가 17초에 3번 → 0단계에서 3단계까지 올라감
    final bool inCooldown = _lastSuspectAt != null &&
        now.difference(_lastSuspectAt!).inSeconds < AppConfig.perclosWindowSec;

    if (hasEnoughWindow && perclos >= AppConfig.perclosThreshold) {
      if (!_perclosTriggered && !_microsleepTriggered && !inCooldown) {
        _perclosTriggered = true; // 기준 아래로 내려갔다 다시 넘어야 셈
        _lastSuspectAt = now;
        final closedFrame = _lastClosedFrame;
        final shot = closedFrame != null
            ? _Shot(_lastClosedAt ?? now, closedFrame)
            : (frame != null ? _Shot(now, frame) : null);
        _send('perclos', 'perclos', currentClosedSec, perclos, _lastEyeOpenProb,
            [?shot], cam.sensorOrientation);
      }
    } else if (perclos < AppConfig.perclosThreshold) {
      _perclosTriggered = false;
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
      return EyeReading(prob, AppConfig.contourEarOn ? contourEar(face) : null, ms,
          face.headEulerAngleX, face.headEulerAngleY, face.smilingProbability);
    } catch (e) {
      debugPrint('[eye_monitor] 사진 분석 실패: $e');
      return EyeReading(null, null, watch.elapsedMilliseconds);
    }
  }

  /// 출발 시 정면 사진 5장으로 개인 기준 설정 (중간값 * 0.5, 0.2~0.4 제한)
  ///   눈 확률이 나온 사진이 calibMinFaces(3)장 미만이면 기준을 기본값으로 되돌리고 StateError
  ///   → calibration_screen(D) 이 잡아서 "얼굴을 확인하지 못해 기본 기준으로 시작해요" (서버 CALIB_MIN_FACES 와 같은 기준)
  Future<double> calibrate(List<String> paths) async {
    final List<double> probs = [];
    for (final path in paths) {
      final prob = await analyzeFile(path);
      if (prob != null) probs.add(prob);
    }

    if (probs.length < AppConfig.calibMinFaces) {
      threshold = AppConfig.eyeClosedProb;
      throw StateError('개인 기준 측정 실패: 얼굴이 잡힌 사진 ${probs.length}장 (${AppConfig.calibMinFaces}장 필요)');
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