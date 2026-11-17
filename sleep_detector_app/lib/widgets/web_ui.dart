// ═══════════════════════════════════════════════════════════════
// widgets/web_ui.dart — 관리자 웹(졸음가드 관리자)과 같은 모양의 공용 부품 (11/17 C)
// ═══════════════════════════════════════════════════════════════
//   - ImageSlot   : 캐릭터 · 로고 그림이 들어갈 자리 (아직 그림 안 넣음 → 네모 + 글자로 자리만 표시)
//   - StageBadge  : '● 3단계 | 위험' 연한 단계 색 알약 배지
//   - WebCard     : 큰 흰 카드 (모서리 22)
//   - StatTabs    : 숫자 칸 여러 개 — 누른 칸 아래에 남색 밑줄 (관리자 웹 홈 위쪽)
//   - WebHeader   : 위 머리줄 [로고] 졸음가드 · ● LIVE
//   - TimelineRow : 시각 | 단계 색 세로 막대 | 제목 · 단계 (경고 기록 한 줄)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../theme.dart';

/// 그림 자리 — 캐릭터 이미지 · 로고가 정해지면 이 자리에 넣는다 (사용자 규칙 11/17)
class ImageSlot extends StatelessWidget {
  final String label; // '메인 캐릭터 이미지' · '캐릭터 이미지' · '로고'
  final double width;
  final double height;
  final double radius;
  const ImageSlot({super.key, required this.label, this.width = 64, this.height = 64, this.radius = 12});

  /// 로고 자리
  const ImageSlot.logo({super.key, double size = 40})
      : label = '로고',
        width = size,
        height = size,
        radius = 10;

  @override
  Widget build(BuildContext context) {
    final small = width < 70 || height < 50;
    return Container(
      width: width,
      height: height,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0xFFB9BFCD), width: 1.2),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        maxLines: 3,
        overflow: TextOverflow.fade,
        style: TextStyle(
            fontSize: small ? 9.5 : 12.5, height: 1.25, fontWeight: FontWeight.w600, color: const Color(0xFF8A90A0)),
      ),
    );
  }
}

/// 단계 알약 배지 — '● 2단계 | 휴식 권고'. text 를 주면 단계 이름 대신 그 글 (예: '피로 누적')
class StageBadge extends StatelessWidget {
  final int stage;
  final String? text;
  final double fontSize;
  const StageBadge({super.key, required this.stage, this.text, this.fontSize = 12.5});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final name = text ?? stageShortName(s);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.stageTint(s), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        // 자리가 좁으면 넘치지 않고 '…' 로 줄임 (긴 이유 이름 · 좁은 화면)
        Flexible(
          child: Text(s == 0 ? name : '$s단계 | $name',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: AppColors.stageInk(s))),
        ),
      ]),
    );
  }
}

/// 단계 이름 (배지용 짧은 이름) — 관리자 웹과 같은 말
String stageShortName(int stage) {
  switch (stage.clamp(0, 3)) {
    case 1:
      return '주의';
    case 2:
      return '휴식 권고';
    case 3:
      return '위험';
    default:
      return '정상';
  }
}

/// 큰 흰 카드
class WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  const WebCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = AppColors.card});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(22),
          boxShadow: const [BoxShadow(color: Color(0x0A1F2A5C), blurRadius: 12, offset: Offset(0, 2))],
        ),
        child: child,
      );
}

/// 숫자 칸 하나
class StatItem {
  final String label;
  final String value;
  final String unit;
  final bool alert; // 빨간 숫자
  const StatItem(this.label, this.value, this.unit, {this.alert = false});
}

/// 숫자 칸 여러 개 + 누른 칸 아래 남색 밑줄 (관리자 웹 홈)
class StatTabs extends StatelessWidget {
  final List<StatItem> items;
  final int selected;
  final ValueChanged<int>? onSelect;
  const StatTabs({super.key, required this.items, this.selected = 0, this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < items.length; i++)
        Expanded(
          child: InkWell(
            onTap: onSelect == null ? null : () => onSelect!(i),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 14),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: i == selected ? AppColors.navy : AppColors.line, width: i == selected ? 2.5 : 1),
                ),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(items[i].value,
                      style: TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: items[i].alert ? AppColors.urgent : AppColors.textPrimary)),
                  const SizedBox(width: 3),
                  Text(items[i].unit, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// 위 머리줄 — [로고] 졸음가드 · ● LIVE   (오른쪽에 trailing)
class WebHeader extends StatelessWidget {
  final bool live;
  final Widget? trailing;
  const WebHeader({super.key, this.live = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      const ImageSlot.logo(size: 32),
      const SizedBox(width: 10),
      const Text('졸음가드', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      if (live) ...[
        const SizedBox(width: 10),
        Container(width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        const Text('LIVE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.live)),
      ],
      const Spacer(),
      if (trailing != null) trailing!,
    ]);
  }
}

/// 경고 기록 한 줄 — '17:44 ┃ 피로 누적 / 3단계 | 위험'
class TimelineRow extends StatelessWidget {
  final String time;
  final int stage;
  final String title;
  final VoidCallback? onTap;
  const TimelineRow({super.key, required this.time, required this.stage, required this.title, this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              width: 46,
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(time, style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
              ),
            ),
            Container(width: 3, decoration: BoxDecoration(color: AppColors.stage(s), borderRadius: BorderRadius.circular(2))),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(s == 0 ? stageShortName(s) : '$s단계 | ${stageShortName(s)}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
              ]),
            ),
            if (onTap != null) const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
          ]),
        ),
      ),
    );
  }
}
