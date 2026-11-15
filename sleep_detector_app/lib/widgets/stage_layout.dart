// ═══════════════════════════════════════════════════════════════
// widgets/stage_layout.dart — 운행 화면 · 경고 화면 공통 틀 (11/15 팀장)
// ═══════════════════════════════════════════════════════════════
// 모든 단계가 같은 자리 · 같은 크기:
//   ① (제목 줄은 AppBar — 가운데 제목 + 오른쪽 단계 배지 StageBadge)
//   ② 카메라: 화면 높이의 cameraRatio 로 고정 (단계가 바뀌어도 크기 · 위치 그대로, 테두리 색만 바뀜)
//   ③ 부엉이 말풍선 (남는 자리, 위쪽 정렬)
//   ④ 단계별 버튼 자리: 높이 actionsHeight 로 고정, 버튼은 아래에 붙음 (버튼이 적어도 카메라가 움직이지 않게)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../theme.dart';

class StageLayout extends StatelessWidget {
  final Widget camera;
  final Widget? cameraOverlay; // 카메라 위에 겹치는 띠 (카메라 확인 · 확인 중)
  final List<Widget> message; // 부엉이 말풍선 등
  final List<Widget> actions; // 단계별 버튼 (아래에 붙음)

  static const double cameraRatio = 0.40;
  static const double actionsHeight = 196;

  const StageLayout({
    super.key,
    required this.camera,
    this.cameraOverlay,
    required this.message,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final camH = (box.maxHeight * cameraRatio).clamp(180.0, 420.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: camH,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  camera,
                  if (cameraOverlay != null)
                    Positioned(left: 12, right: 12, top: 12, child: cameraOverlay!),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: message),
              ),
            ),
            SizedBox(
              height: actionsHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: actions,
              ),
            ),
          ],
        ),
      );
    });
  }
}

/// 단계 배지 '● 주의' — 제목 줄 오른쪽 (모든 단계 같은 자리). 빨강 바탕(3단계) 위에서는 흰 배지
class StageBadge extends StatelessWidget {
  final int stage;
  const StageBadge({super.key, required this.stage});

  static const List<String> labels = ['정상', '주의', '휴식 권고', '긴급'];

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final c = AppColors.stage(s);
    final onRed = s >= 3;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: onRed ? Colors.white : c.withValues(alpha: 0.20),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: onRed ? Colors.white : c.withValues(alpha: 0.55)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(labels[s],
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: onRed ? c : Color.lerp(c, Colors.white, 0.55))),
        ],
      ),
    );
  }
}
