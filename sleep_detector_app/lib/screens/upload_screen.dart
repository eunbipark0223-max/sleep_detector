// ═══════════════════════════════════════════════════════════════
// screens/upload_screen.dart — 사진 1장 테스트 (비상 시연 · KPI ① 측정)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/upload_screen.dart (🟡 수정)
//
// [이 파일이 하는 일]
//   - 갤러리 / 촬영으로 사진 1장 → eye_monitor.analyzeFile 로 ML Kit 눈 뜸 확률 표시
//   - → sendDetect (reason 없이) → 서버 EAR 결과 · 단계 표시
//
// [주의]
//   - 가장 먼저 완성 (카메라 자동 감지가 안 될 때 발표 보험)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════


import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/sleep_response.dart';
import '../services/api_service.dart';
import '../theme.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  Uint8List? _photo; // 고른 사진 (없으면 null)
  SleepResponse? _result; // 서버가 돌려준 결과 (없으면 null)
  String? _error; // 화면에 보여 줄 오류 글
  bool _loading = false; // 서버 응답을 기다리는 중

  // 사진 고르기 (갤러리 / 카메라)
  Future<void> _pick(ImageSource source) async {
    try {
      final file = await ImagePicker().pickImage(source: source, maxWidth: 1280, imageQuality: 85);
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _result = null;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = '사진을 불러오지 못했어요. 사진 · 카메라 권한을 확인해 주세요');
    }
  }

  // 서버로 사진 보내고 결과 받기
  Future<void> _send() async {
    final photo = _photo;
    if (photo == null || _loading) return;

    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });

    try {
      // TODO: A의 eye_monitor가 완성되면 눈 뜸 확률을 여기서 같이 보내기
      final result = await ApiService.sendDetect(photo);
      if (!mounted) return;
      setState(() => _result = result);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('사진 1장 테스트')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            AspectRatio(
              aspectRatio: 4 / 3,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.cardBorder),
                ),
                clipBehavior: Clip.antiAlias,
                child: _photo == null
                    ? const Center(child: Text('얼굴 사진을 1장 골라 주세요'))
                    : Image.memory(_photo!, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('갤러리'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : () => _pick(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_outlined),
                    label: const Text('촬영'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_photo == null || _loading) ? null : _send,
              child: _loading
                  ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
              )
                  : const Text('졸음 확인하기'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _errorBox(_error!),
            ],
            if (_result != null) ...[
              const SizedBox(height: 16),
              _resultCard(_result!),
            ],
          ],
        ),
      ),
    );
  }

  // 에러 상자 (빨간 테두리)
  Widget _errorBox(String message) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.urgent),
      ),
      child: Text(message, style: const TextStyle(color: AppColors.urgent, fontSize: 15)),
    );
  }

  // 결과 카드: 단계 색 카드 + (있으면) 기사 음성 보고 + 눈 숫자
  Widget _resultCard(SleepResponse r) {
    final bg = AppColors.stage(r.stage); // 단계(0~3) → 화면 색
    final fg = AppColors.onStage(r.stage); // 그 색 위에 올리는 글자색
    final summary = r.summary.isNotEmpty ? r.summary : '졸음이 감지되지 않았어요.';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${r.stage}단계 · ${r.status}',
                style: TextStyle(color: fg, fontSize: 24, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Text(summary, style: TextStyle(color: fg, fontSize: 16)),
              if (r.guidance.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(r.guidance, style: TextStyle(color: fg, fontSize: 16, fontWeight: FontWeight.w600)),
              ],
            ],
          ),
        ),
        if (r.driverVoice.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.aiPurple, borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔊 기사 음성 보고',
                  style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(r.driverVoice, style: const TextStyle(color: Colors.white, fontSize: 15)),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _infoRow('졸음 판정', r.isSleep ? '졸음' : '정상'),
                _infoRow('EAR (눈 열림)', r.ear?.toStringAsFixed(2) ?? '-'),
                _infoRow('판정 방식', r.method.isEmpty ? '-' : r.method),
                _infoRow('최근 10분 졸음', '${r.sleepCount10min}번'),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // 결과 표의 한 줄 (왼쪽 이름 · 오른쪽 값)
  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
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