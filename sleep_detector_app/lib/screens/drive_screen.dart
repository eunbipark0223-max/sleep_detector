// ═══════════════════════════════════════════════════════════════
// screens/drive_screen.dart — 운행 화면 (카메라 · 눈 판정 · 의심 전송 · ping)  ⭐ 핵심
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/upload_screen.dart (전송) · report_screen.dart (위치), Flutter 9·10일차 (🔴 신규)
//
// [이 파일이 하는 일]
//   - 전면 카메라 미리보기 + startImageStream → eye_monitor.processFrame
//   - onSuspect → camera_image_utils.toJpg → api_service.sendDetect (위도 · 경도 포함)
//   -   → 응답 isSleep 이면 warning_screen 을 이 화면 위에 겹쳐 띄움 (Stack, 카메라 · 판정은 계속)
//   - 30초마다 sendPing → stage 로 화면 색 (1단계 자동 해제 · 조치완료 반영), restDue 면 휴게 배너 + 🔊 1번
//   - onCheckCamera → 🔊 '카메라를 확인하세요'
//   - 화면 꺼짐 방지 (wakelock_plus), 0단계 화면에 눈 뜸 확률 · 내 기준 표시
//   - 나갈 때 스트림 정지 · eye_monitor.close()
//
// [주의]
//   - Navigator.push 로 경고 화면을 띄우면 카메라가 멈춤 → 반드시 Stack 으로 겹쳐 띄우기
//   - 위치(geolocator)는 경고 기록용만 — 속도 · 정차 판단에 쓰지 않음
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/eye_monitor.dart';
import '../theme.dart';
import 'warning_screen.dart';

class DriveScreen extends StatefulWidget {
  /// 측정 화면(D)이 돌려준 "내 눈 기준값". 측정을 건너뛰었으면 null → 기본 기준을 쓴다.
  /// 홈 화면에서 이렇게 연다:  DriveScreen(threshold: t)
  final double? threshold;

  const DriveScreen({super.key, this.threshold});

  @override
  State<DriveScreen> createState() => _DriveScreenState();
}

class _DriveScreenState extends State<DriveScreen> {
  late final EyeMonitor _eye; // 눈 감시 도구 (A)
  CameraController? _controller; // 앞 카메라

  int _stage = 0; // 지금 단계 (0 정상 ~ 3 긴급)
  double? _eyeOpenProb; // 지금 눈 뜸 확률 (모르면 null)
  double _perclos = 0; // 최근 30초 눈 감은 비율
  String _notice = ''; // 화면에 보여 줄 안내 글
  bool _sending = false; // 서버에 보내는 중인지 (같은 졸음을 두 번 보내지 않게)
  bool _warningOpen = false; // 경고 화면이 떠 있는지 (또 띄우지 않게)

  // 카메라 지킴이: 사진(프레임)이 마지막으로 들어온 시각을 기억했다가, 오래 안 들어오면 카메라를 다시 켠다
  Timer? _watchdog;
  DateTime _lastFrameAt = DateTime.now();
  bool _restarting = false; // 다시 켜는 중인지 (두 번 겹쳐 켜지 않게)

  @override
  void initState() {
    super.initState();

    // 눈 감시 도구를 만들고, 알림이 오면 받을 함수를 연결한다
    _eye = EyeMonitor(
      onSuspect: _onSuspect,
      onCheckCamera: _onCheckCamera,
      onFrameResult: _onFrameResult,
    );

    // ⭐ 측정 화면이 돌려준 기준값을 눈 감시 도구에 넣는다 (없으면 기본값 그대로)
    final t = widget.threshold;
    if (t != null) _eye.threshold = t;

    _startCamera(); // 카메라 켜기

    // 2초마다 카메라가 살아 있는지 확인한다
    _watchdog = Timer.periodic(const Duration(seconds: 2), (_) => _checkCamera());
  }

  // 측정 화면(D)이 카메라를 늦게 정리하면, 막 켠 운행 화면 카메라까지 같이 꺼질 때가 있다.
  // 이때는 오류 없이 사진만 안 들어오므로, 3초 넘게 사진이 없으면 카메라를 다시 켠다.
  Future<void> _checkCamera() async {
    if (!mounted || _restarting || _controller == null) return;
    if (DateTime.now().difference(_lastFrameAt).inSeconds < 3) return;
    _restarting = true;
    final old = _controller;
    setState(() => _controller = null);
    try {
      await old?.dispose();
    } catch (_) {}
    await _startCamera();
    _restarting = false;
  }

  // 앞 카메라를 켠다.
  // 측정 화면(D)이 막 닫힌 직후에는 카메라가 아직 정리되는 중이라 첫 시도가 실패할 수 있다.
  // 그래서 잠깐 기다렸다가 켜고, 안 켜지면 1초 쉬고 최대 3번까지 다시 시도한다.
  Future<void> _startCamera() async {
    await Future.delayed(const Duration(milliseconds: 500)); // 이전 화면이 카메라를 놓을 시간
    for (var attempt = 1; attempt <= 3; attempt++) {
      if (!mounted) return;
      try {
        await _openCamera();
        return; // 켜졌으면 끝
      } catch (e) {
        if (attempt == 3) {
          if (mounted) setState(() => _notice = '카메라를 켤 수 없어요: $e');
          return;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
  }

  // 카메라를 한 번 켜 본다 (실패하면 오류를 위로 던진다)
  Future<void> _openCamera() async {
    final cameras = await availableCameras();
    final front = cameras.firstWhere(
          (c) => c.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    final controller = CameraController(
      front,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.nv21, // ⭐ 꼭 (A님 camera_image_utils 약속)
    );
    try {
      await controller.initialize();
    } catch (e) {
      await controller.dispose(); // 실패한 카메라는 정리하고 오류를 위로 던진다
      rethrow;
    }
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    _lastFrameAt = DateTime.now(); // 지킴이 시계를 새로 시작
    try {
      // 프레임이 올 때마다 A님 눈 감시 도구에 넘긴다 (바쁘면 A님 코드가 알아서 버림)
      await controller.startImageStream((image) {
        _lastFrameAt = DateTime.now(); // 사진이 들어왔다고 지킴이에게 알림
        _eye.processFrame(image, front);
      });
    } catch (e) {
      await controller.dispose();
      if (mounted) setState(() => _controller = null);
      rethrow;
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel(); // 카메라 지킴이 끄기
    _controller?.dispose(); // 카메라 끄기
    _eye.close(); // 눈 감시 도구 끄기
    super.dispose();
  }

  // 졸음 의심 (눈을 오래 감음 / 최근 30초 중 많이 감음) → 서버에 보내서 확인받기
  Future<void> _onSuspect(String reason, double closedSec, double perclos,
      double eyeOpenProb, Uint8List? frame) async {
    if (!mounted || _sending) return;
    _sending = true;
    setState(() => _notice = '서버 확인 중…');
    try {
      // frame 이 null 이어도 꼭 보낸다 (고개를 떨군 채 졸면 사진이 없음 → 서버가 앱 판단대로 처리)
      final res = await ApiService.sendDetect(
        frame,
        reason: reason,
        closedSec: closedSec,
        perclos: perclos,
        eyeOpenProb: eyeOpenProb,
      );
      if (!mounted) return;
      setState(() {
        _stage = res.stage;
        _notice = res.isSleep ? '졸음 확정 (${res.stage}단계)' : '서버 확인: 눈 뜸 → 취소';
      });
      // 졸음이 맞고 1단계 이상이면 경고 화면을 띄운다 (이미 떠 있으면 또 띄우지 않는다)
      if (res.isSleep && res.stage >= 1 && !_warningOpen) {
        _warningOpen = true;
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WarningScreen(response: res)),
        );
        _warningOpen = false; // 경고 화면이 닫히면(뒤로 가기) 다시 띄울 수 있게
      }
    } catch (e) {
      if (mounted) setState(() => _notice = '서버 연결 실패: $e');
    } finally {
      _sending = false;
    }
  }

  // 얼굴이 3초 이상 안 보임
  // TODO: 다음 단계에서 🔊 '카메라를 확인하세요'
  void _onCheckCamera() {
    if (!mounted) return;
    setState(() => _notice = '카메라를 확인하세요');
  }

  // 프레임마다 오는 눈 뜸 확률 · PERCLOS (0단계 화면 표시용)
  void _onFrameResult(double? eyeOpenProb, double perclos, double? ear) {
    if (!mounted) return;
    setState(() {
      _eyeOpenProb = eyeOpenProb;
      _perclos = perclos;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bg = AppColors.stage(_stage);
    final fg = AppColors.onStage(_stage);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        foregroundColor: fg,
        elevation: 0,
        title: const Text('운행 중'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 16),
            Icon(_stageIcon(_stage), size: 72, color: fg),
            const SizedBox(height: 12),
            Text(
              _stageTitle(_stage),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: fg),
            ),
            const SizedBox(height: 24),
            // 내 기준 · 눈 뜸 확률 · PERCLOS
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
              child: Column(
                children: [
                  _row('내 눈 기준', _eye.threshold.toStringAsFixed(2)),
                  _row('눈 뜸 확률', _eyeOpenProb == null ? '-' : _eyeOpenProb!.toStringAsFixed(2)),
                  _row('최근 30초 감은 비율', '${(_perclos * 100).toStringAsFixed(0)}%'),
                ],
              ),
            ),
            if (_notice.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(_notice, textAlign: TextAlign.center, style: TextStyle(fontSize: 15, color: fg)),
            ],
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: fg,
                side: BorderSide(color: fg),
                minimumSize: const Size.fromHeight(50),
              ),
              child: const Text('운행 종료'),
            ),
          ],
        ),
      ),
    );
  }

  // 단계별 큰 글자 (0 정상 · 1 주의 · 2 휴식 권고 · 3 긴급)
  String _stageTitle(int stage) {
    switch (stage) {
      case 1:
        return '졸음이 감지됐어요';
      case 2:
        return '가까운 졸음쉼터에서 쉬어 가세요';
      case 3:
        return '즉시 안전한 곳에 정차하세요';
      default:
        return '안전 운전 중이에요';
    }
  }

  // 단계별 아이콘
  IconData _stageIcon(int stage) {
    switch (stage) {
      case 1:
        return Icons.warning_amber_rounded;
      case 2:
        return Icons.local_cafe_outlined;
      case 3:
        return Icons.report_gmailerrorred;
      default:
        return Icons.remove_red_eye_outlined;
    }
  }

  // 표의 한 줄 (왼쪽 이름 · 오른쪽 값)
  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}