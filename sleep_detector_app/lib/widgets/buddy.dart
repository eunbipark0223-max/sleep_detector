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
      builder: (_, _) {
        final t = Curves.easeInOut.transform(c.value);
        final paint = CustomPaint(size: box, painter: _OrbPainter(s, t, widget.alert));
        // (11/25 사용자 요청) 3단계 — 놀라서 위아래로 아주 조금 콩콩
        return s == 3 ? Transform.translate(offset: Offset(0, (t - 0.5) * widget.size * 0.07), child: paint) : paint;
      },
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
      case 1: // (11/23 사용자 요청) 주의 — 졸린 얼굴 대신 '앗, 조심!' 귀여운 얼굴
        _cautionFace(canvas, ink, inkFill, l, r);
      case 2: // (11/23 사용자 요청) 휴식 권고 — 자는 얼굴 대신 '어떡해, 쉬어요!' 귀여운 걱정 얼굴
        _restFace(canvas, ink, inkFill, l, r);
      default: // 3 긴급 — (11/19) 귀여운 깜짝 얼굴: 동그란 눈 + 반짝 · 위로 올라간 짧은 눈썹 · 작은 'o' 입 · 분홍 볼
        for (final e in [l, r]) {
          canvas.drawCircle(e, 4.6, inkFill);
          canvas.drawCircle(e.translate(-1.5, -1.6), 1.4, Paint()..color = Colors.white);
          canvas.drawPath(Path()..moveTo(e.dx - 5, e.dy - 10)..quadraticBezierTo(e.dx, e.dy - 14, e.dx + 5, e.dy - 10), ink);
        }
        canvas.drawOval(Rect.fromCenter(center: const Offset(50, 52), width: 8, height: 9), ink);
        canvas.drawCircle(const Offset(28, 46), 4.5, Paint()..color = const Color(0x66FFFFFF));
        canvas.drawCircle(const Offset(72, 46), 4.5, Paint()..color = const Color(0x66FFFFFF));
    }
    canvas.restore();
  }

  /// (11/23 사용자 요청) 2단계 휴식 권고 얼굴 — 반짝 동그란 눈 · 안쪽이 올라간 걱정 눈썹 · 물결 입 · 볼
  void _restFace(Canvas canvas, Paint ink, Paint inkFill, Offset l, Offset r) {
    for (final e in [l, r]) {
      canvas.drawCircle(e, 4.4, inkFill);
      canvas.drawCircle(e.translate(-1.4, -1.5), 1.4, Paint()..color = Colors.white);
    }
    canvas.drawLine(const Offset(33, 27), const Offset(43, 23.5), ink); // 걱정 눈썹 (안쪽이 위로)
    canvas.drawLine(const Offset(57, 23.5), const Offset(67, 27), ink);
    canvas.drawPath(Path()..moveTo(42, 51)..quadraticBezierTo(46, 47.5, 50, 51)..quadraticBezierTo(54, 54.5, 58, 51), ink); // 물결 입
    canvas.drawCircle(const Offset(29, 46), 4.5, Paint()..color = const Color(0x66FFFFFF));
    canvas.drawCircle(const Offset(71, 46), 4.5, Paint()..color = const Color(0x66FFFFFF));
  }

  /// (11/23 사용자 요청) 1단계 주의 얼굴 — 반짝이는 동그란 눈 · 살짝 올라간 짧은 눈썹 · 작은 미소 · 이마 옆 땀방울 · 볼
  void _cautionFace(Canvas canvas, Paint ink, Paint inkFill, Offset l, Offset r) {
    for (final e in [l, r]) {
      canvas.drawCircle(e, 4.4, inkFill);
      canvas.drawCircle(e.translate(-1.4, -1.5), 1.4, Paint()..color = Colors.white);
      canvas.drawPath(Path()..moveTo(e.dx - 5, e.dy - 9)..quadraticBezierTo(e.dx, e.dy - 12, e.dx + 5, e.dy - 9), ink);
    }
    canvas.drawPath(Path()..moveTo(44, 49)..quadraticBezierTo(50, 54, 56, 49), ink); // 작은 미소
    canvas.drawCircle(const Offset(29, 46), 4.5, Paint()..color = const Color(0x66FFFFFF)); // 볼
    canvas.drawCircle(const Offset(71, 46), 4.5, Paint()..color = const Color(0x66FFFFFF));
    // 땀방울 (오른쪽 이마) — 연한 하늘색
    final drop = Path()
      ..moveTo(76, 18)
      ..quadraticBezierTo(71, 26, 76, 29)
      ..quadraticBezierTo(81, 26, 76, 18)
      ..close();
    canvas.drawPath(drop, Paint()..color = const Color(0xFF8FC8F2));
  }

  /// (11/19 사용자 요청) 운행 화면 경고 얼굴 — 1단계 '어? 조심해요' · 2단계 '쉬어야 해요' (졸린 얼굴 대신)
  void _alertFace(Canvas canvas, Paint ink, Paint inkFill, Offset l, Offset r) {
    if (stage == 1) {
      _cautionFace(canvas, ink, inkFill, l, r); // (11/23) 홈 · 운행 화면 같은 얼굴
    } else {
      _restFace(canvas, ink, inkFill, l, r); // (11/23) 홈 · 운행 화면 같은 얼굴
    }
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
  final String? label; // (11/23) 왼쪽 위 작은 글 (달 · 날짜)
  final Widget? labelWidget; // (11/23) 왼쪽 위에 글 대신 넣을 것 (MY 달 고르기)
  final double? faceSize; // (11/24) 캐릭터 크기를 직접 (두 줄 글 높이에 맞춤)
  const HsCard({super.key, required this.stage, int? face, required this.child, this.minHeight = 132, this.orb = 172, this.label, this.labelWidget, this.faceSize})
      : face = face ?? stage;

  @override
  Widget build(BuildContext context) {
    // (11/23 리디자인_3) 홈 운행 카드와 같은 모양 — 흰색에서 아주 연한 단계 색 · 얇은 테두리 · 둥글기 16 ·
    //   캐릭터는 잘리지 않게 오른쪽에 작게 (빛 번짐 · 큰 캐릭터 걸침은 뺌)
    final s = stage.clamp(0, 3);
    // (11/23 사용자 요청) 카드 공통 — 왼쪽 연한 단계 색 → 오른쪽 흰색 · 구분선 없음
    //   왼쪽 위 작은 글(달 · 날짜) / 아래 큰 글 · 캐릭터는 맨 오른쪽이 아니라 글이 끝나는 바로 옆
    final size = faceSize ?? (orb * 0.36).clamp(48.0, 60.0);
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppleGray.separator),
        gradient: LinearGradient(colors: [AppIllust.softTint[s], Colors.white]),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (labelWidget != null || label != null) ...[
          // (11/24 사용자 요청) 숫자 '1' 의 왼쪽 여백만큼 살짝 당겨 아래 '졸음 경고' 와 같은 시작선
          Transform.translate(
            offset: const Offset(-0.8, 0),
            child: labelWidget ?? Text(label!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppleGray.label)),
          ),
          const SizedBox(height: 10),
        ],
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(child: child),
          const SizedBox(width: 14),
          _OrbOn(stage: s, face: face.clamp(0, 3), size: size),
        ]),
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
