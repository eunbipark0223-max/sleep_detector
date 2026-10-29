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
  }

  // 앞 카메라를 켜고, 프레임이 올 때마다 눈 감시 도구에 넘긴다
  Future<void> _startCamera() async {
    try {
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
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      // 프레임이 올 때마다 A님 눈 감시 도구에 넘긴다 (바쁘면 A님 코드가 알아서 버림)
      await controller.startImageStream((image) => _eye.processFrame(image, front));
    } catch (e) {
      if (mounted) setState(() => _notice = '카메라를 켤 수 없어요: $e');
    }
  }

  @override
  void dispose() {
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
            Icon(Icons.remove_red_eye_outlined, size: 72, color: fg),
            const SizedBox(height: 12),
            Text(
              '안전 운전 중이에요',
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