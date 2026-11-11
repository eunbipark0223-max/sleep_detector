// ═══════════════════════════════════════════════════════════════
// widgets/owl_says.dart — 부엉이가 말풍선으로 안내하는 줄 (홈 · 운행 · 경고 화면 공용)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   11/11 초안 (부엉이를 앱 시그니처로 — "부엉이가 안내해 주는 앱")
//
// [모양]
//   [부엉이 그림] ◀[ 흰 말풍선 안에 안내 글 ]
//   - 부엉이 그림: assets/owl/owl_face0~3.png (얼굴) 또는 owl_stage0~3.png (몸 전체) — 단계 색 (초록 · 노랑 · 주황 · 빨강)
//   - 말풍선: 흰 바탕 + 진한 글자 → 단계 바탕색(노랑 · 주황 · 빨강) 위에서도 잘 읽힘
//
// [쓰는 법]
//   OwlSays(owl: OwlSays.face(stage), text: '안전 운전 중이에요')
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../theme.dart';

/// 한국어 줄바꿈을 단어 단위로 — Flutter 는 글자 중간에서도 줄을 바꿔서 "자 / 주", "고정 / 하고" 처럼 끊김.
///   단어 안의 글자 사이에 '줄 바꾸지 마' 표시(U+2060 WORD JOINER)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다 (11/11)
String keepWords(String text) => text
    .split('\n')
    .map((line) => line.split(' ').map((w) => w.split('').join('⁠')).join(' '))
    .join('\n');

class OwlSays extends StatelessWidget {
  final String owl; // 부엉이 그림 경로
  final String text; // 말풍선 글
  final double owlSize;
  final double fontSize;
  final int maxLines;

  const OwlSays({
    super.key,
    required this.owl,
    required this.text,
    this.owlSize = 64,
    this.fontSize = 20,
    this.maxLines = 3,
  });

  /// 단계별 부엉이 얼굴 (0 초록 · 1 노랑 · 2 주황 · 3 빨강)
  static String face(int stage) => 'assets/owl/owl_face${stage.clamp(0, 3)}.png';

  /// 단계별 부엉이 몸 전체
  static String body(int stage) => 'assets/owl/owl_stage${stage.clamp(0, 3)}.png';

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Image.asset(owl, width: owlSize, height: owlSize, fit: BoxFit.contain),
        const SizedBox(width: 4),
        // 말풍선 꼬리 (부엉이 쪽을 가리킴)
        CustomPaint(size: const Size(14, 24), painter: _TailPainter()),
        Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16), // 운전 중에 읽기 쉽게 넉넉히 (11/11)
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 6, offset: Offset(0, 2))],
            ),
            child: Text(
              keepWords(text),
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1.3),
            ),
          ),
        ),
      ],
    );
  }
}

/// 부엉이 아래에 붙는 말풍선 — 꼬리가 위(부엉이 쪽)를 가리킴. 퀴즈처럼 글을 크게 보여 줄 때 (11/11 초안)
///   [부엉이 얼굴]
///        ▲
///   [ 큰 글씨 말풍선 ]
class OwlAbove extends StatelessWidget {
  final String owl;
  final String text;
  final double owlSize;
  final double fontSize;

  const OwlAbove({super.key, required this.owl, required this.text, this.owlSize = 180, this.fontSize = 40});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(child: Image.asset(owl, width: owlSize, height: owlSize, fit: BoxFit.contain)),
        const SizedBox(height: 6),
        Center(child: CustomPaint(size: const Size(32, 18), painter: _TailUpPainter())),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 3))],
          ),
          child: Text(
            keepWords(text),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w900, color: Colors.black, height: 1.3),
          ),
        ),
      ],
    );
  }
}

class _TailUpPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, size.height)
      ..lineTo(size.width / 2, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(0, size.height / 2)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
