// ═══════════════════════════════════════════════════════════════
// screens/history_screen.dart — 운행 기록 (내 경고 목록)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/my_reports_screen.dart (🟡 이름 변경 + 수정)
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
import '../theme.dart';
import '../widgets/web_ui.dart';
import 'event_detail_screen.dart';

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
                  return _scroll([
                    const SizedBox(height: 12),
                    _MonthCalendar(
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
                    const SizedBox(height: 12),
                    _MonthDonut(month: _month, events: month, diff: month.length - prevCount),
                    const SizedBox(height: 12),
                    WebCard(
                      padding: EdgeInsets.zero,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        _FilterBar(
                          selected: _stage,
                          stages: _filterStages,
                          onSelected: (stage) => setState(() => _stage = stage),
                        ),
                        if (_day != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 0, 10, 4),
                            child: Row(children: [
                              Text('${_day!.month}월 ${_day!.day}일만 보는 중',
                                  style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                              const Spacer(),
                              TextButton(
                                  onPressed: () => setState(() => _day = null), child: const Text('전체 보기')),
                            ]),
                          ),
                        const Divider(height: 1, thickness: 1, color: AppColors.line),
                        if (shown.isEmpty)
                          const _Hint(text: '이 조건의 경고가 없어요')
                        else
                          ..._byDay(shown, now),
                      ]),
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
    // (11/17) 큰 카드 하나 안에 날짜 작은 제목 + 줄 목록
    final out = <Widget>[];
    for (final list in groups.values) {
      out.add(_DayHeader(label: _dayLabel(list.first.createdAt, now), count: list.length));
      for (var i = 0; i < list.length; i++) {
        if (i > 0) out.add(const _Line());
        out.add(_EventCard(event: list[i]));
      }
    }
    return out;
  }

  // 당겨서 새로고침이 안내 문구 화면에서도 되도록 항상 스크롤 가능하게 둔다
  Widget _scroll(List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
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
  if (days == 0) return '오늘';
  if (days == 1) return '어제';
  const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
  final year = d.year == now.year ? '' : '${d.year}년 ';
  return '$year${d.month}월 ${d.day}일 (${weekdays[d.weekday - 1]})';
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
          const ImageSlot(label: '캐릭터 이미지', width: 62, height: 62, radius: 14),
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
      padding: const EdgeInsets.only(top: 16, bottom: 4, left: 18),
      child: Semantics(
        header: true,
        label: '$label $count건',
        child: Text(
          label,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
        ),
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

  // (11/17 관리자 웹) 연회색 칸 안의 알약 — 고른 것만 흰 바탕 + 그림자
  Widget _pill(String text, bool on, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 13),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? AppColors.card : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            boxShadow: on ? const [BoxShadow(color: Color(0x141F2A5C), blurRadius: 6, offset: Offset(0, 1))] : null,
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: on ? FontWeight.w700 : FontWeight.w500,
              color: on ? AppColors.textPrimary : AppColors.textSecondary,
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(999)),
          child: Row(
            children: [
              _pill('전체', selected == null, () => onSelected(null)),
              for (final stage in stages)
                _pill('$stage단계 | ${stageShortName(stage)}', selected == stage, () => onSelected(stage)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  final SleepEvent event;
  const _EventCard({required this.event});

  // 날짜는 위 구분 줄에 있으니 카드에는 시각만 (오후 2:40)
  static String _time(DateTime t) {
    final d = t.toLocal();
    if (d.year < 2000) return '시각 없음';
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? '오전' : '오후';
    return '$ampm $h:${d.minute.toString().padLeft(2, '0')}';
  }

  // (11/16 R안 · readdy) 카드 안 한 줄 — 왼쪽 단계 색 막대 · 이유 + 단계 표 · 시각(검정) · 오른쪽 동그란 꺾쇠
  @override
  Widget build(BuildContext context) {
    // (11/17 관리자 웹 표 한 줄) 긴급은 왼쪽에 빨간 세로 선 · 이유 · 시각 · 오른쪽 단계 알약 + 꺾쇠
    final s = event.stage.clamp(0, 3);
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => EventDetailScreen(event: event))),
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: s >= 3 ? AppColors.urgent : Colors.transparent, width: 3)),
        ),
        padding: const EdgeInsets.fromLTRB(15, 13, 12, 13),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(event.reasonLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              const SizedBox(height: 2),
              Text(_time(event.createdAt), style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            ]),
          ),
          const SizedBox(width: 8),
          StageBadge(stage: s),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
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
  final DateTime month; // 그 달 1일
  final List<SleepEvent> events; // 그 달 경고
  final DateTime? selected;
  final bool canNext;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDay;
  const _MonthCalendar({
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

    return WebCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          const SizedBox(width: 4),
          Text('${month.year}년 ${month.month}월',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(width: 6),
          Text('경고 ${events.length}건', style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
          const Spacer(),
          IconButton(onPressed: onPrev, icon: const Icon(Icons.chevron_left, size: 22), tooltip: '이전 달'),
          IconButton(
              onPressed: canNext ? onNext : null, icon: const Icon(Icons.chevron_right, size: 22), tooltip: '다음 달'),
        ]),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
          decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(16)),
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
    final dots = (stages?.toList() ?? <int>[])..sort();
    return GestureDetector(
      onTap: future ? null : () => onDay(day),
      child: Container(
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.card : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected ? const [BoxShadow(color: Color(0x141F2A5C), blurRadius: 6, offset: Offset(0, 1))] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('${day.day}',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                color: future ? const Color(0xFFBFC3CE) : (isToday ? AppColors.navy : AppColors.textPrimary),
              )),
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
      ),
    );
  }
}

/// (11/17 관리자 웹) 그 달 전체 — 도넛 그래프(가운데 총 건수) + 1 · 2 · 3단계 칸(건수 · %)
class _MonthDonut extends StatelessWidget {
  final DateTime month;
  final List<SleepEvent> events;
  final int diff; // 지난달보다 몇 건 많은지 (음수면 적음)
  const _MonthDonut({required this.month, required this.events, required this.diff});

  @override
  Widget build(BuildContext context) {
    final counts = [for (var s = 1; s <= 3; s++) events.where((e) => e.stage.clamp(1, 3) == s).length];
    final total = events.length;
    String pct(int n) => total == 0 ? '0%' : '${(n * 100 / total).round()}%';
    return WebCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text('${month.month}월 전체',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Spacer(),
          if (diff != 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: diff > 0 ? AppColors.stageTint(3) : AppColors.stageTint(0),
                  borderRadius: BorderRadius.circular(999)),
              child: Text('지난달보다 ${diff > 0 ? '+' : ''}$diff건',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: diff > 0 ? AppColors.stageInk(3) : AppColors.stageInk(0))),
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
        Row(children: [
          for (var s = 1; s <= 3; s++) ...[
            if (s > 1) const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                decoration: BoxDecoration(color: AppColors.stageTint(s), borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('$s단계 | ${stageShortName(s)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: AppColors.stageInk(s))),
                  const SizedBox(height: 6),
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Text('${counts[s - 1]}',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.stageInk(s))),
                    const SizedBox(width: 2),
                    Text('건', style: TextStyle(fontSize: 11, color: AppColors.stageInk(s))),
                  ]),
                  const SizedBox(height: 2),
                  Text(pct(counts[s - 1]), style: TextStyle(fontSize: 11, color: AppColors.stageInk(s))),
                ]),
              ),
            ),
          ],
        ]),
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