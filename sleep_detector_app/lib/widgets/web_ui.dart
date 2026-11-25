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
import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/material.dart';

import 'owl_says.dart' show keepWords;

import '../design_tokens.dart';
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
        color: AppleGray.fill, // (11/19) 따뜻한 톤
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppleGray.chevron, width: 1.2),
      ),
      child: Text(
        keepWords(label), // 단어 중간에서 줄이 안 나뉘게 ('이미 / 지' 방지)
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
  final double vPad; // (11/24) 세로 여백 — 운행 기록 타임라인은 얇게
  const StageBadge({super.key, required this.stage, this.text, this.fontSize = 12.5, this.vPad = 5});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final name = text ?? stageShortName(s);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: vPad),
      decoration: BoxDecoration(color: AppColors.stageTint(s), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 6, height: 6, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
        const SizedBox(width: 6),
        // 자리가 좁으면 넘치지 않고 '…' 로 줄임 (긴 이유 이름 · 좁은 화면)
        Flexible(
          child: Text(name, // (11/23 사용자 요청) 'n단계' 없이 점 + 이름
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: AppColors.stageInk(s))),
        ),
      ]),
    );
  }
}

/// (11/18 사용자 요청) 화면 글자에는 마침표를 쓰지 않는다 — 서버가 준 문장(AI 분석 · 안내)도 화면에 보일 때
///   끝 마침표는 지우고, 문장이 여러 개면 줄을 바꾼다. "A 했어요. B 해 주세요" → "A 했어요\nB 해 주세요"
String noDot(String text) => text
    .trim()
    .replaceAll(RegExp(r'\.\s+'), '\n')
    .replaceAll(RegExp(r'\.$'), '');

/// 단계 이름 (배지용 짧은 이름) — 관리자 웹과 같은 말
String stageShortName(int stage) {
  switch (stage.clamp(0, 3)) {
    case 1:
      return '주의';
    case 2:
      return '휴식 권고';
    case 3:
      return '긴급';
    default:
      return '정상';
  }
}

/// 큰 흰 카드
class WebCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;
  final bool outline; // (11/24) 홈 카드만 예전처럼 얇은 테두리 — 나머지는 슈퍼SOL 처럼 테두리 없이 그림자만
  const WebCard({super.key, required this.child, this.padding = const EdgeInsets.all(20), this.color = AppColors.card, this.outline = false});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        // (11/18 사용자 요청) 흰 바탕 위에서 그림자 대신 얇은 회색 테두리로 구분 (애플 · 관리자 웹 표 느낌)
        // (11/24 사용자 요청) 홈 카드처럼 — 흰색에서 오른쪽 아래로 아주 연한 파랑 · 얇은 테두리 · 옅은 그림자
        decoration: BoxDecoration(
          color: color == AppColors.card ? null : color,
          gradient: color == AppColors.card
              ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Colors.white, Color(0xFFF5F8FD)])
              : null,
          boxShadow: AppShadow.card,
          borderRadius: BorderRadius.circular(AppRadius.card), // (11/18 디자인 토큰) 앱 전체 카드 둥글기 하나
          border: Border.all(color: AppColors.cardBorder),
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
  final bool dropdown; // (11/24) 옆에 달력과 같은 ⌄ 아이콘 (눌러서 날짜 고르기)
  const StatItem(this.label, this.value, this.unit, {this.alert = false, this.dropdown = false});
}

/// 숫자 칸 여러 개 + 누른 칸 아래 남색 밑줄 (관리자 웹 홈)
class StatTabs extends StatelessWidget {
  final List<StatItem> items;
  final int selected;
  final ValueChanged<int>? onSelect;
  const StatTabs({super.key, required this.items, this.selected = 0, this.onSelect});

  @override
  Widget build(BuildContext context) {
    // (11/18 사용자 요청) 고른 칸 밑줄이 옆 칸으로 부드럽게 미끄러져 감
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth / items.length;
      return Stack(children: [
        Positioned(left: 0, right: 0, bottom: 0, child: Container(height: 1, color: AppColors.line)),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: AppMotion.curve,
          // (11/18 피드백) 밑줄은 칸 폭의 88% · 칸 가운데 · 끝이 둥글게
          left: w * selected + w * 0.06,
          width: w * 0.88,
          bottom: 0,
          child: Container(
              height: 2.5, decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(2))),
        ),
        _row(),
      ]);
    });
  }

  Widget _row() {
    return Row(children: [
      for (var i = 0; i < items.length; i++)
        Expanded(
          child: InkWell(
            onTap: onSelect == null ? null : () => onSelect!(i),
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
              // (11/18 피드백) 오늘 · 이번 주 · 긴급 — 칸 가운데 정렬
              child: items[i].value.isEmpty
                  // (11/23 사용자 요청) 숫자 없이 제목만 — 고른 칸은 진하게
                  ? Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(items[i].label,
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.subheadline.copyWith(
                                fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                                color: i == selected ? AppColors.textPrimary : AppColors.textSecondary)),
                      ),
                      // (11/24 사용자 요청) 운행 기록 달력 제목과 같은 ⌄ 아이콘 · 색은 옆 글자와 같게
                      if (items[i].dropdown)
                        Icon(Icons.keyboard_arrow_down_rounded, size: 20, color: i == selected ? AppColors.textPrimary : AppColors.textSecondary),
                    ])
                  : Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Text(items[i].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.footnote.copyWith(color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                  Text(items[i].value,
                      style: TextStyle(
                          fontSize: 28,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          color: items[i].alert ? AppColors.urgent : AppColors.textPrimary)),
                  const SizedBox(width: 3),
                  Text(items[i].unit, style: AppType.footnote.copyWith(color: AppColors.textMuted)),
                ]),
              ]),
            ),
          ),
        ),
    ]);
  }
}

/// (11/18 사용자 요청) 내용이 옆으로 부드럽게 미끄러지며 바뀌는 칸 — 홈 숫자 칸 목록 · 운행 기록 달력
///   index 가 커지면 오른쪽에서 들어오고, 작아지면 왼쪽에서 들어옴. 손가락으로 옆으로 밀면 onSwipe(+1 / -1)
class SlideSwitcher extends StatefulWidget {
  final int index;
  final Widget child;
  final ValueChanged<int>? onSwipe;
  const SlideSwitcher({super.key, required this.index, required this.child, this.onSwipe});

  @override
  State<SlideSwitcher> createState() => _SlideSwitcherState();
}

class _SlideSwitcherState extends State<SlideSwitcher> {
  int _dir = 1;

  @override
  void didUpdateWidget(covariant SlideSwitcher old) {
    super.didUpdateWidget(old);
    if (old.index != widget.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final current = ValueKey(widget.index);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: widget.onSwipe == null
          ? null
          : (d) {
              final v = d.primaryVelocity ?? 0;
              if (v.abs() < 250) return;
              widget.onSwipe!(v < 0 ? 1 : -1); // 왼쪽으로 밀면 다음
            },
      child: ClipRect(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: AppMotion.curve,
          alignment: Alignment.topCenter,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: AppMotion.curve,
            switchOutCurve: Curves.easeOutCubic,
            layoutBuilder: (cur, prev) => Stack(alignment: Alignment.topCenter, children: [...prev, ?cur]),
            transitionBuilder: (child, anim) {
              // 들어오는 칸: 미는 방향 반대편에서 · 나가는 칸: 미는 방향으로
              final incoming = child.key == current;
              final from = Offset(incoming ? _dir.toDouble() : -_dir.toDouble(), 0);
              return SlideTransition(
                position: Tween<Offset>(begin: from, end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: child),
              );
            },
            child: KeyedSubtree(key: current, child: widget.child),
          ),
        ),
      ),
    );
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


/// (11/24 사용자 요청) 앱의 모든 확인 창 = '정차하셨나요?' 창과 같은 아이폰 알림창
///   가운데 제목(20 · 굵게) · 회색 설명 · 아래 [왼쪽 회색 | 오른쪽 남색 굵게]
Future<bool> showAppConfirm(BuildContext context, {required String title, required String body, String cancel = '취소', required String ok, bool danger = false}) async {
  final yes = await showDialog<bool>(
    context: context,
    builder: (ctx) => CupertinoAlertDialog(
      title: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ),
      content: Text(body, style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary)),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.pop(ctx, false),
          textStyle: const TextStyle(fontSize: 18, color: AppColors.textSecondary),
          child: Text(cancel),
        ),
        CupertinoDialogAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx, true),
          textStyle: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: danger ? AppColors.danger : AppColors.navy),
          child: Text(ok),
        ),
      ],
    ),
  );
  return yes == true;
}
