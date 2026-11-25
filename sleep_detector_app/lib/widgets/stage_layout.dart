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
    this.headerInset = 12,
    this.gap = 26,
  });
  final double headerInset; // (11/23) 머리 칸 좌우 들여쓰기 — 상태 줄은 0 (카메라와 같은 폭)
  final double gap; // (11/23) 카메라와 카드 사이

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final camH = (box.maxHeight * (camRatio ?? (header == null ? cameraRatio : 0.36))).clamp(180.0, 560.0);
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 0), // (11/24 사용자 요청) 상태 줄 더 위로 · 아래 버튼 조금 더 아래로 (모든 운행 화면 같은 자리) // (11/23 사용자 요청) 상태 줄은 위로 · 맨 아래 버튼은 조금 위로 (세 화면 같은 자리)
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (11/18 피드백) 글은 카메라 둥근 모서리 안쪽에서 시작 (좌우 12 들여씀)
            if (header != null) ...[Padding(padding: EdgeInsets.symmetric(horizontal: headerInset), child: header!), SizedBox(height: headerInset == 0 ? 10 : 18)],
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
            SizedBox(height: gap), // (11/19 사용자 요청) 카메라와 카드 사이 여백 넉넉히
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
  final String? sub; // (11/24 사용자 요청) 2단계 — 카드 안 아래 작은 한 줄 (가까운 졸음쉼터)
  const StageMessage(this.text, {super.key, this.stage = 0, this.info = false, this.sub});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final lines = titleLines(text).take(2).map((l) => l.replaceAll(RegExp(r'[.。]\s*$'), '')).toList(); // (11/24) 마침표 없음
    // (11/23 사용자 요청) 운행 화면 카드도 처음 홈 카드처럼 — 단색 카드는 캐릭터가 안 보여서
    //   흰색 → 아주 연한 단계 색 · 얇은 테두리 / 왼쪽 위 상태 알약 · 큰 글 / 오른쪽 캐릭터
    final c = AppIllust.stageSolid[s]; // (11/23 사용자 요청) 0단계는 초록 (3단계 빨강처럼)
    const names = ['정상', '주의', '휴식 권고', '긴급'];
    const title = TextStyle(fontSize: 22, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppleGray.label);
    return Container(
      height: 132, // (11/23 사용자 요청) 0 · 1 · 2 · 3단계 카드 크기 모두 같게
      padding: const EdgeInsets.fromLTRB(20, 14, 16, 14), // (11/24) 알약이 카드 맨 위에 붙게
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        // (11/24) 흰 카드 · 테두리 없이 부드러운 그림자
        color: Colors.white,
        boxShadow: AppShadow.card,
      ),
      // (11/25 사용자 요청) 캐릭터를 큰 글 두 줄 바로 옆에 — 캐릭터 세로 길이 = 두 줄 높이, 두 줄과 같은 가운데
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding: const EdgeInsets.fromLTRB(9, 2, 11, 2), // (11/24 사용자 요청) 세로 조금 줄임
              decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(width: 7, height: 7, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
                const SizedBox(width: 5),
                Text(names[s], // (11/23 사용자 요청) '2단계' 없이 점 + 이름
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color.lerp(c, AppleGray.label, 0.25))),
              ]),
            ),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final (i, line) in lines.indexed) ...[
                        if (i > 0) const SizedBox(height: 4), // 줄 사이 한 칸
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(line, maxLines: 1, softWrap: false, style: title),
                        ),
                      ],
                    ]),
                  ),
                  const SizedBox(width: 12),
                  // 두 줄 높이 = 22 × 1.3 × 2 + 줄 사이 4 ≈ 61
                  Buddy(stage: s, size: 61, breathe: s > 0, alert: true),
                ]),
                if (sub != null) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    const Icon(Icons.location_on_rounded, size: 16, color: AppColors.navy),
                    const SizedBox(width: 4),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(sub!, maxLines: 1, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ),
                  ]),
                ],
              ]),
            ),
          ]),
    );
  }
}

/// (11/25 사용자 요청) 2 · 3단계 [쉼터 안내 | 정차했어요] — 남는 자리를 써서 더 크게
ButtonStyle stageButtonBig(String kind) => stageButton(kind).copyWith(
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(68)),
      textStyle: const WidgetStatePropertyAll(TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
      iconSize: const WidgetStatePropertyAll(24),
    );

/// 운행 · 경고 화면 큰 버튼 (readdy) — kind: 'white'(흰 반투명 + 남색 글) · 'navy'(남색 꽉 참)
ButtonStyle stageButton(String kind, {double height = AppSize.button}) => FilledButton.styleFrom(
      backgroundColor: kind == 'navy' ? AppColors.navy : Colors.white,
      foregroundColor: kind == 'navy' ? Colors.white : AppColors.navy,
      disabledBackgroundColor: Colors.white.withValues(alpha: 0.4),
      disabledForegroundColor: AppColors.navy.withValues(alpha: 0.4),
      minimumSize: const Size.fromHeight(AppSize.button), // (11/23) 높이는 앱 전체 하나
      elevation: 0,
      side: kind == 'navy' ? null : const BorderSide(color: AppleGray.separator), // (v2) 흰 버튼은 얇은 테두리
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)), // (11/23 Headspace 토큰) 알약 버튼
      textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700), // (11/23) AuthButton 과 같은 글자
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

/// (11/23 사용자 요청) 두 줄 제목 규칙 — 문장마다 한 줄 · 줄이 둘 이상이면 마지막 줄 끝에 마침표
///   관리자에게 알렸어요
///   지금 바로 정차하세요.
List<String> titleLines(String text) {
  final l = text.replaceAll('.', '\n').split('\n').map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
  if (l.length > 1) l[l.length - 1] = '${l.last}.';
  return l;
}
