// ═══════════════════════════════════════════════════════════════
// widgets/home_ui.dart — 홈 화면 디자인 부품 (Figma 시안 '졸음운전 감지 앱2' 홈)
// ═══════════════════════════════════════════════════════════════
// 디자인만 담당 — 단계 계산 · 서버 호출은 home_screen 이 그대로 가진다
//   - HomeStateCard      : 남색 '지금 상태' 카드 (단계 배지 · 큰 글 · 부엉이 · 흰 [운행 시작])
//   - HomeSectionHeading : 굵은 소제목 + 오른쪽 작은 글/버튼
//   - HomeReadyTile      : 출발 준비 칸 (아이콘 · 이름 · 상태 · 초록 체크)
//   - HomeEmptyCard      : 흰 카드 + 작은 부엉이 + 안내
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../models/sleep_event.dart';
import '../stage_texts.dart';
import '../theme.dart';
import 'owl_says.dart';

/// 남색 '지금 상태' 카드 (시안 .current-state-card)
class HomeStateCard extends StatelessWidget {
  final int stage;
  final VoidCallback onStart;
  final String startLabel; // 진행 중인 운행이 있으면 '새로 운행 시작' ([이어서 운행]과 헷갈리지 않게, 11/12)
  const HomeStateCard({super.key, required this.stage, required this.onStart, this.startLabel = '운행 시작'});

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    final stageColor = AppColors.stage(s);
    // 0단계는 시안 문구, 1 ~ 3단계는 경고 화면 · 음성과 같은 문구 (stage_texts)
    final small = s == 0 ? '오늘도 안전하게' : '지금 단계';
    final big = s == 0 ? '안전 운전\n중이에요' : StageTexts.headline(s);
    final sub = s == 0 ? '편안한 운전을\n도와드릴게요' : null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: const Color(0xFF334275)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26366D), AppColors.navy],
          stops: [0, 0.68],
        ),
        boxShadow: const [BoxShadow(color: Color(0x2B1F2A5C), blurRadius: 32, offset: Offset(0, 14))],
      ),
      child: Stack(
        children: [
          // 오른쪽 위 은은한 동그라미 (시안 ::before)
          Positioned(
            top: -60,
            right: -42,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x13FFFFFF)),
                boxShadow: const [BoxShadow(color: Color(0x08FFFFFF), spreadRadius: 28)],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(15),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Text('지금 상태',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFFC9D1EE))),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: stageColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: stageColor.withValues(alpha: 0.35)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: stageColor, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          Text(SleepEvent.stageLabels[s],
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Color.lerp(stageColor, Colors.white, 0.55))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(small,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFAEBBE2))),
                            const SizedBox(height: 4),
                            Text(big,
                                maxLines: 4,
                                style: TextStyle(
                                    fontSize: s == 0 ? 27 : 20,
                                    height: 1.28,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -1,
                                    color: Colors.white)),
                            if (sub != null) ...[
                              const SizedBox(height: 7),
                              Text(sub,
                                  style: const TextStyle(fontSize: 12, height: 1.45, color: Color(0xFFBFC9E8))),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Container(
                      width: 142,
                      height: 150,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        boxShadow: [BoxShadow(color: Color(0x420B1234), blurRadius: 15, offset: Offset(0, 10))],
                        shape: BoxShape.circle,
                      ),
                      child: Image.asset(OwlSays.body(s), width: 150, height: 150, fit: BoxFit.contain),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: const [BoxShadow(color: Color(0x3D0B1234), blurRadius: 18, offset: Offset(0, 8))],
                  ),
                  child: ElevatedButton.icon(
                    onPressed: onStart,
                    icon: const Icon(Icons.photo_camera_outlined, size: 22),
                    label: Text(startLabel, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.navy,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 굵은 소제목 + 오른쪽 (시안 .section-heading)
class HomeSectionHeading extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const HomeSectionHeading({super.key, required this.title, this.trailing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 출발 준비 칸 (시안 .ready-grid > div)
class HomeReadyTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String sub;
  const HomeReadyTile({super.key, required this.icon, required this.title, required this.sub});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: const Color(0xFFEDF0F8), borderRadius: BorderRadius.circular(11)),
            child: Icon(icon, size: 19, color: AppColors.navy),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(sub, style: const TextStyle(fontSize: 11, color: AppColors.textMuted)),
              ],
            ),
          ),
          Container(
            width: 19,
            height: 19,
            decoration: const BoxDecoration(color: AppColors.normal, shape: BoxShape.circle),
            child: const Icon(Icons.check, size: 13, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

/// 출발 준비 줄 (시안 '졸음운전 감지 앱4' .ready-section — 제목 + 카메라 | 음성 안내 알약)
///   허용된 칸은 초록 (연초록 바탕 · 초록 체크), 아직이면 회색. 누르면 [onTap] (권한 받기)
class HomeReadyRow extends StatelessWidget {
  final bool camera;
  final bool voice;
  final VoidCallback onTap;
  const HomeReadyRow({super.key, required this.camera, required this.voice, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final all = camera && voice;
    Widget half(String text, bool ok, {required bool left}) {
      final fg = ok ? const Color(0xFF257B49) : const Color(0xFF7D8497);
      return Expanded(
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: ok ? const Color(0xFFE8F5ED) : const Color(0xFFE7E9EE),
            borderRadius: left
                ? const BorderRadius.horizontal(left: Radius.circular(10))
                : const BorderRadius.horizontal(right: Radius.circular(10)),
            border: left
                ? null
                : Border(left: BorderSide(color: all ? const Color(0xFFBCDCC7) : const Color(0xFFCDD1DA))),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: fg)),
              const SizedBox(width: 5),
              Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                    color: ok ? AppColors.normal : const Color(0xFFA8ADBA), shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 48,
      child: Row(
        children: [
          const Text('출발 준비', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              button: true,
              label: all ? '카메라와 음성 안내 권한 허용됨' : '카메라와 음성 안내 권한 허용하기',
              excludeSemantics: true,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: all ? const Color(0xFFE8F5ED) : const Color(0xFFE7E9EE),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: all ? const Color(0xFFBFE2CB) : const Color(0xFFD6DAE4)),
                    ),
                    child: Row(
                      children: [
                        half('카메라', camera, left: true),
                        half('음성 안내', voice, left: false),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 흰 카드 + 작은 부엉이 + 안내 (시안 .empty-state)
class HomeEmptyCard extends StatelessWidget {
  final String title;
  final String? sub;
  final String? actionText;
  final VoidCallback? onAction;
  const HomeEmptyCard({super.key, required this.title, this.sub, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Image.asset(OwlSays.body(0), width: 58, height: 58),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
          if (actionText != null) TextButton(onPressed: onAction, child: Text(actionText!)),
        ],
      ),
    );
  }
}

/// 권한 안내창 (Figma 시안 '졸음운전 감지 앱3' 위치 권한 — 아래에서 올라오는 흰 창, 11/12 카메라 · 마이크도 함께)
/// [계속] → true (그다음 휴대폰의 실제 권한 창이 카메라 → 마이크 → 위치 순서로 연달아 뜸), 바깥을 눌러 닫으면 null
Future<bool?> showPermissionSheet(BuildContext context,
    {bool camera = false, bool mic = false, bool location = false}) {
  final names = [if (camera) '카메라', if (mic) '마이크', if (location) '위치'];
  // 카메라 · 마이크 · 위치 모두 받침 없는 말 → '와' · '를'
  final title = '${names.join(names.length >= 3 ? ' · ' : '와 ')}를\n사용해도 될까요?';
  Widget row(IconData icon, String name, String why) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F8FB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: const Color(0xFFEDF0F8), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, size: 22, color: AppColors.navy),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(why, style: const TextStyle(fontSize: 14, height: 1.4, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      );

  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    barrierColor: const Color(0x8F11172D),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(30))),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 11, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(color: const Color(0xFFC9CEDA), borderRadius: BorderRadius.circular(99)),
            ),
            const SizedBox(height: 32),
            // 아이콘 (연한 동그라미 안 남색 동그라미)
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: Color(0xFFEDF0F8),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Color(0xFFF7F8FB), spreadRadius: 10)],
              ),
              alignment: Alignment.center,
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: Color(0x2B1F2A5C), blurRadius: 18, offset: Offset(0, 8))],
                ),
                child: Icon(names.length > 1 ? Icons.verified_user_outlined : camera ? Icons.photo_camera_outlined : mic ? Icons.mic_none : Icons.location_on_outlined,
                    size: 31, color: Colors.white),
              ),
            ),
            const SizedBox(height: 24),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 26, height: 1.3, fontWeight: FontWeight.w900, letterSpacing: -1, color: AppColors.textPrimary)),
            const SizedBox(height: 8),
            if (camera) row(Icons.photo_camera_outlined, '카메라', '운전 중 눈을 감는지 확인할 때 써요'),
            if (mic) row(Icons.mic_none, '마이크', '운전 중 음성 퀴즈 대답을 들을 때 써요'),
            if (location) row(Icons.location_on_outlined, '위치', '졸음쉼터 안내와 경고 위치 기록에 써요'),
            const SizedBox(height: 4),
            const SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock_outline, size: 20, color: AppColors.textMuted),
                  SizedBox(width: 7),
                  Text('운행 안전을 위해서만 사용해요',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
                ],
              ),
            ),
            const SizedBox(height: 11),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(17),
                boxShadow: const [BoxShadow(color: Color(0x251F2A5C), blurRadius: 20, offset: Offset(0, 9))],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                ),
                child: const Text('계속', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
