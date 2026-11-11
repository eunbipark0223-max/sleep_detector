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

  // 쓰는 순서 3가지 (Figma 시안 '졸음운전 감지 앱2' 앱 사용 가이드, 11/12 팀장)
  static const List<(IconData, String, String)> _steps = [
    (Icons.photo_camera_outlined, '휴대폰을 거치해 주세요', '얼굴이 카메라 가운데 보이도록 맞춰 주세요.'),
    (Icons.visibility_outlined, '앞을 보고 운전해 주세요', '화면 대신 음성 안내를 들어 주세요.'),
    (Icons.volume_up_outlined, '경고가 들리면 따라 주세요', '단계별 안내에 따라 안전한 곳에서 쉬어 주세요.'),
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
              margin: const EdgeInsets.only(bottom: 9),
              constraints: const BoxConstraints(minHeight: 92),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Row(
                children: [
                  // 왼쪽 아이콘 칸 (연한 남색 네모)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: const Color(0xFFEDF0F8), borderRadius: BorderRadius.circular(14)),
                    child: Icon(_steps[i].$1, size: 24, color: AppColors.navy),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 번호 동그라미
                        Container(
                          width: 20,
                          height: 20,
                          margin: const EdgeInsets.only(top: 2, right: 6),
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
                          child: Text('${i + 1}',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Colors.white)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_steps[i].$2,
                                  style: const TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                              const SizedBox(height: 4),
                              Text(keepWords(_steps[i].$3),
                                  style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
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
