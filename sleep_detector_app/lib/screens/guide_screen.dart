// ═══════════════════════════════════════════════════════════════
// screens/guide_screen.dart — 사용 가이드 (MY 탭)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   11/11 초안 · 11/18 애플 스타일로 다시 (피드백 여러 번 반영)
//
// [이 화면이 하는 일]
//   - 처음 쓰는 기사님이 "이 앱이 뭘 하는지" 한눈에 알게
//   - ① 사용 방법 3가지  ② 단계별 안내 (정상 · 주의 · 휴식 권고 · 긴급)
//
// [모양] (11/18 피드백 — 아이폰 설정 화면처럼)
//   - 맨 위: 캐릭터 그림 자리 | 세로 구분선(그림 높이의 90%) | 큰 제목 + 작은 설명 (말풍선 없음)
//   - 묶음 위 작은 회색 제목 · 흰 카드(둥글기 12) · 줄 사이 선은 카드 폭의 90% 가운데
//   - 단계별 안내: 왼쪽 색 점 + 이름 · 오른쪽 회색 설명 (두 줄이면 줄이 커짐) — 설정 앱의 '이름 | 값' 줄
//   - 단계 문구는 경고 화면 · 음성과 같은 말 (stage_texts.dart — 한 곳만 고치면 여기도 바뀜)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../stage_texts.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/buddy.dart';

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
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('사용 가이드'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
        children: [
          // 캐릭터 | 세로 구분선 | 제목 (운행 화면 아래 글과 같은 구성)
          const SizedBox(
            height: 84,
            child: Row(children: [
              Buddy(stage: 0, size: 84),
              VerticalDivider(width: 30, thickness: 1, indent: 4, endIndent: 4, color: AppColors.fill),
              Expanded(
                child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('앱 사용법',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.6, color: AppColors.textPrimary)),
                  SizedBox(height: 4),
                  Text('출발 전에 한 번 읽어 주세요', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 30),
          const _Title('사용 방법'),
          _Group(children: [
            for (var i = 0; i < _steps.length; i++)
              _StepLine(number: i + 1, title: _steps[i].$1, body: _steps[i].$2),
          ]),
          const SizedBox(height: 28),
          const _Title('단계별 안내'),
          _Group(children: [
            for (var s = 0; s < _stageNames.length; s++)
              _StageLine(stage: s, name: _stageNames[s], text: s == 0 ? StageTexts.normal : StageTexts.headline(s)),
          ]),
        ],
      ),
    );
  }
}

/// 묶음 위 작은 회색 제목 (아이폰 설정)
class _Title extends StatelessWidget {
  final String text;
  const _Title(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8), // (11/18) 아래 카드 테두리 쪽으로
        child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      );
}

/// 흰 카드(둥글기 12 · 옅은 테두리) 하나에 줄 여러 개 — 줄 사이 선은 카드 폭의 90% 가운데
class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});
  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: LayoutBuilder(builder: (context, c) {
          final side = c.maxWidth * 0.05;
          return Column(children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0) Divider(height: 1, thickness: 1, indent: side, endIndent: side, color: AppColors.line),
              children[i],
            ],
          ]);
        }),
      );
}

/// 사용 방법 한 줄 — 남색 번호(줄 가운데) · 굵은 제목 · 아래 회색 설명
class _StepLine extends StatelessWidget {
  final int number;
  final String title;
  final String body;
  const _StepLine({required this.number, required this.title, required this.body});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text('$number',
                strutStyle: const StrutStyle(fontSize: 12.5, height: 1, forceStrutHeight: true),
                style: const TextStyle(fontSize: 12.5, height: 1, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      );
}

/// 단계별 안내 한 줄 — 왼쪽 색 점 + 이름 · 오른쪽 회색 설명 (오른쪽 정렬, 두 줄이면 줄이 커짐)
class _StageLine extends StatelessWidget {
  final int stage;
  final String name;
  final String text;
  const _StageLine({required this.stage, required this.name, required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          Buddy(stage: stage, size: 40, breathe: false), // (11/19) 단계 점 대신 단계 캐릭터 얼굴
          const SizedBox(width: 12),
          // (11/18 피드백) 이름 칸 폭 고정 → 설명은 모두 같은 곳에서 시작 · 왼쪽 정렬 (두 줄이면 둘째 줄도 같은 시작점)
          SizedBox(
            width: 78,
            child: Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.45, color: AppColors.textSecondary)),
          ),
        ]),
      );
}
