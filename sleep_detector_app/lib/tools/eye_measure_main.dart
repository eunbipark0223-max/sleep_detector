// ═══════════════════════════════════════════════════════════════
// tools/eye_measure_main.dart — 사진 여러 장 ML Kit 측정 도구 (앱과 따로 실행)
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0 (KPI ① · 기준값 측정)
// 수업 원본: (없음, 🔴 신규) — 앱 화면이 아니라 A 측정용. 로그인 · 서버 없이 폰 안에서만 돈다
//
// [실행]  (sleep_detector_app 폴더, 시연 폰 USB 연결)
//   flutter run -t lib/tools/eye_measure_main.dart
//
// [하는 일]
//   - [갤러리에서 사진 고르기] → 여러 장 선택 → eye_monitor.analyzeFileDetail 로 한 장씩
//       눈 뜸 확률 · 폰 EAR(눈 윤곽) · 처리 ms
//   - 결과를 화면 표 + 콘솔(CSV 줄) + 파일로 남김
//       파일: /sdcard/Android/data/com.example.sleep_detector_app/files/eye_measure.csv
//       PC 로 가져오기: adb pull /sdcard/Android/data/com.example.sleep_detector_app/files/eye_measure.csv
//   - 파일 이름에 open / half / closed 가 들어 있으면 label 칸에 넣고, 종류별 평균 · 최소 · 최대를 보여 줌
//       → 서버 result.csv (python services/face_service.py images) 와 file 칸으로 이어 붙여 비교
//
// [사진 이름 규칙 (내일 촬영)]  사람_상태_번호.jpg   예) p1_open_01.jpg · p1_half_01.jpg · p1_closed_01.jpg
//
// [주의]
//   - 팀 얼굴 사진 · 결과 CSV 는 GitHub 에 올리지 않는다 (Google Drive 에만)
//   - 기준값(config.dart)은 이 도구로 바꾸지 않는다 — 숫자를 보고 A 가 직접 고친다
// ═══════════════════════════════════════════════════════════════
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../services/eye_monitor.dart';

const _csvPath = '/sdcard/Android/data/com.example.sleep_detector_app/files/eye_measure.csv';
const _labels = ['closed', 'half', 'open']; // 파일 이름에서 찾는 순서 (서버 face_service 의 label 칸과 같은 규칙)

void main() => runApp(const MaterialApp(home: EyeMeasureScreen(), debugShowCheckedModeBanner: false));

class _Row {
  final String file;
  final String label;
  final EyeReading r;
  _Row(this.file, this.label, this.r);

  String toCsv() => [
        file,
        label,
        r.eyeOpenProb?.toStringAsFixed(4) ?? '',
        r.ear?.toStringAsFixed(4) ?? '',
        r.ms,
      ].join(',');
}

class EyeMeasureScreen extends StatefulWidget {
  const EyeMeasureScreen({super.key});

  @override
  State<EyeMeasureScreen> createState() => _EyeMeasureScreenState();
}

class _EyeMeasureScreenState extends State<EyeMeasureScreen> {
  final _monitor = EyeMonitor();
  final _rows = <_Row>[];
  bool _running = false;
  String _status = '사진을 고르세요 (여러 장 가능)';

  @override
  void dispose() {
    _monitor.close();
    super.dispose();
  }

  static String _labelOf(String name) {
    final n = name.toLowerCase();
    return _labels.firstWhere((l) => n.contains(l), orElse: () => '');
  }

  Future<void> _pickAndMeasure() async {
    final files = await ImagePicker().pickMultiImage(); // 크기 옵션 없음 → 원본 그대로 (줄이면 눈이 작아져 EAR 이 흔들림)
    if (files.isEmpty) return;
    setState(() {
      _running = true;
      _rows.clear();
    });
    for (int i = 0; i < files.length; i++) {
      final f = files[i];
      final r = await _monitor.analyzeFileDetail(f.path);
      _rows.add(_Row(f.name, _labelOf(f.name), r));
      setState(() => _status = '측정 중 ${i + 1} / ${files.length}');
    }
    await _save();
    setState(() => _running = false);
  }

  Future<void> _save() async {
    const header = 'file,label,eye_open_prob,phone_ear,ms';
    final lines = [header, ..._rows.map((r) => r.toCsv())];
    // 콘솔에도 남김 (flutter run 창에서 복사 가능)
    debugPrint('===== eye_measure.csv 시작 =====');
    for (final l in lines) {
      debugPrint(l);
    }
    debugPrint('===== eye_measure.csv 끝 =====');
    try {
      final file = File(_csvPath);
      await file.parent.create(recursive: true);
      await file.writeAsString('${lines.join('\n')}\n');
      _status = '완료 ${_rows.length}장 → $_csvPath';
    } catch (e) {
      _status = '완료 ${_rows.length}장 (파일 저장 실패 — 콘솔의 CSV 를 복사하세요: $e)';
    }
  }

  /// 종류별 평균 · 최소 · 최대 (값이 없는 사진은 뺌)
  String _summary(String label, double? Function(EyeReading) pick) {
    final v = _rows.where((r) => r.label == label).map((r) => pick(r.r)).whereType<double>().toList()..sort();
    if (v.isEmpty) return '-';
    final mean = v.reduce((a, b) => a + b) / v.length;
    return '평균 ${mean.toStringAsFixed(3)} (${v.first.toStringAsFixed(3)}~${v.last.toStringAsFixed(3)}, ${v.length}장)';
  }

  @override
  Widget build(BuildContext context) {
    final noFace = _rows.where((r) => r.r.eyeOpenProb == null).length;
    final avgMs = _rows.isEmpty ? 0 : _rows.map((r) => r.r.ms).reduce((a, b) => a + b) / _rows.length;
    return Scaffold(
      appBar: AppBar(title: const Text('눈 측정 도구 (A)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _running ? null : _pickAndMeasure,
              icon: const Icon(Icons.photo_library),
              label: const Text('갤러리에서 사진 고르기'),
            ),
            const SizedBox(height: 8),
            Text(_status),
            Text('윤곽 EAR ${AppConfig.contourEarOn ? "켬" : "꺼짐"} · 눈 폭 ${AppConfig.minEyeWidthPx.toInt()}px 미만은 EAR 빈칸'),
            if (_rows.isNotEmpty) ...[
              const Divider(),
              Text('얼굴 · 눈 확률 없음: $noFace장 · 평균 처리 ${avgMs.toStringAsFixed(0)}ms'),
              for (final l in _labels)
                if (_rows.any((r) => r.label == l))
                  Text('[$l] 뜸 확률 ${_summary(l, (r) => r.eyeOpenProb)}\n'
                      '        폰 EAR ${_summary(l, (r) => r.ear)}'),
              const Divider(),
            ],
            Expanded(
              child: ListView(
                children: [
                  for (final r in _rows)
                    Text('${r.file}  ${r.label.isEmpty ? "?" : r.label}  ${r.r}',
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
