// ═══════════════════════════════════════════════════════════════
// services/drive_log.dart — 운행 한 번 = [운행 시작] ~ [운행 종료] 를 폰에 적어 두기 (11/19 C)
// ═══════════════════════════════════════════════════════════════
// [왜] 홈 리포트를 '운행 1 · 운행 2' 로 묶어 보여 주기로 함 (사용자 요청 11/19).
//   두 서버 모두 지난 운행의 시작 · 종료 시각을 따로 저장하지 않아서, 앱이 누른 순간을 직접 적어 둔다.
//   - [운행 시작] (출발 전 측정이 끝나고 운행 화면에 들어갈 때) → start()
//   - [운행 종료] 에서 '네' → end()    ← 운행을 나누는 기준 = 운행 종료를 누른 때
//   - 종료 없이 새 운행을 시작하면 앞 운행은 새 운행 시작 시각에 끝난 것으로 본다
// [묶는 법] groupDrives(경고들, 운행 기록) — 운행 시간 안의 경고를 그 운행에 넣음.
//   기록이 없던 예전 경고는 60분 넘게 떨어지면 다른 운행으로 짐작해서 묶는다
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/sleep_event.dart';

/// 운행 한 번의 시작 · 종료 (종료가 없으면 아직 운행 중)
class DriveSpan {
  final DateTime start;
  final DateTime? end;
  const DriveSpan(this.start, this.end);

  Map<String, dynamic> toJson() => {'s': start.millisecondsSinceEpoch, if (end != null) 'e': end!.millisecondsSinceEpoch};
  static DriveSpan fromJson(Map<String, dynamic> j) => DriveSpan(
        DateTime.fromMillisecondsSinceEpoch(j['s'] as int),
        j['e'] == null ? null : DateTime.fromMillisecondsSinceEpoch(j['e'] as int),
      );
}

class DriveLog {
  DriveLog._();
  static const _storage = FlutterSecureStorage();
  static const _key = 'drive_spans_v1';
  static const _keep = 300; // 최근 300번만 보관

  static Future<List<DriveSpan>> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null || raw.isEmpty) return [];
      return (jsonDecode(raw) as List).map((e) => DriveSpan.fromJson(Map<String, dynamic>.from(e))).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<DriveSpan> spans) async {
    final keep = spans.length > _keep ? spans.sublist(spans.length - _keep) : spans;
    await _storage.write(key: _key, value: jsonEncode(keep.map((s) => s.toJson()).toList()));
  }

  /// [운행 시작] — 끝나지 않은 앞 운행은 지금 끝난 것으로 닫고 새 운행을 연다
  static Future<void> start() async {
    final now = DateTime.now();
    final spans = await load();
    if (spans.isNotEmpty && spans.last.end == null) spans[spans.length - 1] = DriveSpan(spans.last.start, now);
    spans.add(DriveSpan(now, null));
    await _save(spans);
  }

  /// [운행 종료] — 열려 있는 운행을 지금 닫는다 (열린 운행이 없으면 아무것도 안 함)
  static Future<void> end() async {
    final spans = await load();
    if (spans.isEmpty || spans.last.end != null) return;
    spans[spans.length - 1] = DriveSpan(spans.last.start, DateTime.now());
    await _save(spans);
  }
}

/// 홈 리포트 카드 하나 = 운행 한 번
class DriveGroup {
  final DateTime start;
  final DateTime? end; // null = 운행 중
  final List<SleepEvent> events; // 시간 순
  final bool guessed; // 기록 없이 경고 시각으로 짐작한 운행
  int number = 1; // 그날의 몇 번째 운행 (운행 1 · 운행 2)
  DriveGroup(this.start, this.end, this.events, {this.guessed = false});

  int count(int stage) => events.where((e) => e.stage == stage).length;
  bool get hasUrgent => events.any((e) => e.stage >= 3);
  DateTime get last => end ?? (events.isEmpty ? start : events.last.createdAt.toLocal());
}

/// 경고를 운행별로 묶는다 — 결과는 시작 시각 순 (오래된 것 먼저), 날마다 운행 번호 1부터
List<DriveGroup> groupDrives(List<SleepEvent> events, List<DriveSpan> spans) {
  final sorted = [...events]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  final now = DateTime.now();
  final groups = <DriveGroup>[];
  final used = <int>{};
  for (final sp in spans) {
    final to = (sp.end ?? now).add(const Duration(minutes: 1)); // 종료 직전 경고가 서버에 늦게 찍혀도 포함
    final mine = [
      for (final e in sorted)
        if (!used.contains(e.id) && !e.createdAt.toLocal().isBefore(sp.start) && e.createdAt.toLocal().isBefore(to)) e
    ];
    used.addAll(mine.map((e) => e.id));
    groups.add(DriveGroup(sp.start, sp.end, mine));
  }
  // 기록이 없던 예전 경고 — 60분 넘게 떨어지면 다른 운행
  DriveGroup? cur;
  for (final e in sorted.where((e) => !used.contains(e.id))) {
    final t = e.createdAt.toLocal();
    if (cur == null || t.difference(cur.events.last.createdAt.toLocal()).inMinutes > 60) {
      cur = DriveGroup(t, t, [e], guessed: true);
      groups.add(cur);
    } else {
      cur.events.add(e);
      groups[groups.length - 1] = DriveGroup(cur.start, t, cur.events, guessed: true);
      cur = groups.last;
    }
  }
  groups.sort((a, b) => a.start.compareTo(b.start));
  // 날마다 1번부터
  DateTime? day;
  var n = 0;
  for (final g in groups) {
    final d = DateTime(g.start.year, g.start.month, g.start.day);
    if (day != d) {
      day = d;
      n = 0;
    }
    g.number = ++n;
  }
  return groups;
}
