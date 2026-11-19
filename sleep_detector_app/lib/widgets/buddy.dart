// ═══════════════════════════════════════════════════════════════
// buddy.dart — 단계별 동그란 해 캐릭터 (11/19 C)
// ═══════════════════════════════════════════════════════════════
// [무엇] Headspace 일러스트 느낌의 동그란 캐릭터 — 반투명 단계 색 동그라미 + 선 하나로 그린 얼굴
//   그림 파일 없이 코드로 그려서 어떤 크기에서도 선명함
//   0 정상 초록 = 편안하게 웃음 · 1 주의 노랑 = 졸린 눈 · 2 휴식 권고 주황 = 꾸벅 z · 3 긴급 빨강 = 깜짝 놀람
//   색은 우리 단계 색에 투명도 85% (design_tokens.dart AppIllust.orb)
// [쓰는 법] Buddy(stage: 2, size: 120)   — 부엉이 판은 보류 (owl_buddy.dart)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../design_tokens.dart';

class Buddy extends StatefulWidget {
  final int stage;
  final double size;
  final bool breathe; // 숨 쉬듯 살짝 움직임 (작은 아이콘은 끔)
  final bool alert; // (11/19) 운행 · 경고 화면 — 1 · 2단계를 졸린 얼굴 대신 '경고하는' 얼굴로
  const Buddy({super.key, this.stage = 0, this.size = 100, this.breathe = true, this.alert = false});

  @override
  State<Buddy> createState() => _BuddyState();
}

class _BuddyState extends State<Buddy> with TickerProviderStateMixin {
  AnimationController? _c;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(Buddy old) {
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
    if (c == null) return CustomPaint(size: box, painter: _OrbPainter(s, 0, widget.alert));
    return AnimatedBuilder(
      animation: c,
      builder: (_, _) => CustomPaint(size: box, painter: _OrbPainter(s, Curves.easeInOut.transform(c.value), widget.alert)),
    );
  }
}

class _OrbPainter extends CustomPainter {
  final int stage;
  final double t; // 0~1 숨
  final bool alert;
  final int? bodyStage; // 몸 색만 다른 단계로 (리포트 카드: 색은 카드 · 표정은 웃음)
  const _OrbPainter(this.stage, this.t, [this.alert = false, this.bodyStage]);

  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 100; // 그림 좌표 100 x 100 기준
    canvas.save();
    canvas.scale(u);

    // 숨: 가운데를 기준으로 아주 살짝 커졌다 작아짐 · 위아래로 1 만큼 떠오름
    canvas.translate(50, 50 - 1.2 * t);
    canvas.scale(1 + 0.02 * t);
    if (stage == 2 && !alert) canvas.rotate(-0.06); // 꾸벅
    canvas.translate(-50, -50);

    // 몸 — 반투명 단계 색 동그라미 · (경고 카드에서는) Headspace 처럼 밝은 왼쪽 위 → 진한 오른쪽 아래 그라데이션
    final body = Paint()..isAntiAlias = true;
    if (alert) {
      // (11/19) 왼쪽 위가 은은하게 밝은 둥근 그라데이션 — 납작하지 않고 자연스럽게
      body.shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        radius: 1.15,
        colors: AppIllust.orbGradient[bodyStage ?? stage],
      ).createShader(Rect.fromCircle(center: const Offset(50, 50), radius: 46));
    } else {
      body.color = AppIllust.orb(stage);
    }
    canvas.drawCircle(const Offset(50, 50), 46, body);

    final ink = Paint()
      ..color = AppIllust.ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;
    final inkFill = Paint()..color = AppIllust.ink..isAntiAlias = true;
    // 얼굴은 동그라미 윗부분에 (아래가 언덕에 가려져도 보이게)
    const l = Offset(39, 36), r = Offset(61, 36);

    if (alert && (stage == 1 || stage == 2)) {
      _alertFace(canvas, ink, inkFill, l, r);
      canvas.restore();
      return;
    }
    switch (stage) {
      case 0: // 편안 — 감은 눈 ‿ ‿ · 크게 웃는 입
        for (final e in [l, r]) {
          canvas.drawPath(Path()..moveTo(e.dx - 6, e.dy - 1)..quadraticBezierTo(e.dx, e.dy + 5, e.dx + 6, e.dy - 1), ink);
        }
        canvas.drawPath(Path()..moveTo(36, 46)..quadraticBezierTo(50, 58, 64, 46), ink);
      case 1: // 졸림 — 눈꺼풀이 반쯤 · 입 일자
        for (final e in [l, r]) {
          canvas.drawArc(Rect.fromCircle(center: e, radius: 4), 0, 3.1416, true, inkFill);
          canvas.drawLine(e.translate(-6, 0), e.translate(6, 0), ink);
        }
        canvas.drawLine(const Offset(44, 50), const Offset(56, 50), ink);
      case 2: // 꾸벅 — 처진 눈 · 작은 하품 · z
        for (final e in [l, r]) {
          canvas.drawPath(Path()..moveTo(e.dx - 6, e.dy + 1)..quadraticBezierTo(e.dx, e.dy + 5, e.dx + 6, e.dy + 1), ink);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 51), width: 7, height: 8), ink);
        _z(canvas, const Offset(78, 4), 9, ink);
        _z(canvas, const Offset(90, -6), 6, ink..strokeWidth = 2.6);
      default: // 3 긴급 — 놀란 눈 · 벌린 입
        for (final e in [l, r]) {
          canvas.drawCircle(e, 6, Paint()..color = Colors.white);
          canvas.drawCircle(e, 6, ink);
          canvas.drawCircle(e, 2.4, inkFill);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 53), width: 11, height: 9), inkFill);
    }
    canvas.restore();
  }

  /// (11/19 사용자 요청) 운행 화면 경고 얼굴 — 1단계 '어? 조심해요' · 2단계 '쉬어야 해요' (졸린 얼굴 대신)
  void _alertFace(Canvas canvas, Paint ink, Paint inkFill, Offset l, Offset r) {
    if (stage == 1) {
      // 걱정하는 얼굴 — 동그란 눈 · 안쪽이 올라간 눈썹 · 일자 입
      canvas.drawCircle(l, 3.6, inkFill);
      canvas.drawCircle(r, 3.6, inkFill);
      canvas.drawLine(const Offset(32, 27), const Offset(43, 24), ink);
      canvas.drawLine(const Offset(57, 24), const Offset(68, 27), ink);
      canvas.drawPath(Path()..moveTo(43, 51)..quadraticBezierTo(50, 48, 57, 51), ink);
    } else {
      // 걱정스럽게 경고하는 얼굴 (화난 얼굴 X) — 또렷한 눈 · 살짝 모인 짧은 눈썹 · 작게 시무룩한 입
      canvas.drawCircle(l, 3.8, inkFill);
      canvas.drawCircle(r, 3.8, inkFill);
      canvas.drawLine(const Offset(33, 25), const Offset(43, 27), ink);
      canvas.drawLine(const Offset(57, 27), const Offset(67, 25), ink);
      canvas.drawPath(Path()..moveTo(44, 53)..quadraticBezierTo(50, 49, 56, 53), ink);
    }
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
  bool shouldRepaint(_OrbPainter old) => old.stage != stage || old.t != t || old.alert != alert;
}

/// (11/19) Headspace 오늘 카드 위쪽 — 반투명 단계 색 하늘 + 동그란 해가 흰 언덕 뒤에서 떠오름
class BuddySky extends StatelessWidget {
  final int stage;
  final double height;
  const BuddySky({super.key, required this.stage, this.height = AppIllust.heroSky});

  @override
  Widget build(BuildContext context) {
    final orb = height * 0.78;
    // (11/19 사용자 요청) Headspace 오늘 카드 처음 모습 그대로 — 하늘 + 흰 언덕 뒤로 떠오르는 캐릭터
    return SizedBox(
      height: height,
      child: Stack(clipBehavior: Clip.hardEdge, alignment: Alignment.topCenter, children: [
        Positioned.fill(child: ColoredBox(color: AppIllust.sky(stage))),
        Positioned(top: height * 0.16, child: Buddy(stage: stage, size: orb)),
        // 흰 언덕 — 아래 흰 카드와 이어짐
        Positioned(left: 0, right: 0, bottom: 0, height: height * 0.36, child: CustomPaint(painter: _HillPainter())),
      ]),
    );
  }
}

class _HillPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()
      ..moveTo(0, h * 0.55)
      ..quadraticBezierTo(w / 2, -h * 0.45, w, h * 0.55)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(path, Paint()..color = Colors.white..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_HillPainter old) => false;
}

/// (11/19 사용자 요청 · Headspace '오늘의 명상' 카드) 그라데이션 카드 — 왼쪽에 글, 오른쪽 가장자리에 큰 캐릭터가 걸쳐 나옴
///   운행 · 경고 화면 카메라 아래 카드, 운행 리포트 맨 위 카드에 같이 씀
class HsCard extends StatelessWidget {
  final int stage; // 카드 · 캐릭터 색
  final int face; // 캐릭터 표정 (보통 stage 와 같음 · 리포트는 0 웃는 얼굴)
  final Widget child; // 왼쪽 글
  final double minHeight;
  final double orb; // 캐릭터 크기
  const HsCard({super.key, required this.stage, int? face, required this.child, this.minHeight = 132, this.orb = 172})
      : face = face ?? stage;

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: AppIllust.cardGradient[s]),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(alignment: Alignment.centerLeft, children: [
        // (11/19) 캐릭터 뒤 은은한 빛 — 카드 노랑과 캐릭터 주황이 자연스럽게 이어지게
        Positioned(
          right: -orb * 0.6,
          bottom: -orb * 0.7,
          child: Container(
            width: orb * 1.7,
            height: orb * 1.7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppIllust.orbGradient[s][0].withValues(alpha: 0.42),
                AppIllust.orbGradient[s][0].withValues(alpha: 0),
              ]),
            ),
          ),
        ),
        Positioned(right: -orb * 0.24, bottom: -orb * 0.36, child: _OrbOn(stage: s, face: face.clamp(0, 3), size: orb)),
        Padding(padding: EdgeInsets.fromLTRB(22, 20, orb * 0.66, 20), child: child),
      ]),
    );
  }
}

/// 카드용 캐릭터 — 몸 색은 카드 단계, 표정은 face 단계 (그라데이션 · 경고 표정)
class _OrbOn extends StatelessWidget {
  final int stage;
  final int face;
  final double size;
  const _OrbOn({required this.stage, required this.face, required this.size});
  @override
  Widget build(BuildContext context) =>
      face == stage ? Buddy(stage: stage, size: size, alert: true) : _Mixed(stage: stage, face: face, size: size);
}

class _Mixed extends StatelessWidget {
  final int stage;
  final int face;
  final double size;
  const _Mixed({required this.stage, required this.face, required this.size});
  @override
  Widget build(BuildContext context) => CustomPaint(size: Size(size, size), painter: _OrbPainter(face, 0, true, stage));
}
