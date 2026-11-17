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
  final Widget? header; // (11/16 R안) 카메라 위 — 단계 점 · 이름 + 큰 제목 (StageHeader)

  static const double cameraRatio = 0.40;
  static const double actionsHeight = 196;

  const StageLayout({
    super.key,
    required this.camera,
    this.cameraOverlay,
    required this.message,
    required this.actions,
    this.header,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final camH = (box.maxHeight * (header == null ? cameraRatio : 0.36)).clamp(180.0, 420.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null) ...[header!, const SizedBox(height: 18)],
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
            const SizedBox(height: 18),
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(), // 스크롤바는 안 보임 (사용자 요청 7)
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

/// (11/16 R안 · readdy) 운행 · 경고 화면 머리 — '● 주의' 작은 글 + 큰 제목 (단계 파스텔 바탕 위 검정 글자)
class StageHeader extends StatelessWidget {
  final int stage;
  final String title;
  const StageHeader({super.key, required this.stage, required this.title});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Text(StageBadge.labels[s],
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
        const SizedBox(height: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 34, height: 1.15, fontWeight: FontWeight.w800, letterSpacing: -1, color: AppColors.textPrimary)),
      ],
    );
  }
}

/// 운행 · 경고 화면 아래 문장 (readdy) — 부엉이 말풍선 대신 큰 글. 마침표는 뺌 (사용자 요청 6)
class StageMessage extends StatelessWidget {
  final String text;
  const StageMessage(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(text.replaceAll('.', '').replaceAll('\n\n', '\n'),
        style: const TextStyle(fontSize: 21, height: 1.45, fontWeight: FontWeight.w500, color: AppColors.textPrimary));
  }
}

/// 운행 · 경고 화면 큰 버튼 (readdy) — kind: 'white'(흰 반투명 + 남색 글) · 'navy'(남색 꽉 참)
ButtonStyle stageButton(String kind, {double height = 64}) => FilledButton.styleFrom(
      backgroundColor: kind == 'navy' ? AppColors.navy : Colors.white.withValues(alpha: 0.7),
      foregroundColor: kind == 'navy' ? Colors.white : AppColors.navy,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
      disabledForegroundColor: AppColors.navy.withValues(alpha: 0.4),
      minimumSize: Size.fromHeight(height),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      textStyle: const TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
    );

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
