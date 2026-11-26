// ═══════════════════════════════════════════════════════════════
// widgets/press.dart — 누르면 살짝 작아졌다 돌아오는 움직임 (11/18 C · 애플 버튼 느낌)
// ═══════════════════════════════════════════════════════════════
//   Press(child: 버튼) 로 감싸기만 하면 된다. 누르는 동안 96% 로 줄고, 떼면 부드럽게 원래 크기로
//   - Listener 라서 버튼의 눌림(onPressed · onTap)은 그대로 버튼이 받는다
//   - 손가락이 움직이면(목록 스크롤) 바로 원래 크기로 — 스크롤하다 카드가 작아진 채로 있지 않게
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/widgets.dart';

class Press extends StatefulWidget {
  final Widget child;
  final bool enabled; // 꺼진 버튼은 움직이지 않음
  final double scale;
  const Press({super.key, required this.child, this.enabled = true, this.scale = 0.96});

  @override
  State<Press> createState() => _PressState();
}

class _PressState extends State<Press> {
  bool _down = false;
  Offset? _start;

  void _set(bool v) {
    if (_down != v && mounted) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (e) {
        _start = e.position;
        _set(true);
      },
      onPointerMove: (e) {
        if (_start != null && (e.position - _start!).distance > 12) _set(false);
      },
      onPointerUp: (_) => _set(false),
      onPointerCancel: (_) => _set(false),
      child: AnimatedScale(
        scale: _down ? widget.scale : 1,
        duration: Duration(milliseconds: _down ? 110 : 220),
        curve: _down ? Curves.easeOut : Curves.easeOutBack,
        child: widget.child,
      ),
    );
  }
}
