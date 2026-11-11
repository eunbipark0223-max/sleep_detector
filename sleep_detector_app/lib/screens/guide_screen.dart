// ═══════════════════════════════════════════════════════════════
// screens/guide_screen.dart — 앱 사용 가이드 (≡ 메뉴)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   11/11 초안
//
// [이 파일이 하는 일]
//   - 처음 쓰는 기사님이 "이 앱이 뭘 하는지"를 부엉이 그림으로 한눈에 알게
//   - ① 쓰는 순서 3단계  ② 부엉이 색의 뜻 (정상 · 주의 · 휴식 권고 · 긴급) — 운행 · 경고 화면과 같은 부엉이 · 같은 색
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/owl_says.dart';
import 'warning_screen.dart' show stageTint;

class GuideScreen extends StatelessWidget {
  const GuideScreen({super.key});

  static const List<(String, String)> _steps = [
    ('폰을 거치대에 고정해요', '얼굴이 화면 가운데에 보이게'),
    ('[운행 시작]을 눌러요', '부엉이가 눈을 지켜보기 시작해요'),
    ('부엉이 말을 들어요', '졸면 소리로 깨우고, 쉴 곳을 알려 줘요'),
  ];

  static const List<(String, String)> _stages = [
    ('정상', '안전하게 운전 중이에요'),
    ('주의', '졸음이 감지됐어요. 창문을 열고 환기해요'),
    ('휴식 권고', '가까운 졸음쉼터에서 15분 쉬어요'),
    ('긴급', '관리자에게 알렸어요. 바로 정차해요'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('앱 사용 가이드')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          OwlSays(owl: OwlSays.face(0), text: '안녕하세요! 졸음을 지켜 주는 부엉이예요', owlSize: 96, fontSize: 20),
          const SizedBox(height: 24),
          const Text('이렇게 써요', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          for (var i = 0; i < _steps.length; i++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.navy,
                    child: Text('${i + 1}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.white)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_steps[i].$1, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(_steps[i].$2, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 20),
          const Text('부엉이 색의 뜻', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          for (var s = 0; s < _stages.length; s++)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: stageTint(s), borderRadius: BorderRadius.circular(16)),
              child: Row(
                children: [
                  Image.asset(OwlSays.face(s), width: 72, height: 72),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_stages[s].$1, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(keepWords(_stages[s].$2), style: const TextStyle(fontSize: 16, color: AppColors.textPrimary, height: 1.3)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
