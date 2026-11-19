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

import '../design_tokens.dart';
import '../theme.dart';
import 'buddy.dart';

class StageLayout extends StatelessWidget {
  final Widget camera;
  final Widget? cameraOverlay; // 카메라 위에 겹치는 띠 (카메라 확인 · 확인 중)
  final List<Widget> message; // 부엉이 말풍선 등
  final List<Widget> actions; // 단계별 버튼 (아래에 붙음)
  final Widget? header; // (11/16 R안) 카메라 위 — 단계 점 · 이름 + 큰 제목 (StageHeader)

  static const double cameraRatio = 0.40;
  // (11/19 사용자 요청) 화면마다 카메라 크기 · 버튼 칸 높이를 따로 — 운행 화면은 버튼이 하나라 카메라를 크게
  final double? camRatio; // 카메라 높이 = 화면 높이 x 이 값 (없으면 머리줄 있을 때 0.36 · 없을 때 0.40)
  final double actionsHeight; // 아래 버튼 칸 높이 (버튼 3개 경고 화면 196 · 버튼 1개 운행 화면 76)

  const StageLayout({
    super.key,
    required this.camera,
    this.cameraOverlay,
    required this.message,
    required this.actions,
    this.header,
    this.camRatio,
    this.actionsHeight = 196,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final camH = (box.maxHeight * (camRatio ?? (header == null ? cameraRatio : 0.36))).clamp(180.0, 560.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8), // (11/19) 아래 버튼을 조금 더 아래로
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (11/18 피드백) 글은 카메라 둥근 모서리 안쪽에서 시작 (좌우 12 들여씀)
            if (header != null) ...[Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: header!), const SizedBox(height: 18)],
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
            const SizedBox(height: 26), // (11/19 사용자 요청) 카메라와 카드 사이 여백 넉넉히
            Expanded(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(), // 스크롤바는 안 보임 (사용자 요청 7)
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: message), // (11/19) 카드가 카메라와 같은 폭
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
/// (11/18 피드백) 지금 운행 상태 — 몇 분째 운전 중인지. 운행 화면이 서버 ping(drive_min)을 받을 때마다 넣는다 (운행이 아니면 null)
class DriveClock {
  DriveClock._();
  static final ValueNotifier<int?> minutes = ValueNotifier<int?>(null);
  static String label(int m) => m >= 60 ? '${m ~/ 60}시간 ${m % 60}분' : '$m분';
}

/// (11/19 사용자 요청) 운행 · 경고 화면 맨 위 '운행 중' — 작고 차분하게 (단계 · 운전 시간은 아래 카드에)
class DriveTopTitle extends StatelessWidget {
  final String text;
  const DriveTopTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.live, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppleGray.label)),
        ]),
      );
}

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
          const Spacer(),
          // 오른쪽 위 작은 알약 — '🕒 1시간 20분 운전 중' (반투명 흰 바탕이라 단계 색 바탕 위에서도 잘 보임)
          ValueListenableBuilder<int?>(
            valueListenable: DriveClock.minutes,
            builder: (_, m, _) => m == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
                    // (11/18 피드백) 글자색 통일 — 보조 정보('정상' · 운전 시간)는 회색, 제목 · 문장은 검정, 버튼만 남색
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textSecondary),
                      const SizedBox(width: 5),
                      Text('${DriveClock.label(m)} 운전 중',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                    ]),
                  ),
          ),
        ]),
        const SizedBox(height: 8),
        // (11/18 피드백) 덜 굵게 · 진회색 — 눈 기준 측정 화면과 같은 톤
        Text(title,
            style: const TextStyle(
                fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppleGray.softLabel)),
      ],
    );
  }
}

/// (11/19 사용자 요청 · Headspace '오늘의 명상' 카드) 운행 · 경고 화면 카메라 아래 카드
///   왼쪽: 큰 글(두 줄까지) · '● 휴식 권고' · '🕒 1시간 20분 운전 중'  /  오른쪽 가장자리: 경고 표정 캐릭터가 걸쳐 나옴
///   info=false 면 큰 글만 (경고 화면은 위 머리줄에 단계가 이미 있음)
class StageMessage extends StatelessWidget {
  final String text;
  final int stage;
  final bool info;
  const StageMessage(this.text, {super.key, this.stage = 0, this.info = false});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final lines = text
        .replaceAll('.', '\n')
        .split('\n')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(2)
        .toList();
    const title = TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppleGray.label);
    return HsCard(
      stage: s,
      minHeight: info ? 140 : 116,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (final line in lines)
          // 한 문장은 꼭 한 줄 — 폭이 모자라면 글자만 조금 줄어듦
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(line, maxLines: 1, softWrap: false, style: title),
          ),
        if (info) ...[
          // (11/19 사용자 요청) 운전 시간 먼저 · 단계 알약 다음 — 두 알약 모양 · 안쪽 시작선을 똑같이 맞춤
          ValueListenableBuilder<int?>(
            valueListenable: DriveClock.minutes,
            builder: (_, m, _) => m == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: _CardChip(
                      lead: const Icon(Icons.schedule_rounded, size: 14, color: Color(0xB32D2C2B)),
                      text: '${DriveClock.label(m)} 운전 중',
                      bg: Colors.white.withValues(alpha: 0.55),
                      color: const Color(0xD92D2C2B),
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          _CardChip(
            lead: Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
            text: s >= 1 ? '$s단계 | ${StageBadge.labels[s]}' : '안전 운전 중',
            bg: s >= 1 ? AppColors.stageTint(s) : Colors.white.withValues(alpha: 0.55),
            color: s >= 1 ? AppColors.stageInk(s) : const Color(0xD92D2C2B),
          ),
        ],
      ]),
    );
  }
}

/// 카드 안 작은 알약 — 왼쪽 14 칸(아이콘 · 점) + 글. 두 알약의 글 시작선이 같음
class _CardChip extends StatelessWidget {
  final Widget lead;
  final String text;
  final Color bg;
  final Color color;
  const _CardChip({required this.lead, required this.text, required this.bg, required this.color});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 12, 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(width: 14, child: Center(child: lead)),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: -0.2, color: color)),
        ]),
      );
}

/// 운행 · 경고 화면 큰 버튼 (readdy) — kind: 'white'(흰 반투명 + 남색 글) · 'navy'(남색 꽉 참)
ButtonStyle stageButton(String kind, {double height = 64}) => FilledButton.styleFrom(
      backgroundColor: kind == 'navy' ? AppColors.navy : Colors.white.withValues(alpha: 0.7),
      foregroundColor: kind == 'navy' ? Colors.white : AppColors.navy,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
      disabledForegroundColor: AppColors.navy.withValues(alpha: 0.4),
      minimumSize: Size.fromHeight(height),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)), // (11/18) 카메라 칸과 같은 둥글기
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
