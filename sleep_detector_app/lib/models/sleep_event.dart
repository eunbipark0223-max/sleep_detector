// ═══════════════════════════════════════════════════════════════
// models/sleep_event.dart — 경고 1건 (운행 기록 목록)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/models/hazard.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - GET /events/my 의 한 줄
//   - stageLabel (0~3 이름) · reason 이름
//   -   microsleep 미세수면 · perclos 피로 누적 · rest_overdue 휴게 미준수 · no_response 음성 응답 없음
//
// [주의]
//   - 칸 이름은 서버 schema/response.py 의 SleepEventResponse 와 같다 (snake_case → camelCase)
//   - report 는 객체로 온다 (situation · stage_reason · regulation · recommended_action · location · eye · driving_quiz · rest).
//     혹시 문자열로 오면 JSON 으로 풀어서 쓴다
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:convert';

class SleepEvent {
  static const List<String> stageLabels = ['정상', '주의', '휴식 권고', '긴급'];
  static const Map<String, String> reasonLabels = {
    'microsleep': '미세수면',
    'perclos': '피로 누적',
    'rest_overdue': '휴게 미준수',
    'no_response': '음성 응답 없음',
  };

  final int id;
  final int userId;
  final int stage; // 0~3
  final String status; // 미확인 · 확인 · 조치완료 · 휴식완료
  final String reason; // microsleep · perclos · rest_overdue · no_response
  final double? ear;
  final double? eyeClosedProb;
  final String? method; // ear · cnn · mlkit
  final double? perclos;
  final String summary;
  final String guidance;
  final Map<String, dynamic> report;
  final String? photoUrl;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  const SleepEvent({
    required this.id,
    required this.userId,
    required this.stage,
    required this.status,
    required this.reason,
    this.ear,
    this.eyeClosedProb,
    this.method,
    this.perclos,
    this.summary = '',
    this.guidance = '',
    this.report = const {},
    this.photoUrl,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  /// 단계 이름 (0 정상 · 1 주의 · 2 휴식 권고 · 3 긴급)
  String get stageLabel => stageLabels[stage.clamp(0, 3)];

  /// 경고 종류 이름. 모르는 값이면 서버가 준 글자 그대로.
  String get reasonLabel => reasonLabels[reason] ?? reason;

  /// 관리자 웹에서 빨간 줄로 보이는 경고 (3단계 · 음성 응답 없음)
  bool get isUrgent => stage == 3 || reason == 'no_response';

  /// 보고서 속 운전 중 퀴즈 기록 (type · asked · heard · passed · answer_sec)
  List<Map<String, dynamic>> get drivingQuiz {
    final raw = report['driving_quiz'];
    if (raw is! List) return const [];
    return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  /// 보고서 속 휴식 기록 (started · resumed · minutes). 없으면 null
  Map<String, dynamic>? get rest {
    final raw = report['rest'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  factory SleepEvent.fromJson(Map<String, dynamic> json) {
    return SleepEvent(
      id: _toInt(json['id']),
      userId: _toInt(json['user_id']),
      stage: _toInt(json['stage']),
      status: '${json['status'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
      ear: _toDouble(json['ear']),
      eyeClosedProb: _toDouble(json['eye_closed_prob']),
      method: json['method'] as String?,
      perclos: _toDouble(json['perclos']),
      summary: '${json['summary'] ?? ''}',
      guidance: '${json['guidance'] ?? ''}',
      report: _toReport(json['report']),
      photoUrl: json['photo_url'] as String?,
      latitude: _toDouble(json['latitude']),
      longitude: _toDouble(json['longitude']),
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}') ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  // 수업에서 배운 '5' 문자열 사고 방지 — 숫자 칸이 글자로 와도 숫자로 바꿔 읽는다
  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static double? _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

  static Map<String, dynamic> _toReport(dynamic raw) {
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const {};
  }
}
