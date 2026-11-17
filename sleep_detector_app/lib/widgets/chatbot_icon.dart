// ═══════════════════════════════════════════════════════════════
// widgets/chatbot_icon.dart — 홈 오른쪽 위 규정 도우미 버튼 아이콘 (11/17 C)
// ═══════════════════════════════════════════════════════════════
//   로봇 얼굴(가만히) ↔ 말풍선 안 점 세 개가 통통 튀는 '입력 중…' 을 번갈아 보여 준다
//   → 챗봇이 말을 걸려는 것처럼 보이게 (사용자 요청)
//   로봇 2.6초 → 말풍선 2.4초 → 로봇 … (부드럽게 바뀜)
// ═══════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

class ChatbotIcon extends StatefulWidget {
  final double size;
  final Color color;
  const ChatbotIcon({super.key, this.size = 26, this.color = AppColors.textPrimary});

  @override
  State<ChatbotIcon> createState() => _ChatbotIconState();
}

class _ChatbotIconState extends State<ChatbotIcon> with SingleTickerProviderStateMixin {
  late final AnimationController _dots =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  Timer? _timer;
  bool _typing = false;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  void _schedule() {
    _timer = Timer(Duration(milliseconds: _typing ? 2400 : 2600), () {
      if (!mounted) return;
      setState(() => _typing = !_typing);
      _schedule();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _dots.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return SizedBox(
      width: s,
      height: s,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) =>
            FadeTransition(opacity: anim, child: ScaleTransition(scale: Tween(begin: 0.8, end: 1.0).animate(anim), child: child)),
        child: _typing
            ? _Bubble(key: const ValueKey('typing'), size: s, color: widget.color, dots: _dots)
            : Icon(Icons.smart_toy_outlined, key: const ValueKey('robot'), size: s, color: widget.color),
      ),
    );
  }
}

/// 말풍선 + 점 세 개 (차례로 위아래로 통통)
class _Bubble extends StatelessWidget {
  final double size;
  final Color color;
  final Animation<double> dots;
  const _Bubble({super.key, required this.size, required this.color, required this.dots});

  @override
  Widget build(BuildContext context) {
    final w = size;
    final h = size * 0.78;
    final dot = size * 0.13;
    return Center(
      child: Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(h * 0.45),
            topRight: Radius.circular(h * 0.45),
            bottomRight: Radius.circular(h * 0.45),
            bottomLeft: Radius.circular(h * 0.12), // 왼쪽 아래만 덜 둥글게 = 말풍선 꼬리 느낌
          ),
        ),
        child: AnimatedBuilder(
          animation: dots,
          builder: (context, _) => Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: dot * 0.35),
                  child: Transform.translate(
                    // 점마다 시작을 조금씩 늦춰서 물결처럼
                    offset: Offset(0, -math.max(0, math.sin((dots.value - i * 0.18) * 2 * math.pi)) * dot * 0.9),
                    child: Container(width: dot, height: dot, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
