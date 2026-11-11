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
import '../widgets/owl_says.dart';

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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF8F9FC),
      child: Column(
        children: [
          _FilterBar(
            selected: _stage,
            stages: _filterStages,
            onSelected: (stage) => setState(() => _stage = stage),
          ),
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

                  // 받은 목록을 건드리지 않게 복사해서 최신순으로 정렬한다
                  final shown =
                      events
                          .where((e) => _stage == null || e.stage == _stage)
                          .toList()
                        ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  final now = DateTime.now();
                  return _scroll([
                    _Summary(events: events, now: now), // 요약은 단계 필터와 상관없이 전체 기준
                    if (shown.isEmpty)
                      const _Hint(text: '이 단계의 경고가 없어요')
                    else
                      ..._byDay(shown, now),
                  ]);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 최신순으로 정렬된 목록을 날짜가 바뀔 때마다 구분 줄을 끼워서 카드로 만든다
  static List<Widget> _byDay(List<SleepEvent> sorted, DateTime now) {
    final counts = <String, int>{};
    for (final e in sorted) {
      counts.update(_dayKey(e.createdAt), (n) => n + 1, ifAbsent: () => 1);
    }
    final out = <Widget>[];
    String? lastKey;
    for (final e in sorted) {
      final key = _dayKey(e.createdAt);
      if (key != lastKey) {
        out.add(
          _DayHeader(label: _dayLabel(e.createdAt, now), count: counts[key]!),
        );
        lastKey = key;
      }
      out.add(_EventCard(event: e));
    }
    return out;
  }

  // 당겨서 새로고침이 안내 문구 화면에서도 되도록 항상 스크롤 가능하게 둔다
  Widget _scroll(List<Widget> children) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
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

// 목록 맨 위 남색 띠 (Figma 시안 '졸음운전 감지 앱3' 운행 기록, 11/12 — 예전 건수 요약 대신)
class _Summary extends StatelessWidget {
  final List<SleepEvent> events;
  final DateTime now;
  const _Summary({required this.events, required this.now});

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
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.asset(
              OwlSays.body(0),
              width: 62,
              height: 62,
              fit: BoxFit.contain,
            ),
          ),
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
      padding: const EdgeInsets.only(top: 20, bottom: 9, left: 2),
      child: Semantics(
        header: true,
        label: '$label $count건',
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
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

  // 시안의 둥근 알약 버튼 (선택 = 남색 바탕 흰 글)
  Widget _pill(String text, bool on, VoidCallback tap) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Material(
      color: on ? AppColors.navy : Colors.white,
      shape: StadiumBorder(
        side: BorderSide(color: on ? AppColors.navy : AppColors.cardBorder),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: tap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: on ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft, // 시안처럼 왼쪽부터
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(18, 7, 18, 15),
        child: Row(
          children: [
            _pill('전체', selected == null, () => onSelected(null)),
            for (final stage in stages)
              _pill(
                SleepEvent.stageLabels[stage],
                selected == stage,
                () => onSelected(stage),
              ),
          ],
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

  @override
  Widget build(BuildContext context) {
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
          // TODO(상세 화면): 경고 상세 화면이 생기면 여기서 연다 — 예) Navigator.push(... EventDetailScreen(event: event))
          onTap: () {},
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
