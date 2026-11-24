// widgets/month_picker.dart — (11/24 사용자 요청) 아래에서 올라오는 '연도 · 달 고르기' 창
//   MY '운행 분석' 카드와 운행 기록 달력 제목을 누르면 열림
//   위: 손잡이 · '기간 선택' / 가운데: ‹ 2026년 › / 아래: 1월 ~ 12월 알약 (고른 달 = 남색 · 아직 안 온 달 = 흐림)
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../theme.dart';

/// 연도 · 달을 고르면 그 달 1일을 돌려준다 (닫으면 null). first = 고를 수 있는 가장 이른 달
Future<DateTime?> showMonthPicker(BuildContext context, {required DateTime initial, DateTime? first}) {
  final now = DateTime.now();
  final earliest = first ?? DateTime(now.year - 2, 1);
  var year = initial.year;
  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.card + 4))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(width: 36, height: 5, decoration: BoxDecoration(color: AppleGray.separator, borderRadius: BorderRadius.circular(99))),
            ),
            const SizedBox(height: 16),
            const Text('기간 선택', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.textPrimary)),
            const SizedBox(height: 14),
            // 연도 — 화살표로 앞뒤 해
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              IconButton(
                onPressed: year > earliest.year ? () => setSheet(() => year--) : null,
                icon: const Icon(Icons.chevron_left_rounded, size: 26),
                color: AppColors.textPrimary,
                disabledColor: AppleGray.separator,
              ),
              SizedBox(
                width: 110,
                child: Text('$year년',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ),
              IconButton(
                onPressed: year < now.year ? () => setSheet(() => year++) : null,
                icon: const Icon(Icons.chevron_right_rounded, size: 26),
                color: AppColors.textPrimary,
                disabledColor: AppleGray.separator,
              ),
            ]),
            const SizedBox(height: 12),
            // 달 — 4칸 x 3줄 알약
            GridView.count(
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (var m = 1; m <= 12; m++)
                  Builder(builder: (_) {
                    final d = DateTime(year, m);
                    final off = d.isAfter(DateTime(now.year, now.month)) || d.isBefore(DateTime(earliest.year, earliest.month));
                    final sel = year == initial.year && m == initial.month;
                    return GestureDetector(
                      onTap: off ? null : () => Navigator.of(ctx).pop(d),
                      child: Container(
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: sel ? AppColors.navy : AppColors.field,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text('$m월',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel ? Colors.white : (off ? AppleGray.tertiaryLabel : AppColors.textPrimary),
                            )),
                      ),
                    );
                  }),
              ],
            ),
          ]),
        ),
      ),
    ),
  );
}

/// (11/24 사용자 요청 · 보내 준 아이폰 사진) 그 자리에서 펼쳐지는 흰 바탕 날짜 바퀴 — 아래에서 올라오는 창 없음
///   [년 | 월 | 일] (withDay=false 면 [년 | 월]) · 가운데 옅은 회색 띠 · 돌리면 바로 onChanged · 아직 안 온 날은 오늘로
class MonthWheel extends StatefulWidget {
  final DateTime initial;
  final ValueChanged<DateTime> onChanged;
  final bool withDay;
  final int years;
  const MonthWheel({super.key, required this.initial, required this.onChanged, this.withDay = false, this.years = 3});

  @override
  State<MonthWheel> createState() => _MonthWheelState();
}

class _MonthWheelState extends State<MonthWheel> {
  late final DateTime _now = DateTime.now();
  late final int _firstYear = _now.year - widget.years + 1;
  late int _y = widget.initial.year.clamp(_firstYear, _now.year), _m = widget.initial.month, _d = widget.initial.day;
  late final _yc = FixedExtentScrollController(initialItem: _y - _firstYear);
  late final _mc = FixedExtentScrollController(initialItem: _m - 1);
  late final _dc = FixedExtentScrollController(initialItem: _d - 1);

  @override
  void dispose() {
    _yc.dispose();
    _mc.dispose();
    _dc.dispose();
    super.dispose();
  }

  void _emit() {
    final dim = DateTime(_y, _m + 1, 0).day;
    var r = DateTime(_y, _m, widget.withDay ? _d.clamp(1, dim) : 1);
    final today = DateTime(_now.year, _now.month, _now.day);
    if (r.isAfter(today)) r = widget.withDay ? today : DateTime(_now.year, _now.month);
    widget.onChanged(r);
  }

  Widget _wheel(FixedExtentScrollController c, int count, String Function(int) label, ValueChanged<int> onSel, int flex) => Expanded(
        flex: flex,
        child: CupertinoPicker(
          scrollController: c,
          itemExtent: 36,
          diameterRatio: 1.3,
          squeeze: 1.0,
          backgroundColor: Colors.transparent,
          selectionOverlay: const SizedBox.shrink(), // 띠는 한 줄로 길게 (아래 Stack)
          onSelectedItemChanged: onSel,
          children: [
            for (var i = 0; i < count; i++)
              Center(child: Text(label(i), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w400, color: AppColors.textPrimary))),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            height: 36,
            decoration: BoxDecoration(color: const Color(0xFFEFF0F4), borderRadius: BorderRadius.circular(9)),
          ),
          Row(children: [
            _wheel(_yc, _now.year - _firstYear + 1, (i) => '${_firstYear + i}년', (i) {
              _y = _firstYear + i;
              _emit();
            }, 3),
            _wheel(_mc, 12, (i) => '${i + 1}월', (i) {
              _m = i + 1;
              _emit();
            }, 2),
            if (widget.withDay)
              _wheel(_dc, 31, (i) => '${i + 1}일', (i) {
                _d = i + 1;
                _emit();
              }, 2),
          ]),
        ]),
      );
}

/// (11/24 사용자 요청 · 보내 준 아이폰 사진 그대로) 아래에서 올라오는 날짜 바퀴
///   회색 바탕 · 큰 글씨 · 가운데 진한 회색 띠 · [월 | 일 | 년] 순서. 위 오른쪽 [완료] 만. withDay=false 면 [월 | 년]
Future<DateTime?> showDateWheel(BuildContext context, {required DateTime initial, bool withDay = true, int years = 3}) {
  final now = DateTime.now();
  final firstYear = now.year - years + 1;
  var y = initial.year.clamp(firstYear, now.year), m = initial.month, d = initial.day;
  int daysIn(int yy, int mm) => DateTime(yy, mm + 1, 0).day;
  final yc = FixedExtentScrollController(initialItem: y - firstYear);
  final mc = FixedExtentScrollController(initialItem: m - 1);
  final dc = FixedExtentScrollController(initialItem: d - 1);
  const bg = Color(0xFFD1D4DA); // 아이폰 날짜 바퀴 회색 바탕
  Widget wheel(FixedExtentScrollController c, int count, String Function(int) label, ValueChanged<int> onSel, {int flex = 1}) => Expanded(
        flex: flex,
        child: CupertinoPicker(
          scrollController: c,
          itemExtent: 46,
          diameterRatio: 1.35,
          squeeze: 1.0,
          backgroundColor: Colors.transparent,
          selectionOverlay: const SizedBox.shrink(), // 띠는 아래에서 한 줄로 길게
          onSelectedItemChanged: onSel,
          children: [
            for (var i = 0; i < count; i++)
              Center(child: Text(label(i), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w400, color: Colors.black))),
          ],
        ),
      );
  DateTime result() {
    var r = DateTime(y, m, withDay ? d.clamp(1, daysIn(y, m)) : 1);
    final today = DateTime(now.year, now.month, now.day);
    if (r.isAfter(today)) r = withDay ? today : DateTime(now.year, now.month);
    return r;
  }

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: bg,
    shape: const RoundedRectangleBorder(),
    builder: (ctx) => SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          height: 44,
          color: const Color(0xFFF7F7F8),
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: 8),
          child: TextButton(
            onPressed: () => Navigator.of(ctx).pop(result()),
            child: const Text('완료', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.navy)),
          ),
        ),
        SizedBox(
          height: 250,
          child: Stack(alignment: Alignment.center, children: [
            // 가운데 진한 회색 띠 — 화면 폭 거의 끝까지 · 둥근 모서리
            Container(
              height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(color: const Color(0xFFB4B8C0), borderRadius: BorderRadius.circular(10)),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(children: [
                wheel(mc, 12, (i) => '${i + 1}월', (i) => m = i + 1, flex: 4),
                if (withDay) wheel(dc, 31, (i) => (i + 1).toString().padLeft(2, '0'), (i) => d = i + 1, flex: 2),
                wheel(yc, now.year - firstYear + 1, (i) => '${firstYear + i}', (i) => y = firstYear + i, flex: 3),
              ]),
            ),
          ]),
        ),
      ]),
    ),
  ).whenComplete(() {
    yc.dispose();
    mc.dispose();
    dc.dispose();
  });
}
