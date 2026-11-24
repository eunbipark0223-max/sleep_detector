// ═══════════════════════════════════════════════════════════════
// widgets/system_status.dart — 시스템 상태 부품 (11/23 C · 기업용 리디자인)
// ═══════════════════════════════════════════════════════════════
// [왜] 기업 입장에서 "이 장치가 지금 제대로 돌아가나?" 를 한눈에 확인할 수 있어야 함 (Samsara Driver 홈의 장치 · 연결 상태 줄 참고)
//   - 상태는 색만으로 나타내지 않음 — 아이콘 + 글 + 색 함께 (색약 · 햇빛 아래에서도 읽히게)
//   - 실제로 확인하는 값만 보여 줌: 카메라 · 마이크 · 위치 권한 (휴대폰) / 관제 서버 연결 (운행 상태 요청 성공 여부)
//   - 장치 연결 · 감지 작동 · 졸음 감지(단계) 는 서로 다른 상태라 따로 보여 줌
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../theme.dart';
import 'stage_layout.dart' show DriveClock;

/// 점검 한 칸 — ok: true 정상 / false 문제 / null 확인 중
class SystemCheck {
  final IconData icon;
  final String label;
  final bool? ok;
  final String badText;
  const SystemCheck(this.icon, this.label, this.ok, {this.badText = '확인 필요'});
}

/// 작은 상태 알약 — [아이콘 · 글] + 연한 바탕
class StatusPill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool dot;
  const StatusPill(this.text, {super.key, required this.color, this.icon, this.dot = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(9, 5, 11, 5),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot)
            Container(width: 7, height: 7, decoration: BoxDecoration(color: color, shape: BoxShape.circle))
          else if (icon != null)
            Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(text, style: AppType.footnote.copyWith(fontWeight: FontWeight.w700, color: AppStatus.ink(color))),
        ]),
      );
}

/// 홈 맨 위 '시스템 상태' 카드 — 제목줄(종합 상태) + 점검 칸 4개
class SystemStatusCard extends StatelessWidget {
  final List<SystemCheck> checks;
  final bool driving;
  const SystemStatusCard({super.key, required this.checks, this.driving = false});

  @override
  Widget build(BuildContext context) {
    final loading = checks.any((c) => c.ok == null);
    final bad = checks.where((c) => c.ok == false).toList();
    final serverBad = checks.isNotEmpty && checks.last.ok == false;
    final (String text, Color color, IconData icon) = loading
        ? ('확인 중', AppStatus.offline, Icons.more_horiz_rounded)
        : serverBad
            ? ('서버 연결 끊김', AppStatus.danger, Icons.cloud_off_rounded)
            : bad.isNotEmpty
                ? ('권한 필요', AppStatus.caution, Icons.error_outline_rounded)
                : driving
                    ? ('운행 중', AppStatus.info, Icons.local_shipping_outlined) // 홈에서는 카메라가 꺼져 있어 '감지 중' 이 아님
                    : ('준비 완료', AppStatus.normal, Icons.check_circle_rounded);
    final note = serverBad
        ? '경고가 관리자에게 전달되지 않을 수 있어요'
        : bad.isNotEmpty
            ? '운행 시작을 누르면 권한을 받을 수 있어요'
            : '카메라로 졸음 신호를 살피고 위험하면 관리자에게 알려요';
    // (11/23 사용자 요청) 네모 칸 없이 state 처럼 — 제목줄 + 알약 하나에 4칸 (운행 중 알약과 같은 모양 · 칸 사이 세로선)
    // (11/23 사용자 요청) 방패 · '졸음 감지 시스템' 제목줄은 뺌 — 알약 칸만 맨 위에 (문제 있을 때만 아래 한 줄)
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // (11/23 사용자 요청) 상자 · 구분선 없이 체크 + 이름만 한 줄
      // (11/23 사용자 요청 · 보내 준 사진) 연한 알약 한 줄 · 초록 체크 + 이름 · 넉넉하게 (이모지 · 기기 아이콘 · 구분선 없음)
      FractionallySizedBox(
        widthFactor: 0.94, // (11/24 사용자 요청) 조금 더 길게 (다른 칸보다는 살짝 작게)
        child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(AppRadius.pill),
          border: Border.all(color: AppleGray.separator),
        ),
        child: Row(children: [for (final c in checks) Expanded(child: _CheckCell(c))]),
      ),
      ),
      if (serverBad || bad.isNotEmpty) ...[
        const SizedBox(height: 6),
        Row(children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Expanded(child: Text('$text · $note', style: AppType.caption.copyWith(fontWeight: FontWeight.w600, color: AppStatus.ink(color)))),
        ]),
      ],
    ]);
  }
}

class _CheckCell extends StatelessWidget {
  final SystemCheck c;
  const _CheckCell(this.c);

  @override
  Widget build(BuildContext context) {
    // (11/23 사용자 요청) 왼쪽 불 — 되면 파랑 · 안 되면 빨강 · 확인 중 회색
    // (11/23 사용자 요청) 정상 = 초록 체크 · 문제 = 빨간 느낌표 · 확인 중 = 회색
    // (11/23 사용자 요청) 초록 체크 + 이름 (문제면 빨간 느낌표 · 확인 중 회색)
    final col = c.ok == null ? AppStatus.offline : (c.ok! ? AppStatus.normal : AppStatus.danger);
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(c.ok == null ? Icons.more_horiz_rounded : (c.ok! ? Icons.check_circle_rounded : Icons.error_rounded), size: 15, color: col),
      const SizedBox(width: 5),
      Flexible(
        child: Text(c.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.caption.copyWith(fontWeight: FontWeight.w600, color: c.ok == false ? AppStatus.danger : AppColors.textSecondary)),
      ),
    ]);
  }
}

/// 방패 표시 — 스플래시 · 로그인 로고 (11/23 사용자 요청: 그림 대신 방패 이모지)
class ShieldMark extends StatelessWidget {
  final double size;
  const ShieldMark({super.key, this.size = 82});
  @override
  Widget build(BuildContext context) =>
      // (11/23 사용자 요청) 삼성 이모지(빨강 · 은색) 대신 브랜드 남색 방패 + 체크
      SizedBox(width: size, height: size, child: Icon(Icons.verified_user_rounded, size: size * 0.92, color: AppColors.navy));
}

/// (11/23 사용자 요청) 운행 · 경고 화면 위 상태 줄 — 한 칸에 다 담고, 격자처럼 세로 구분선으로 나눔
///   감지 | 단계 | 운전 시간 | 서버 연결 (3단계면 마지막 칸 = 관리자 알림 시각)
class DriveStatusStrip extends StatelessWidget {
  final bool online;
  final int stage;
  final DateTime? reportedAt; // 3단계 — 관리자에게 알린 시각
  const DriveStatusStrip({super.key, this.online = true, this.stage = 0, this.reportedAt});

  static const _names = ['정상', '주의', '휴식 권고', '긴급'];

  Widget _value(String text, {Color? dot, Color? color}) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (dot != null) ...[
            Container(width: 7, height: 7, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
            const SizedBox(width: 5),
          ],
          Text(text,
              style: AppType.subheadline.copyWith(
                  height: 1.2, fontWeight: FontWeight.w700, color: color ?? AppColors.textPrimary, fontFeatures: AppStatus.figures)),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    String two(int n) => n.toString().padLeft(2, '0');
    final s = stage.clamp(0, 3);
    // (11/23 사용자 요청) 운전 시간 | 감지 | 관제 서버 (3단계면 마지막 칸 = 관리자 알림 시각)
    final cells = <(String, Widget)>[
      (
        '운전 시간',
        ValueListenableBuilder<int?>(
          valueListenable: DriveClock.minutes,
          builder: (_, m, _) => _value(m == null ? '—' : DriveClock.label(m)),
        )
      ),
      ('감지', _value('작동 중', dot: AppStatus.normal)),
      reportedAt != null
          ? ('관리자 알림', _value('${two(reportedAt!.hour)}:${two(reportedAt!.minute)}', color: AppStatus.danger))
          : ('관제 서버', _value(online ? '연결됨' : '끊김', dot: online ? const Color(0xFF2A75D4) : AppStatus.danger, color: online ? null : AppStatus.danger)),
    ];
    final _ = s; // 단계는 아래 카드에 (위 칸에서는 뺌)
    return Container(
      height: 60,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppleGray.separator),
      ),
      child: Row(children: [
        for (var i = 0; i < cells.length; i++) ...[
          if (i > 0) const VerticalDivider(width: 1, thickness: 1, indent: 13, endIndent: 13, color: Color(0x1F1C2033)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(cells[i].$1, style: AppType.caption.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 3),
                cells[i].$2,
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}
