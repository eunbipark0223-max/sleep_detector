// ═══════════════════════════════════════════════════════════════
// owl_buddy.dart — (보류 11/19) 단계별 부엉이 일러스트 · 지금은 Buddy(동그란 해) 를 씀
// ═══════════════════════════════════════════════════════════════
// [무엇] 동글동글한 부엉이 덩어리 캐릭터 — 납작한 색 몸 + 선 하나로 그린 얼굴 (Headspace 일러스트 느낌)
//   그림 파일 없이 코드로 그려서 어떤 크기에서도 선명함
//   0 정상 초록 = 눈 뜨고 웃음 · 1 주의 노랑 = 눈 반쯤 감김 · 2 휴식 권고 주황 = 눈 감고 z · 3 긴급 빨강 = 깜짝 놀람
// [쓰는 법] Buddy(stage: 2, size: 120)   (색 · 선 굵기 · 숨 속도는 design_tokens.dart AppIllust)
// ═══════════════════════════════════════════════════════════════
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

class OwlBuddy extends StatefulWidget {
  final int stage;
  final double size;
  final bool breathe; // 숨 쉬듯 살짝 움직임 (작은 아이콘은 끔)
  const OwlBuddy({super.key, this.stage = 0, this.size = 100, this.breathe = true});

  @override
  State<OwlBuddy> createState() => _OwlBuddyState();
}

class _OwlBuddyState extends State<OwlBuddy> with TickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(OwlBuddy old) {
    super.didUpdateWidget(old);
    // (11/19 고침) 단계가 바뀌면 움직임을 새로 만들지 않고 속도만 바꿈 — 새로 만들면 예전 그림이 겹쳐 남음
    if (old.breathe != widget.breathe) {
      _c?.dispose();
      _c = null;
      _setup();
    } else if (old.stage != widget.stage && _c != null) {
      _c!
        ..duration = widget.stage.clamp(0, 3) == 3 ? AppIllust.breathFast : AppIllust.breath
        ..repeat(reverse: true);
    }
  }

  void _setup() {
    if (!widget.breathe) return;
    _c = AnimationController(
      vsync: this,
      duration: widget.stage.clamp(0, 3) == 3 ? AppIllust.breathFast : AppIllust.breath,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.stage.clamp(0, 3);
    final box = Size(widget.size, widget.size);
    final c = _c;
    if (c == null) return CustomPaint(size: box, painter: _OwlPainter(s, 0));
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) => CustomPaint(size: box, painter: _OwlPainter(s, Curves.easeInOut.transform(c.value))),
    );
  }
}

class _OwlPainter extends CustomPainter {
  final int stage;
  final double t; // 0~1 숨
  const _OwlPainter(this.stage, this.t);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100; // 그림 좌표 100 x 100 기준
    canvas.save();
    canvas.scale(u);

    // 바닥 납작 그림자 — 숨 쉴 때 살짝 넓어짐
    canvas.drawOval(Rect.fromCenter(center: const Offset(50, 96), width: 68 + 4 * t, height: 6),
        Paint()..color = AppIllust.shadow);

    // 숨: 아래를 기준으로 위로 살짝 늘어남
    canvas.translate(50, 94);
    canvas.scale(1 - 0.01 * t, 1 + 0.03 * t);
    canvas.translate(-50, -94);
    if (stage == 2) {
      // 꾸벅 — 살짝 기울어짐
      canvas.translate(50, 94);
      canvas.rotate(-0.05);
      canvas.translate(-50, -94);
    }

    final body = Paint()..color = AppIllust.bodyOf(stage)..isAntiAlias = true;
    // 귀깃 (부엉이 귀) — 몸과 같은 색이라 몸에 붙어 보임
    //   (끝이 살짝 둥근 뾰족한 삼각형 — 돔 위로 쏙 올라옴)
    canvas.drawPath(
        Path()
          ..moveTo(9, 50)
          ..lineTo(8, 18)
          ..quadraticBezierTo(8, 12, 14, 14)
          ..lineTo(38, 23)
          ..close(),
        body);
    canvas.drawPath(
        Path()
          ..moveTo(91, 50)
          ..lineTo(92, 18)
          ..quadraticBezierTo(92, 12, 86, 14)
          ..lineTo(62, 23)
          ..close(),
        body);
    // 몸 — 크고 넓은 돔 (옆이 살짝 불룩) · 바닥은 평평하게
    final bodyPath = Path()
      ..moveTo(6, 66)
      ..cubicTo(6, 34, 26, 16, 50, 16)
      ..cubicTo(74, 16, 94, 34, 94, 66)
      ..cubicTo(94, 78, 93, 88, 88, 94)
      ..lineTo(12, 94)
      ..cubicTo(7, 88, 6, 78, 6, 66)
      ..close();
    canvas.drawPath(bodyPath, body);
    // 배 — 반투명 흰 타원
    canvas.save();
    canvas.clipPath(bodyPath);
    canvas.drawOval(Rect.fromCenter(center: const Offset(50, 86), width: 50, height: 36), Paint()..color = AppIllust.belly);
    canvas.restore();

    final ink = Paint()
      ..color = AppIllust.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = AppIllust.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final inkFill = Paint()..color = AppIllust.ink..isAntiAlias = true;
    const l = Offset(36, 52), r = Offset(64, 52);
    // 부엉이 눈 둘레 (동그란 얼굴판) — 반투명 흰 원
    for (final e in [l, r]) {
      canvas.drawCircle(e, 12, Paint()..color = AppIllust.belly);
    }

    switch (stage) {
      case 0: // 깨어 있음 · 웃음
        canvas.drawCircle(l, 3.8, inkFill);
        canvas.drawCircle(r, 3.8, inkFill);
        canvas.drawPath(Path()..moveTo(42, 63)..quadraticBezierTo(50, 71, 58, 63), ink);
        canvas.drawCircle(const Offset(22, 68), 5, Paint()..color = AppIllust.cheek);
        canvas.drawCircle(const Offset(78, 68), 5, Paint()..color = AppIllust.cheek);
      case 1: // 졸림 — 눈꺼풀이 반쯤 내려옴
        for (final e in [l, r]) {
          canvas.drawArc(Rect.fromCircle(center: e, radius: 4.2), 0, math.pi, true, inkFill);
          canvas.drawLine(e.translate(-6, 0), e.translate(6, 0), ink);
        }
        canvas.drawLine(const Offset(45, 64), const Offset(55, 64), ink);
      case 2: // 잠듦 — 감은 눈 ‿ · 하품 o · z
        for (final e in [l, r]) {
          canvas.drawPath(Path()..moveTo(e.dx - 6, e.dy - 1)..quadraticBezierTo(e.dx, e.dy + 6, e.dx + 6, e.dy - 1), ink);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 65), width: 7, height: 8), ink);
        _z(canvas, const Offset(80, 10), 9, ink);
        _z(canvas, const Offset(92, 0), 6, ink..strokeWidth = AppIllust.stroke * 0.8);
      default: // 3 긴급 — 놀란 큰 눈 · 벌린 입 · 놀람 선
        for (final e in [l, r]) {
          canvas.drawCircle(e, 6.5, Paint()..color = Colors.white);
          canvas.drawCircle(e, 6.5, ink);
          canvas.drawCircle(e, 2.6, inkFill);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 67), width: 11, height: 9), inkFill);
        canvas.drawLine(const Offset(8, 14), const Offset(14, 22), ink);
        canvas.drawLine(const Offset(2, 26), const Offset(10, 29), ink);
        canvas.drawLine(const Offset(92, 14), const Offset(86, 22), ink);
        canvas.drawLine(const Offset(98, 26), const Offset(90, 29), ink);
    }
    canvas.restore();
  }

  void _z(Canvas c, Offset o, double w, Paint p) {
    c.drawPath(
        Path()
          ..moveTo(o.dx, o.dy)
          ..lineTo(o.dx + w, o.dy)
          ..lineTo(o.dx, o.dy + w)
          ..lineTo(o.dx + w, o.dy + w),
        p);
  }

  @override
  bool shouldRepaint(_OwlPainter old) => old.stage != stage || old.t != t;
}
