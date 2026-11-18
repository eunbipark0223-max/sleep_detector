// ═══════════════════════════════════════════════════════════════
// screens/guide_screen.dart — 사용 가이드 (MY 탭)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   11/11 초안 · 11/18 애플 스타일로 다시
//
// [이 화면이 하는 일]
//   - 처음 쓰는 기사님이 "이 앱이 뭘 하는지" 한눈에 알게
//   - ① 사용 방법 3가지  ② 단계별 안내 (정상 · 주의 · 휴식 권고 · 긴급)
//
// [모양] (11/18 사용자 요청)
//   - 맨 위 '안녕하세요' 크게 · 아래 작게 한 줄
//   - 아이콘 없이, 묶음마다 흰 카드 하나 안에 줄로 나눔 (번호 · 제목 · 설명)
//   - 단계별 안내: 색 바탕 없이 이름 왼쪽에 진한 단계 색 점 하나
//   - 단계 문구는 경고 화면 · 음성과 같은 말 (stage_texts.dart — 한 곳만 고치면 여기도 바뀜)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../stage_texts.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const List<(String, String)> _steps = [
    ('휴대폰을 거치해 주세요', '얼굴이 카메라 가운데 보이도록 맞춰 주세요'),
    ('앞을 보고 운전해 주세요', '화면 대신 음성 안내를 들어 주세요'),
    ('경고가 들리면 따라 주세요', '단계별 안내에 따라 안전한 곳에서 쉬어 주세요'),
  ];

  static const List<String> _stageNames = ['정상', '주의', '휴식 권고', '긴급'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(title: const Text('사용 가이드'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          const Text('안녕하세요',
              style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          const Text('졸음을 지켜 주는 부엉이예요', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 32),
          const _Title('사용 방법'),
          _Group(children: [
            for (var i = 0; i < _steps.length; i++)
              _Line(
                lead: Container(
                  width: 24,
                  height: 24,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                  child: Text('${i + 1}',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                title: _steps[i].$1,
                body: _steps[i].$2,
              ),
          ]),
          const SizedBox(height: 28),
          const _Title('단계별 안내'),
          _Group(children: [
            for (var s = 0; s < _stageNames.length; s++)
              _Line(
                lead: Padding(
                  padding: const EdgeInsets.only(left: 7, right: 7, top: 7), // 제목 글자 가운데 높이
                  child: Container(
                      width: 10, height: 10, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
                ),
                title: _stageNames[s],
                // 경고 화면 · 음성과 같은 말 (0단계는 홈의 '안전 운전 중이에요')
                body: s == 0 ? StageTexts.normal : StageTexts.headline(s),
              ),
          ]),
        ],
      ),
    );
  }
}

class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );
}

/// 흰 카드(회색 테두리) 하나 안에 줄 여러 개 — 줄 사이 얇은 선
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) => WebCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 52, color: AppColors.line),
            children[i],
          ],
        ]),
      );
}

/// 한 줄 — 왼쪽 번호(또는 색 점) · 굵은 제목 · 아래 설명
class _Line extends StatelessWidget {
  final Widget lead;
  final String title;
  final String body;
  const _Line({required this.lead, required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: const EdgeInsets.only(top: 1), child: SizedBox(width: 24, child: Center(child: lead))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(body, style: const TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary)),
          ]),
        ),
      ]),
    );
  }
}
