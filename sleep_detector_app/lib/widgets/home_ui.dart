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
import '../design_tokens.dart';
import '../theme.dart';
import 'auth_ui.dart';
import 'owl_says.dart' show keepWords;
import 'web_ui.dart';
import 'buddy.dart';
import 'system_status.dart';
import 'stage_layout.dart' show titleLines;

/// 남색 '지금 상태' 카드 (시안 .current-state-card)
class HomeStateCard extends StatelessWidget {
  final int stage;
  final VoidCallback onStart;
  final String
  startLabel; // 진행 중인 운행이 있으면 '새로 운행 시작' ([이어서 운행]과 헷갈리지 않게, 11/12)
  // (11/16 팀장) 진행 중인 운행이 있으면 [운행 시작] 자리에 이 위젯 ('진행 중인 운행이 있어요' + [이어서 운행]).
  //   새 운행은 카드 아래 회색 글씨 링크 (home_screen)
  final Widget? resume;
  // (11/16 R안) 운행 요약 숫자 — (값, 이름) 예: ('1:20', '운행 시간'). 비면 안 보임
  final List<(String, String)> stats;
  // (11/17) 아직 운행을 시작하지 않음 — 0단계면 상태 글 없이 캐릭터 + [운행 시작] 만
  final bool idle;
  const HomeStateCard({
    super.key,
    required this.stage,
    required this.onStart,
    this.idle = false,
    this.startLabel = '운행 시작',
    this.resume,
    this.stats = const [],
  });

  @override
  Widget build(BuildContext context) {
    final s = stage.clamp(0, 3);
    // 0단계는 시안 문구, 1 ~ 3단계는 경고 화면 · 음성과 같은 문구 (stage_texts)
    final big = s == 0 ? '안전 운전 중이에요' : StageTexts.headline(s);
    return _today(s, big); // (11/19 사용자 요청) Headspace '오늘' 카드 — 예전 흰 카드는 _readdy (되돌릴 때 참고)
  }


  // ignore: unused_element
  static Color _titleColor(int s) => switch (s) {
        0 => AppColors.navy,
        1 => AppColors.stageInk(1),
        2 => AppColors.rest,
        _ => AppColors.urgent.withValues(alpha: 0.85),
      };

  // (11/19 사용자 요청 · Headspace 오늘 탭) 위 = 반투명 단계 색 하늘 + 흰 언덕 뒤로 떠오르는 동그란 캐릭터
  //   아래 흰 칸 = 날짜 · 큰 글 · (운행 중이면) 운행 요약 · 버튼
  Widget _today(int s, String big) {
    // (11/23 사용자 요청) 단계마다 문구 · 캐릭터 얼굴 · 바탕 색 · 왼쪽 위 단계 알약이 바뀜 (버튼 · 날짜 자리는 그대로)
    final now = DateTime.now();
    final date = '${now.month}/${now.day}'; // (11/19 사용자 요청) '11월 19일 목요일' 대신 짧게
    // 큰 글 · 작은 글 — 시나리오 단계 문장과 같은 뜻
    final title = const ['오늘도 안전 운행하세요', '졸음이 감지됐어요', '쉼터에서 쉬어 가세요', '지금 바로 정차하세요'][s];
    const String? sub = null; // (11/23 리디자인_2) 설명 글 뺌
    // (11/23 기업용 리디자인) 상태 알약 — 운행 대기 / 운행 중 / n단계
    const names = ['정상', '주의', '휴식 권고', '긴급'];
    // (11/23 사용자 요청) 운행 전 = '11/23' 만 · 운행 중 = 남색 알약 · 단계 = 점 + 이름
    final (String pill, Color pc) = idle && s == 0
        ? (date, AppStatus.info)
        : s == 0
            ? ('운행 중', AppColors.navy)
            : (names[s], [AppStatus.normal, AppStatus.caution, AppStatus.warning, AppStatus.danger][s]);
    final String? friendly = const [
      '졸음은 제가 옆에서 지켜볼게요',
      '정신 차리고 앞을 봐 주세요',
      '15분 쉬면 다시 출발할 수 있어요',
      '관리자에게 알렸어요',
    ][s];
    final stageCol = [AppStatus.normal, AppStatus.caution, AppStatus.warning, AppStatus.danger][s];
    return Container(
      decoration: BoxDecoration(
        // (11/23 리디자인_3) 흰색에서 오른쪽 아래로 아주 연한 단계 색 — 졸음가드다운 따뜻함 (장식 그라데이션은 이것 하나만)
        gradient: LinearGradient(
          begin: Alignment.centerLeft, // (11/23 사용자 요청) 왼쪽 → 오른쪽
          end: Alignment.centerRight,
          colors: [Colors.white, AppIllust.softTint[s]],
        ),
        border: Border.all(color: AppleGray.separator),
        borderRadius: BorderRadius.circular(AppRadius.card), // (11/19) 홈 모든 카드 둥글기 같게
        boxShadow: AppShadow.card,
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24), // (11/24 사용자 요청) 위 여백을 조금 써서 내용을 위로
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // (11/23) 캐릭터는 작은 칸으로 (친근함은 남기고 정보가 먼저) · 오른쪽 = 상태 알약 + 큰 글
            // (11/23 사용자 요청) 왼쪽 = 맨 위 상태 알약 · 아래 캐릭터 / 오른쪽 = 큰 글 — 문장마다 한 줄
            //   관리자에게 알렸어요
            //   지금 바로 정차하세요
            // (11/23 사용자 요청) 단계 알약 = 오른쪽 맨 위 (조금 작게) · 왼쪽 캐릭터 · 오른쪽 큰 글 두 줄 (줄 사이 한 칸)
            Stack(clipBehavior: Clip.none, children: [
              Padding(
                padding: const EdgeInsets.only(top: 36), // (11/23) 위 단계 알약과 숨 쉴 틈
                child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  Buddy(stage: s, size: 64, breathe: !idle),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      for (final (i, line) in titleLines(title).indexed) ...[
                        if (i > 0) const SizedBox(height: 4), // 줄 사이 한 칸
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(line, maxLines: 1, softWrap: false, style: AppType.title2.copyWith(height: 1.25, color: AppColors.textPrimary)),
                        ),
                      ],
                      if (friendly != null) ...[
                        const SizedBox(height: 6),
                        Text(friendly, style: AppType.subheadline.copyWith(color: AppColors.textSecondary)), // (11/23) 글자 키움
                      ],
                    ]),
                  ),
                ]),
              ),
              // (11/23 사용자 요청) 왼쪽 위 — 지금 단계 (연한 단계 색 알약 · 틀 없는 색 점 · 이름)
              Positioned(
                top: -4,
                left: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(9, 4, 11, 4),
                  decoration: BoxDecoration(color: stageCol.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(AppRadius.pill)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: stageCol, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(names[s], style: AppType.footnote.copyWith(fontWeight: FontWeight.w700, color: s == 1 ? const Color(0xFF9A6B00) : stageCol)),
                  ]),
                ),
              ),
              // (11/23 사용자 요청) 점 · 알약 없이 — 오른쪽 끝 = 아래 버튼 끝선
              Positioned(
                top: 0,
                right: 10, // (11/23 사용자 요청) 조금 더 왼쪽
                child: Text(date, style: AppType.footnote.copyWith(fontWeight: FontWeight.w600, color: AppColors.textSecondary, fontFeatures: AppStatus.figures)),
              ),
            ]),
            if (sub != null) ...[
              const SizedBox(height: 14),
              Text(sub, style: AppType.subheadline.copyWith(color: AppColors.textSecondary)),
            ],
            if (stats.isNotEmpty && pill.isEmpty && pc == Colors.transparent) ...[ // (11/23) 첫 카드에서는 숫자 줄 안 보임
              const SizedBox(height: 24),
              IntrinsicHeight(
                child: Row(children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4, color: AppColors.line),
                    Expanded(
                      child: Column(children: [
                        Text(stats[i].$1,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 26,
                                height: 1.15,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.6,
                                fontFeatures: AppStatus.figures,
                                color: stats[i].$2 == '졸음' && stats[i].$1 != '0회' ? const Color(0xFFD97706) : AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(stats[i].$2,
                            textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: AppColors.textSecondary)),
                      ]),
                    ),
                  ],
                ]),
              ),
            ],
            const SizedBox(height: 28), // (11/23) 버튼은 넉넉하게
            resume ?? _startButtons(),
          ]),
        ),
      ]),
    );
  }

  // (11/18 사용자 요청) [운행 시작] 아래 [이어서 운행] — 같은 크기 · 같은 알약 모양으로 나란히.
  //   이어서 할 운행이 없으면 [이어서 운행] 은 흐리게 (눌리지 않음). 운행이 있으면 home_screen 의 resume 이 대신 들어옴
  Widget _startButtons() => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // (11/18 피드백) 두 버튼의 아이콘 · 글자 시작점을 맞춤 (애플 SF 심볼 느낌의 둥근 아이콘)
        AuthButton(
          text: startLabel,
          onPressed: onStart,
          height: AppSize.button, // (11/23) 운전자 장갑 · 큰 손가락 — 누르는 칸 넉넉히
          contentWidth: 118,
          leading: const Icon(Icons.play_arrow_rounded, size: 22, color: Colors.white),
        ),
        const SizedBox(height: 12),
        const AuthButton(
          text: '이어서 운행',
          primary: false,
          height: AppSize.button,
          contentWidth: 118,
          leading: Icon(Icons.redo_rounded, size: 22, color: AuthUi.placeholder),
        ),
      ]);

  // (11/16 R안 · readdy 홈 카드) 흰 카드 · 단계 점 + 이름 · 큰 글 · 운행 요약 숫자 · 버튼 (부엉이 · 그라데이션 · 그림자 없음)
  // ignore: unused_element
  Widget _readdy(int s, String big) {
    // (11/17 사용자 요청) 운행 전 · 정상이면 '정상' 배지 · '안전 운전 중이에요' 없이 캐릭터 자리 + [운행 시작] 만
    if (idle && s == 0) {
      return WebCard(
        padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // (11/18 사용자 요청) 캐릭터는 왼쪽 · 오른쪽에 애플 메시지 같은 말풍선
            const Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Buddy(stage: 0, size: 104), // (11/19) 단계 캐릭터 — 운행 전은 초록 웃는 얼굴
              SizedBox(width: 14),
              Expanded(
                // (11/18 사용자 요청) '안녕하세요' 굵게 · 다음 줄 '오늘도 안전운전하세요' 보통 굵기
                child: SpeechBubble(
                  child: Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '안녕하세요\n', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800, color: AppColors.navy)),
                      TextSpan(text: '졸음을 지켜 주는 부엉이에요!', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: AppColors.textSecondary)),
                    ]),
                    style: TextStyle(height: 1.45, letterSpacing: -0.3, color: AppColors.textPrimary),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 22),
            resume ?? _startButtons(),
          ],
        ),
      );
    }
    // (11/17 관리자 웹 느낌) 흰 카드 · 단계 알약 배지 · 큰 글 · 오른쪽 캐릭터 그림 자리
    return WebCard(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20), // 운행 전 카드와 같은 여백
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // (11/18 피드백) 운행 전 화면과 같은 크기 · 같은 줄 — 캐릭터 왼쪽 · 말풍선 안에는 큰 글만 (단계 배지 뺌)
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Buddy(stage: s, size: 104), // (11/19) 지금 단계 색 · 표정
            const SizedBox(width: 14),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 8), // (11/18 피드백) 말풍선 끝선 조금 안쪽
                child: SpeechBubble(
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // 단계 점 — 운행 기록 타임라인과 같은 모양 · 글이 두 줄이 돼도 첫 줄 높이에
                  Padding(padding: const EdgeInsets.only(top: 5), child: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: AppColors.stage(s),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [BoxShadow(color: AppColors.stage(s).withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 1.5)],
                    ),
                  )),
                  const SizedBox(width: 10), // 글은 점 오른쪽으로 살짝
                  Expanded(
                    // 단어 중간에서 줄이 안 나뉘게 ('가세 / 요' 방지)
                    child: Text(keepWords(big),
                        maxLines: 3,
                        style: const TextStyle(
                            fontSize: 17, height: 1.35, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.textPrimary)),
                  ),
                ]),
              ),
              ),
            ),
          ]),
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            // (11/18 피드백) 운행 시간 · 졸음 · 휴식 — 연한 회색 칸 하나로 꽉 채워서 위 캐릭터 · 말풍선 · 아래 버튼과
            //   시작점 · 끝점이 같게 (칸 안은 세로선으로 나눔)
            // (11/18 피드백) 원래대로 — 회색 칸 없이 세로선으로만 나눈 한 줄 (애플 스타일 숫자 · 작은 회색 이름)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: IntrinsicHeight(
                child: Row(children: [
                  for (var i = 0; i < stats.length; i++) ...[
                    if (i > 0) const VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4, color: AppColors.line),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Text(stats[i].$1,
                            textAlign: TextAlign.center, style: AppType.title3.copyWith(color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        Text(stats[i].$2,
                            textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: AppColors.textSecondary)),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ],
          const SizedBox(height: 22),
          resume ?? _startButtons(),
        ],
      ),
    );
  }

  // 예전 남색 카드 (안 씀 — 되돌릴 때 참고)
  // ignore: unused_element
  Widget _old(BuildContext context, int s) {
    final stageColor = AppColors.stage(s);
    final small = s == 0 ? '오늘도 안전하게' : '지금 단계';
    final big = s == 0 ? '안전 운전\n중이에요' : StageTexts.headline(s);
    final sub = s == 0 ? '편안한 운전을\n도와 드릴게요' : null;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: const Color(0xFF334275)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF26366D), AppColors.navy],
          stops: [0, 0.68],
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x2B1F2A5C),
            blurRadius: 32,
            offset: Offset(0, 14),
          ),
        ],
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
                boxShadow: const [
                  BoxShadow(color: Color(0x08FFFFFF), spreadRadius: 28),
                ],
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
                    const Text(
                      '지금 상태',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFC9D1EE),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: stageColor.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: stageColor.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: stageColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            SleepEvent.stageLabels[s],
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: Color.lerp(stageColor, Colors.white, 0.55),
                            ),
                          ),
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
                            Text(
                              small,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFAEBBE2),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              big,
                              maxLines: 4,
                              style: TextStyle(
                                fontSize: s == 0 ? 27 : 20,
                                height: 1.28,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -1,
                                color: Colors.white,
                              ),
                            ),
                            if (sub != null) ...[
                              const SizedBox(height: 7),
                              Text(
                                sub,
                                style: const TextStyle(
                                  fontSize: 12,
                                  height: 1.45,
                                  color: Color(0xFFBFC9E8),
                                ),
                              ),
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
                        boxShadow: [
                          BoxShadow(
                            color: Color(0x420B1234),
                            blurRadius: 15,
                            offset: Offset(0, 10),
                          ),
                        ],
                        shape: BoxShape.circle,
                      ),
                      child: const Buddy(stage: 0, size: 140),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (resume != null)
                  resume!
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x3D0B1234),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ElevatedButton.icon(
                      onPressed: onStart,
                      icon: const Icon(Icons.photo_camera_outlined, size: 22),
                      label: Text(
                        startLabel,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.navy,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.card),
                        ),
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
    // (11/16 R안) readdy 소제목 — 작은 회색 글자
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),
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
  const HomeReadyTile({
    super.key,
    required this.icon,
    required this.title,
    required this.sub,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFEDF0F8),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, size: 19, color: AppColors.navy),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 19,
            height: 19,
            decoration: const BoxDecoration(
              color: AppColors.normal,
              shape: BoxShape.circle,
            ),
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
  const HomeReadyRow({
    super.key,
    required this.camera,
    required this.voice,
    required this.onTap,
  });

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
                : Border(
                    left: BorderSide(
                      color: all
                          ? const Color(0xFFBCDCC7)
                          : const Color(0xFFCDD1DA),
                    ),
                  ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                text,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: fg,
                ),
              ),
              const SizedBox(width: 5),
              Container(
                width: 17,
                height: 17,
                decoration: BoxDecoration(
                  color: ok ? AppColors.normal : const Color(0xFFA8ADBA),
                  shape: BoxShape.circle,
                ),
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
          const Text(
            '출발 준비',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
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
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: all
                          ? const Color(0xFFE8F5ED)
                          : const Color(0xFFE7E9EE),
                      borderRadius: BorderRadius.circular(AppRadius.card),
                      border: Border.all(
                        color: all
                            ? const Color(0xFFBFE2CB)
                            : const Color(0xFFD6DAE4),
                      ),
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
  final EdgeInsetsGeometry padding; // 위아래 여백 (홈 '최근 경고가 없어요' 는 아래쪽 빈 곳 가운데쯤으로)
  const HomeEmptyCard({
    super.key,
    required this.title,
    this.sub,
    this.actionText,
    this.onAction,
    this.padding = const EdgeInsets.symmetric(vertical: 36),
  });

  @override
  Widget build(BuildContext context) {
    // (11/17 사용자 요청) 흰 네모 없이 회색 바탕 위에 회색 글자만 (가운데)
    return Padding(
      padding: padding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textMuted)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
          ],
          if (actionText != null) ...[
            const SizedBox(height: 6),
            TextButton(onPressed: onAction, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}

/// 권한 안내창 (Figma 시안 '졸음운전 감지 앱3' 위치 권한 — 아래에서 올라오는 흰 창, 11/12 카메라 · 마이크도 함께)
/// [계속] → true (그다음 휴대폰의 실제 권한 창이 카메라 → 마이크 → 위치 순서로 연달아 뜸), 바깥을 눌러 닫으면 null
Future<bool?> showPermissionSheet(
  BuildContext context, {
  bool camera = false,
  bool mic = false,
  bool location = false,
}) {
  final names = [if (camera) '카메라', if (mic) '마이크', if (location) '위치'];
  // 카메라 · 마이크 · 위치 모두 받침 없는 말 → '와' · '를'
  final title = '${names.join(names.length >= 3 ? ' · ' : '와 ')}를\n사용해도 될까요?';
  Widget row(IconData icon, String name, String why) => Container(
    margin: const EdgeInsets.only(top: 10),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFF7F8FB),
      borderRadius: BorderRadius.circular(AppRadius.card),
      border: Border.all(color: AppColors.cardBorder),
    ),
    child: Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFEDF0F8),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: AppColors.navy),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                why,
                style: const TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  color: AppColors.textSecondary,
                ),
              ),
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
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 11, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFC9CEDA),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 32),
            // 아이콘 (연한 동그라미 안 남색 동그라미)
            Container(
              width: 92,
              height: 92,
              decoration: const BoxDecoration(
                color: Color(0xFFEDF0F8),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: Color(0xFFF7F8FB), spreadRadius: 10),
                ],
              ),
              alignment: Alignment.center,
              child: Container(
                width: 58,
                height: 58,
                decoration: const BoxDecoration(
                  color: AppColors.navy,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Color(0x2B1F2A5C),
                      blurRadius: 18,
                      offset: Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  names.length > 1
                      ? Icons.verified_user_outlined
                      : camera
                      ? Icons.photo_camera_outlined
                      : mic
                      ? Icons.mic_none
                      : Icons.location_on_outlined,
                  size: 31,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 26,
                height: 1.3,
                fontWeight: FontWeight.w900,
                letterSpacing: -1,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            if (camera)
              row(Icons.photo_camera_outlined, '카메라', '운전 중 눈을 감는지 확인할 때 써요'),
            if (mic) row(Icons.mic_none, '마이크', '운전 중 음성 퀴즈 대답을 들을 때 써요'),
            if (location)
              row(Icons.location_on_outlined, '위치', '졸음쉼터 안내와 경고 위치 기록에 써요'),
            const SizedBox(height: 4),
            const SizedBox(
              height: 42,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lock_outline,
                    size: 20,
                    color: AppColors.textMuted,
                  ),
                  SizedBox(width: 7),
                  Text(
                    '운행 안전을 위해서만 사용해요',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 11),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.card),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x251F2A5C),
                    blurRadius: 20,
                    offset: Offset(0, 9),
                  ),
                ],
              ),
              child: ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(58),
                  backgroundColor: AppColors.navy,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                ),
                child: const Text(
                  '계속',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// (11/18 사용자 요청) 애플 메시지 같은 말풍선 — 연회색 둥근 칸 + 왼쪽 아래 작은 꼬리 (캐릭터 쪽을 가리킴)
class SpeechBubble extends StatelessWidget {
  static const Color gray = AppleGray.fill; // (11/19) 따뜻한 연회색 말풍선
  final Widget child;
  final Color color; // (11/18) 사용 가이드는 연한 남색
  const SpeechBubble({super.key, required this.child, this.color = gray});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubbleTail(color),
      child: Container(
        margin: const EdgeInsets.only(left: 6), // 꼬리 자리
        padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.card)),
        child: child,
      ),
    );
  }
}

/// 말풍선 왼쪽 아래로 살짝 휘어 나온 꼬리 (iMessage 받은 말풍선 모양)
class _BubbleTail extends CustomPainter {
  final Color color;
  const _BubbleTail(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final b = size.height; // 아래 끝
    final path = Path()
      ..moveTo(6 + 14, b - 18) // 말풍선 안쪽에서 시작
      ..lineTo(6 + 14, b)
      ..quadraticBezierTo(8, b, 0, b - 1) // 왼쪽 아래 끝으로 휘어 나감
      ..quadraticBezierTo(6, b - 6, 6, b - 18)
      ..close();
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_BubbleTail old) => old.color != color;
}

/// (11/23 리디자인_3 · Samsara Driver 타일 메뉴 참고) 홈 바로가기 2 x 2 — 이미 있는 탭으로만 이동 (새 기능 없음)
class HomeTiles extends StatelessWidget {
  final ValueChanged<int> onOpenTab;
  const HomeTiles({super.key, required this.onOpenTab});

  static const _items = [
    (Icons.article_rounded, '운행 기록', '감지 이력 · 리포트', 1),
    (Icons.location_on_rounded, '졸음쉼터', '가까운 쉼터 찾기', 2),
    (Icons.smart_toy_rounded, '규정 도우미', '휴게 규정 묻기', 3),
    (Icons.insights_rounded, 'MY', '이번 달 안전 분석', 4),
  ];

  Widget _tile((IconData, String, String, int) t) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => onOpenTab(t.$4),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppleGray.separator),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.08), shape: BoxShape.circle),
                  child: Icon(t.$1, size: 20, color: AppColors.navy),
                ),
                const Spacer(),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron),
              ]),
              const SizedBox(height: 12),
              Text(t.$2, style: AppType.headline.copyWith(color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(t.$3, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppType.footnote.copyWith(color: AppColors.textSecondary)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Column(children: [
        Row(children: [Expanded(child: _tile(_items[0])), const SizedBox(width: 10), Expanded(child: _tile(_items[1]))]),
        const SizedBox(height: 10),
        Row(children: [Expanded(child: _tile(_items[2])), const SizedBox(width: 10), Expanded(child: _tile(_items[3]))]),
      ]);
}
