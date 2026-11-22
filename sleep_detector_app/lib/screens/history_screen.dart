// ═══════════════════════════════════════════════════════════════
// screens/history_screen.dart — 운행 기록 (내 경고 목록)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P2
//
// [이 파일이 하는 일]
//   - GET /events/my 목록 · 단계 필터 칩 · 상태 배지 (미확인 · 확인 · 조치완료 · 휴식완료)
//   - 맨 위 요약(오늘 · 누적 · 1~3단계 건수, 단계 필터와 상관없이 전체 기준) + 날짜가 바뀔 때마다 구분 줄 (오늘 · 어제 · 11월 1일 (토))
//
// [연결]
//   - 목록은 C 의 ApiService.fetchMyEvents() (GET /events/my) 로 받는다. 실패하면 '불러오지 못했어요 + 다시 시도'
//
// [쓰는 법]
//   - main_screen 은 const HistoryScreen() 으로 부른다 (loadEvents 를 비우면 fetchMyEvents)
//   - loadEvents 는 테스트 · 미리보기에서 목록을 바꿔 끼우는 입구다 (null 을 돌려주면 '준비 중' 안내)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../models/sleep_event.dart';
import '../services/api_service.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';
import 'event_detail_screen.dart';
import '../widgets/buddy.dart';

class HistoryScreen extends StatefulWidget {
  /// 경고 목록을 가져오는 함수. 비워 두면 기본(_defaultLoad). null 을 돌려주면 '아직 서버와 연결되지 않음'.
  final Future<List<SleepEvent>?> Function()? loadEvents;

  const HistoryScreen({super.key, this.loadEvents});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const List<int> _filterStages = [1, 2, 3];

  late Future<List<SleepEvent>?> _events = _fetch();
  int? _stage; // null = 전체

  static Future<List<SleepEvent>?> _defaultLoad() => ApiService.fetchMyEvents();

  // 화면(FutureBuilder)이 받기 전에 요청이 먼저 실패해도 '처리 안 된 오류'로 새지 않게 ignore() 를 붙인다
  Future<List<SleepEvent>?> _fetch() {
    final future = (widget.loadEvents ?? _defaultLoad)();
    future.ignore();
    return future;
  }

  // setState 안에서는 값을 돌려주면 안 된다 (Future 를 돌려주면 오류) → 중괄호로 대입만 한다
  void _reload() {
    setState(() {
      _events = _fetch();
    });
  }

  // (11/17 관리자 웹 '졸음 경고' 화면) 달력에서 보는 달 · 누른 날짜 (null = 그 달 전체)
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _day;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => _reload(),
              child: FutureBuilder<List<SleepEvent>?>(
                future: _events,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return _scroll(const [
                      Padding(
                        padding: EdgeInsets.all(48),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    ]);
                  }
                  if (snapshot.hasError) {
                    return _scroll([
                      _Hint(
                        text: '운행 기록을 불러오지 못했어요',
                        actionText: '다시 시도',
                        onAction: _reload,
                      ),
                    ]);
                  }
                  final events = snapshot.data;
                  if (events == null)
                    return _scroll(const [_Hint(text: '운행 기록 불러오기는 준비 중이에요')]);
                  if (events.isEmpty)
                    return _scroll(const [_Hint(text: '아직 경고 기록이 없어요')]);

                  // 보고 있는 달의 경고만 (달력 · 도넛 · 목록 모두 같은 달)
                  bool inMonth(SleepEvent e) {
                    final d = e.createdAt.toLocal();
                    return d.year == _month.year && d.month == _month.month;
                  }

                  bool sameDay(SleepEvent e, DateTime day) {
                    final d = e.createdAt.toLocal();
                    return d.year == day.year && d.month == day.month && d.day == day.day;
                  }

                  final month = events.where(inMonth).toList();
                  final prevMonth = DateTime(_month.year, _month.month - 1);
                  final prevCount = events.where((e) {
                    final d = e.createdAt.toLocal();
                    return d.year == prevMonth.year && d.month == prevMonth.month;
                  }).length;
                  // 받은 목록을 건드리지 않게 복사해서 최신순으로 정렬한다
                  final shown = month
                      .where((e) => _stage == null || e.stage == _stage)
                      .where((e) => _day == null || sameDay(e, _day!))
                      .toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  final now = DateTime.now();
                  final thisMonth = DateTime(now.year, now.month);
                  final picked = _day == null ? month : month.where((e) => sameDay(e, _day!)).toList();
                  return _scroll([
                    const SizedBox(height: 12),
                    // (11/19 사용자 요청 · Headspace) 맨 위 노랑 그라데이션 카드 — 그 달(또는 고른 날) 경고 수 · 지난달 비교
                    _HsHero(month: _month, day: _day, total: picked.length, diff: _day == null ? month.length - prevCount : null),
                    const SizedBox(height: 12),
                    // 단계 비율 — 둥근 가로 막대 + 1 · 2 · 3단계 숫자 (도넛 대신)
                    _StageBar(events: picked),
                    const SizedBox(height: 12),
                    _MonthCalendar(
                      onSwipe: (d) {
                        final next = DateTime(_month.year, _month.month + d);
                        if (next.isAfter(thisMonth)) return;
                        setState(() {
                          _month = next;
                          _day = null;
                        });
                      },
                      month: _month,
                      events: month,
                      selected: _day,
                      canNext: _month.isBefore(thisMonth),
                      onPrev: () => setState(() {
                        _month = DateTime(_month.year, _month.month - 1);
                        _day = null;
                      }),
                      onNext: () => setState(() {
                        _month = DateTime(_month.year, _month.month + 1);
                        _day = null;
                      }),
                      onDay: (d) => setState(() => _day = (_day != null && _day == d) ? null : d),
                    ),
                    const SizedBox(height: 22),
                    // (11/19 Headspace) 둥근 알약 필터 — 고른 것만 남색
                    _FilterBar(
                      selected: _stage,
                      stages: _filterStages,
                      onSelected: (stage) => setState(() => _stage = stage),
                    ),
                    const SizedBox(height: 4),
                    if (shown.isEmpty)
                      WebCard(padding: EdgeInsets.zero, child: const _Hint(text: '이 조건의 경고가 없어요'))
                    else
                      ..._byDay(shown, now),
                    // (11/19 사용자 요청) 안내는 맨 아래
                    const Padding(
                      padding: EdgeInsets.only(top: 12, left: 4), // (11/19) 카드와 같은 시작선 · 왼쪽 정렬
                      child: Text('› 를 누르면 AI 분석 보고서를 볼 수 있어요', style: TextStyle(fontSize: 13.5, color: AppColors.textMuted)),
                    ),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 최신순으로 정렬된 목록을 날짜별로 묶어서 — 날짜 작은 제목 + 흰 카드 하나에 줄로 나눈 목록 (11/16 R안 · readdy)
  static List<Widget> _byDay(List<SleepEvent> sorted, DateTime now) {
    final groups = <String, List<SleepEvent>>{};
    for (final e in sorted) {
      groups.putIfAbsent(_dayKey(e.createdAt), () => []).add(e);
    }
    // (11/19 Headspace) 날짜마다 따로 둥근 흰 카드 — 위에 굵은 날짜 · 몇 건
    final out = <Widget>[];
    for (final list in groups.values) {
      out.add(_DayHeader(label: _dayLabel(list.first.createdAt, now), count: list.length));
      out.add(WebCard(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(children: [
          // (11/18 피드백) 타임라인 — 줄 사이 선 대신 왼쪽 세로선 하나로 이어짐
          for (var i = 0; i < list.length; i++) _EventCard(event: list[i], first: i == 0, last: i == list.length - 1),
        ]),
      ));
    }
    return out;
  }

  // 당겨서 새로고침이 안내 문구 화면에서도 되도록 항상 스크롤 가능하게 둔다
  Widget _scroll(List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110), // (11/19) 떠 있는 탭바 높이만큼
      children: children,
    );
  }
}

// 같은 날인지 가르는 열쇠 (기기 시간대 기준 연-월-일)
String _dayKey(DateTime t) {
  final d = t.toLocal();
  return '${d.year}-${d.month}-${d.day}';
}

// 오늘 · 어제 · 11월 1일 (토) · (다른 해는) 2025년 11월 1일 (토)
String _dayLabel(DateTime t, DateTime now) {
  final d = t.toLocal();
  if (d.year < 2000) return '날짜 없음'; // created_at 이 비었을 때의 대신값(1970년)
  // 날짜끼리만 비교하려고 자정 UTC 로 맞춘다 (시각 차이 · 서머타임에 흔들리지 않게)
  final days = DateTime.utc(
    now.year,
    now.month,
    now.day,
  ).difference(DateTime.utc(d.year, d.month, d.day)).inDays;
  // (11/18 피드백) '오늘' · '어제' 대신 날짜만 — 11/18 (다른 해면 2025/11/18)
  days;
  final year = d.year == now.year ? '' : '${d.year}/';
  return '$year${d.month}/${d.day}';
}

/// 카드 안 줄 사이 얇은 선 — 좌우 같은 여백 (11/16 사용자 요청 12)
class _Line extends StatelessWidget {
  const _Line();
  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 18),
        child: Divider(height: 1, thickness: 1, color: AppColors.line),
      );
}

/// 달력 아이콘 모양 날짜 (11/16 사용자 요청 4) — 위 빨간 띠에 'n월', 아래 큰 날짜 숫자
class _CalendarTile extends StatelessWidget {
  final DateTime day;
  const _CalendarTile({required this.day});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 50,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x14000000)),
      ),
      child: Column(children: [
        Container(
          height: 15,
          width: double.infinity,
          color: const Color(0xFFFF3B30),
          alignment: Alignment.center,
          child: Text('${day.month}월',
              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white, height: 1)),
        ),
        Expanded(
          child: Center(
            child: Text('${day.day}',
                style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: Color(0xFF1C1C1E), height: 1)),
          ),
        ),
      ]),
    );
  }
}

// 예전 목록 맨 위 '운행 요약' (11/16 R안 · 안 씀 — 11/17 달력 · 도넛으로 바뀜, 되돌릴 때 참고)
// ignore: unused_element
class _Summary extends StatelessWidget {
  final List<SleepEvent> events;
  final DateTime now;
  const _Summary({required this.events, required this.now});

  static const _week = ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'];

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<SleepEvent>>{};
    for (final e in [...events]..sort((a, b) => b.createdAt.compareTo(a.createdAt))) {
      if (e.createdAt.year < 2000) continue;
      groups.putIfAbsent(_dayKey(e.createdAt), () => []).add(e);
    }
    final days = groups.values.take(3).toList();
    if (days.isEmpty) return const SizedBox.shrink();
    Widget row(List<SleepEvent> list) {
      final d = list.first.createdAt.toLocal();
      final label = _dayLabel(d, now);
      final title = _week[d.weekday - 1] + (label == '오늘' ? ' · 오늘' : label == '어제' ? ' · 어제' : '');
      final counts = [for (var s = 1; s <= 3; s++) list.where((e) => e.stage == s).length];
      final sub = [
        for (var s = 1; s <= 3; s++)
          if (counts[s - 1] > 0) '${SleepEvent.stageLabels[s]} ${counts[s - 1]}',
      ].join(' · ');
      final top = list.map((e) => e.stage).fold<int>(0, (a, b) => b > a ? b : a);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          _CalendarTile(day: d),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 3),
              Text(sub.isEmpty ? '경고 없음' : sub,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: AppColors.stage(top), borderRadius: BorderRadius.circular(999)),
            child: Text('경고 ${list.length}회',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onStage(top))),
          ),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _SmallTitle('운행 요약'),
      Container(
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24)),
        child: Column(children: [
          for (var i = 0; i < days.length; i++) ...[if (i > 0) const _Line(), row(days[i])],
        ]),
      ),
      const SizedBox(height: 8),
      const _SmallTitle('경고 기록'),
    ]);
  }
}

class _SmallTitle extends StatelessWidget {
  final String text;
  const _SmallTitle(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
      );
}

// 예전 남색 띠 (안 씀 — 되돌릴 때 참고)
// ignore: unused_element
class _OldSummary extends StatelessWidget {
  final List<SleepEvent> events;
  final DateTime now;
  const _OldSummary({required this.events, required this.now});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.navy,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Buddy(stage: 0, size: 62, breathe: false),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '이번 주도 안전하게',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  '경고 뒤 충분히 쉬어 주세요',
                  style: TextStyle(fontSize: 13, color: Color(0xFFBEC8E9)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// 날짜가 바뀔 때 카드 사이에 끼는 구분 줄: "오늘 · 3건"
class _DayHeader extends StatelessWidget {
  final String label;
  final int count;
  const _DayHeader({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      // (11/19 사용자 요청) '11/19' 는 카드 안 시각과, '3건' 은 카드 안 꺾쇠 끝과 같은 선
      padding: const EdgeInsets.only(top: 18, bottom: 8, left: 18, right: 14),
      child: Semantics(
        header: true,
        label: '$label $count건',
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary)),
          const Spacer(),
          Text('$count건', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ]),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final int? selected;
  final List<int> stages;
  final ValueChanged<int?> onSelected;
  const _FilterBar({
    required this.selected,
    required this.stages,
    required this.onSelected,
  });

  // (11/19 Headspace) 둥근 알약 4개 — 고른 것은 남색 바탕 · 흰 글자, 나머지는 흰 바탕 (부드럽게 바뀜)
  @override
  Widget build(BuildContext context) {
    final labels = ['전체', for (final s in stages) '$s단계'];
    final index = selected == null ? 0 : stages.indexOf(selected!) + 1;
    return Row(children: [
      for (var i = 0; i < labels.length; i++) ...[
        if (i > 0) const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onSelected(i == 0 ? null : stages[i - 1]),
            child: AnimatedContainer(
              duration: AppMotion.normal,
              curve: AppMotion.curve,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: i == index ? AppColors.navy : AppColors.card,
                borderRadius: BorderRadius.circular(999),
                boxShadow: i == index ? AppShadow.button : AppShadow.card,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (i > 0) ...[
                  // (11/19 사용자 요청) 타임라인 '미세수면' 옆과 같은 링 점
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: AppColors.stage(stages[i - 1]),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 1.5),
                      boxShadow: [BoxShadow(color: AppColors.stage(stages[i - 1]).withValues(alpha: 0.35), spreadRadius: 1.3)],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: i == index ? Colors.white : AppColors.textSecondary)),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}

/// (11/19) 홈 운행 상세에서도 같은 타임라인 줄을 쓰려고 밖으로 내놓은 이름
class HistoryEventRow extends StatelessWidget {
  final SleepEvent event;
  final bool first;
  final bool last;
  const HistoryEventRow({super.key, required this.event, this.first = false, this.last = false});
  @override
  Widget build(BuildContext context) => _EventCard(event: event, first: first, last: last);
}

class _EventCard extends StatelessWidget {
  final SleepEvent event;
  final bool first; // 그날 첫 줄 — 세로선이 점 위로는 안 나감
  final bool last; // 그날 마지막 줄 — 세로선이 점 아래로는 안 나감
  const _EventCard({required this.event, this.first = false, this.last = false});

  // 날짜는 위 구분 줄에 있으니 카드에는 시각만 (오후 2:40)
  static String _time(DateTime t) {
    final d = t.toLocal();
    if (d.year < 2000) return '시각 없음';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? '오전' : '오후';
    return '$ampm $h:${d.minute.toString().padLeft(2, '0')}';
  }

  static String _hm(DateTime t) {
    final d = t.toLocal();
    if (d.year < 2000) return '--:--';
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  // (11/16 R안 · readdy) 카드 안 한 줄 — 왼쪽 단계 색 막대 · 이유 + 단계 표 · 시각(검정) · 오른쪽 동그란 꺾쇠
  @override
  Widget build(BuildContext context) {
    // (11/18 피드백) 타임라인 한 줄 — 왼쪽 시각 · 세로선 위 단계 색 점 · 이유 + 단계 알약 · 꺾쇠
    final s = event.stage.clamp(0, 3);
    const lineColor = AppColors.fill;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // 시각 (점과 같은 높이)
          SizedBox(
            width: 70,
            child: Padding(
              padding: const EdgeInsets.only(left: 18, top: 14),
              // 타임라인은 짧게 24시간 '17:39' (오전/오후를 붙이면 두 줄로 넘어감)
              child: Text(_hm(event.createdAt),
                  maxLines: 1,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
          ),
          // 세로선 + 점 (긴급은 빨간 점 테두리가 조금 큼)
          SizedBox(
            width: 22,
            child: Stack(alignment: Alignment.topCenter, children: [
              Positioned(
                top: first ? 22 : 0,
                bottom: last ? null : 0,
                height: last ? 22 : null,
                child: Container(width: 2, color: lineColor),
              ),
              Positioned(
                top: 16,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: AppColors.stage(s),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.card, width: 2),
                    boxShadow: [BoxShadow(color: AppColors.stage(s).withValues(alpha: 0.35), blurRadius: 0, spreadRadius: 1.5)],
                  ),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 12, 12, 14),
              child: Row(children: [
                Expanded(
                  child: Text(event.reasonLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                ),
                const SizedBox(width: 8),
                StageBadge(stage: s),
                const SizedBox(width: 2),
                const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  // 예전 흰 카드 (안 씀 — 되돌릴 때 참고)
  // ignore: unused_element
  Widget _old(BuildContext context) {
    final s = event.stage.clamp(0, 3);
    final c = AppColors.stage(s);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(
            color: event.isUrgent ? AppColors.urgent : AppColors.cardBorder,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          // (11/15) 경고 기록 상세 — 졸음 사진 + AI 분석 결과 (관리자 웹 경고 상세와 같은 내용)
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
          child: Container(
            constraints: const BoxConstraints(minHeight: 95),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                // 단계 숫자 네모 (단계 색 — 가이드 '부엉이 색의 뜻'과 같게)
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '$s',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: AppColors.onStage(s),
                    ),
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: c.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              event.stageLabel,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: Color.lerp(c, Colors.black, 0.35),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _time(event.createdAt),
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      Text(
                        event.summary.isEmpty
                            ? event.reasonLabel
                            : event.summary,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 22,
                  color: AppColors.textMuted,
                ), // 상세 화면으로 (시안 화살표)
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  final String text;
  final String? actionText;
  final VoidCallback? onAction;
  const _Hint({required this.text, this.actionText, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 10),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 15, color: AppColors.textMuted),
          ),
          if (actionText != null) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: onAction, child: Text(actionText!)),
          ],
        ],
      ),
    );
  }
}

/// (11/17 관리자 웹) 한 달 달력 — 경고가 있던 날 아래에 단계 색 점, 누르면 그날만 보기 (다시 누르면 풀림)
class _MonthCalendar extends StatelessWidget {
  final ValueChanged<int>? onSwipe; // (11/18) 달력을 옆으로 밀면 이전 · 다음 달
  final DateTime month; // 그 달 1일
  final List<SleepEvent> events; // 그 달 경고
  final DateTime? selected;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDay;
  const _MonthCalendar({
    this.onSwipe,
    required this.month,
    required this.events,
    required this.selected,
    required this.canNext,
    required this.onPrev,
    required this.onNext,
    required this.onDay,
  });

  static const _weekNames = ['일', '월', '화', '수', '목', '금', '토'];

  @override
  Widget build(BuildContext context) {
    // 날짜별로 있었던 단계들 (점 색)
    final stagesByDay = <int, Set<int>>{};
    for (final e in events) {
      final d = e.createdAt.toLocal();
      stagesByDay.putIfAbsent(d.day, () => <int>{}).add(e.stage.clamp(1, 3));
    }
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final lead = DateTime(month.year, month.month, 1).weekday % 7; // 일요일 = 0
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var day = 1; day <= daysInMonth; day++) _dayCell(DateTime(month.year, month.month, day), stagesByDay[day], now),
    ];

    // (11/19 사용자 요청) 위아래 여백 같게 — 마지막 줄 칸 아래에 점 자리가 있어 아래 여백은 그만큼 줄임
    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SizedBox(width: 4),
          Text('${month.year}년 ${month.month}월',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.textPrimary)),
          const Spacer(),
          // (11/19 Headspace) 동그란 연한 칸 안 화살표
          _RoundArrow(icon: Icons.chevron_left_rounded, onTap: onPrev, tooltip: '이전 달'),
          const SizedBox(width: 8),
          _RoundArrow(icon: Icons.chevron_right_rounded, onTap: canNext ? onNext : null, tooltip: '다음 달'),
        ]),
        const SizedBox(height: 6),
        // (11/18 사용자 요청) 회색 칸 없이 흰 바탕 그대로 · 달이 바뀌면 옆으로 부드럽게 미끄러짐
        SlideSwitcher(
          index: month.year * 12 + month.month,
          onSwipe: onSwipe,
          child: Column(children: [
            Row(children: [
              for (final w in _weekNames)
                Expanded(
                  child: Center(
                      child: Text(w, style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted))),
                ),
            ]),
            const SizedBox(height: 6),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              padding: EdgeInsets.zero, // (11/19) 탭바 뒤로 흐르게 바꾼 뒤 아래 빈칸이 생기지 않게
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.05,
              children: cells,
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _dayCell(DateTime day, Set<int>? stages, DateTime now) {
    final future = day.isAfter(DateTime(now.year, now.month, now.day));
    final isSelected = selected != null && selected == day;
    final isToday = day.year == now.year && day.month == now.month && day.day == now.day;
    final dots = (stages?.toList() ?? <int>[])..sort((a, b) => b.compareTo(a)); // (11/18) 위험한 순: 빨강 → 주황 → 노랑
    return GestureDetector(
      onTap: future ? null : () => onDay(day),
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          // (11/19 Headspace) 오늘 = 연한 노랑 동그라미 · 고른 날 = 남색 동그라미 + 흰 숫자
          AnimatedContainer(
            duration: AppMotion.normal,
            curve: AppMotion.curve,
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isSelected ? AppColors.navy : (isToday ? AppColors.navy.withValues(alpha: 0.12) : Colors.transparent),
            ),
            child: Text('${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : (isToday ? AppColors.navy : (future ? const Color(0xFFBFC3CE) : AppColors.textPrimary)),
                )),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 5,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (final s in dots)
                Container(
                  width: 5,
                  height: 5,
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle),
                ),
            ]),
          ),
        ]),
    );
  }
}

/// (11/19 Headspace) 달력 위 동그란 화살표 단추
class _RoundArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final String tooltip;
  const _RoundArrow({required this.icon, required this.onTap, required this.tooltip});
  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: AppleGray.fill, shape: BoxShape.circle),
            child: Icon(icon, size: 22, color: onTap == null ? AppleGray.chevron : AppColors.textPrimary),
          ),
        ),
      );
}

/// (11/19 사용자 요청 · Headspace) 운행 기록 맨 위 노랑 그라데이션 카드 — 'n월' · '졸음 경고 n건' · 지난달 비교
class _HsHero extends StatelessWidget {
  final DateTime month;
  final DateTime? day;
  final int total;
  final int? diff; // null = 날짜를 골랐을 때 (비교 없음)
  const _HsHero({required this.month, required this.day, required this.total, required this.diff});

  @override
  Widget build(BuildContext context) {
    final d = diff;
    return HsCard(
      stage: 2,
      face: 0,
      minHeight: 138,
      orb: 168,
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(day != null ? '${day!.month}/${day!.day}' : '${month.month}월',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xB31C2033))),
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: '졸음 경고 '),
            TextSpan(text: '$total', style: const TextStyle(fontSize: 30)),
            const TextSpan(text: '건'),
          ]),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.6, color: AppColors.textPrimary),
        ),
        if (d != null) ...[
          const SizedBox(height: 6),
          Text(d == 0 ? '지난달과 같아요' : '지난달보다 ${d.abs()}건 ${d < 0 ? '줄었어요' : '늘었어요'}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xCC1C2033))),
        ],
      ]),
    );
  }
}

/// (11/19 Headspace) 단계 비율 — 둥근 가로 막대(단계 색으로 나눔) + 아래 1 · 2 · 3단계 링 점 · 건수 · %
class _StageBar extends StatelessWidget {
  final List<SleepEvent> events;
  const _StageBar({required this.events});

  @override
  Widget build(BuildContext context) {
    final counts = [for (var s = 1; s <= 3; s++) events.where((e) => e.stage.clamp(1, 3) == s).length];
    final total = events.length;
    String pct(int n) => total == 0 ? '0%' : '${(n * 100 / total).round()}%';
    // (11/19 사용자 요청) 가로 폭을 고르게 채움 — 칸마다 [작은 캐릭터 | 링 점 · 이름 / 건수 / %] 를 왼쪽부터 · 칸 사이 세로선
    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      child: IntrinsicHeight(
        child: Row(children: [
          for (var s = 1; s <= 3; s++) ...[
            if (s > 1) const VerticalDivider(width: 21, thickness: 1, indent: 2, endIndent: 2, color: AppColors.line),
            Expanded(
              // (11/19 사용자 요청) '● 주의' 위에 작은 캐릭터 · 칸 왼쪽부터 · 아래 여백까지 써서 전체를 조금 아래로
              // (11/19 사용자 요청) 캐릭터처럼 '● 주의' · 건수 · % 도 모두 칸 가운데
              child: Padding(
                padding: EdgeInsets.zero,
                child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                Center(child: Buddy(stage: s, size: 22, breathe: false)), // (11/19) 캐릭터는 칸 가운데
                const SizedBox(height: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                    Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppColors.stage(s),
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.card, width: 1.5),
                          boxShadow: [BoxShadow(color: AppColors.stage(s).withValues(alpha: 0.35), spreadRadius: 1.2)],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(stageShortName(s),
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text.rich(TextSpan(children: [
                      TextSpan(text: '${counts[s - 1]}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      const TextSpan(text: '건', style: TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
                    ])),
                    Text(pct(counts[s - 1]), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                  ]),
              ]),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// (11/17 관리자 웹) 그 달 전체 — 도넛 그래프 (11/19 Headspace 카드 · 막대로 바꿔서 안 씀 · 되돌릴 때 참고)
// ignore_for_file: unused_element_parameter
// ignore: unused_element
class _MonthDonut extends StatelessWidget {
  final DateTime? day; // 고른 날짜 (null = 그 달 전체)
  final List<SleepEvent> events;
  final int diff; // 지난달보다 몇 건 많은지 (음수면 적음, 날짜를 고르면 0)
  final DateTime? month; // (11/18 팀장) 통계가 몇 월 것인지 위에 표시
  const _MonthDonut({required this.day, required this.events, required this.diff, this.month});

  @override
  Widget build(BuildContext context) {
    final counts = [for (var s = 1; s <= 3; s++) events.where((e) => e.stage.clamp(1, 3) == s).length];
    final total = events.length;
    String pct(int n) => total == 0 ? '0%' : '${(n * 100 / total).round()}%';
    return WebCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // (11/18 사용자 요청) 'n월 전체' 글자 없음 — 날짜를 골랐을 때만 그 날짜를 작게 보여 줌
        if (day != null || diff != 0)
        Row(children: [
          if (day != null)
            Text('${day!.month}월 ${day!.day}일',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary))
          else if (month != null)
            Text('${month!.month}월', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Spacer(),
          if (diff != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.field, // (11/18 피드백) 연한 회색 바탕 + 검정 글자
                  borderRadius: BorderRadius.circular(999)),
              child: Text('지난달보다 ${diff > 0 ? '+' : ''}$diff건',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary)),
            ),
        ]),
        const SizedBox(height: 16),
        Center(
          child: SizedBox(
            width: 150,
            height: 150,
            child: CustomPaint(
              painter: _DonutPainter(counts),
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic, children: [
                  Text('$total',
                      style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(width: 2),
                  const Text('건', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        // (11/18 피드백) 1 · 2 · 3단계를 한 줄에 — 세로선으로 나눔 (선은 원래 쓰던 옅은 회색) · 단계마다 다른 색
        const Divider(height: 1, thickness: 1, color: AppColors.line),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(children: [
            for (var s = 1; s <= 3; s++) ...[
              if (s > 1) const VerticalDivider(width: 1, thickness: 1, indent: 4, endIndent: 4, color: AppColors.line),
              Expanded(
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: AppColors.stage(s), shape: BoxShape.circle)),
                    const SizedBox(width: 5),
                    Text('$s단계 ${stageShortName(s)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ]),
                  const SizedBox(height: 6),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text('${counts[s - 1]}',
                            style: AppType.title2.copyWith(color: AppColors.textPrimary)), // (11/18) 애플 스타일 — 숫자는 진회색, 색은 이름 앞 점에만
                        const SizedBox(width: 2),
                        const Text('건', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                      ]),
                  const SizedBox(height: 2),
                  Text(pct(counts[s - 1]), style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<int> counts; // 1 · 2 · 3단계
  _DonutPainter(this.counts);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    final total = counts.fold<int>(0, (a, b) => a + b);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = AppColors.field;
    canvas.drawArc(arcRect, 0, 6.283185, false, base);
    if (total == 0) return;
    const gap = 0.04; // 조각 사이 틈
    var start = -1.5708; // 12시 방향부터
    for (var i = 0; i < 3; i++) {
      if (counts[i] == 0) continue;
      final sweep = 6.283185 * counts[i] / total;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = AppColors.stage(i + 1);
      final hasGap = counts.where((c) => c > 0).length > 1;
      canvas.drawArc(arcRect, start + (hasGap ? gap / 2 : 0), sweep - (hasGap ? gap : 0), false, p);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.counts.join(',') != counts.join(',');
}