// ═══════════════════════════════════════════════════════════════
// models/drive_status.dart — POST /drive/ping 응답 모양 (+ DriveState: GET /drive/state)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: (신규) sleep_response.dart 모양
//
// [이 파일이 하는 일]
//   - stage · status · driveMin · restDue · restMessage
//   - drive_screen 이 30초마다 받아 화면 색 · 휴게 배너를 갱신 (1단계 자동 해제 · 관리자 조치완료 반영)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

class DriveStatus {
  final int stage;
  final String status;
  final int driveMin;
  final bool restDue;
  final String restMessage;

  DriveStatus({
    required this.stage,
    required this.status,
    required this.driveMin,
    required this.restDue,
    required this.restMessage,
  });

  factory DriveStatus.fromJson(Map<String, dynamic> json) {
    return DriveStatus(
      stage: (json['stage'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? '',
      driveMin: (json['drive_min'] as num?)?.toInt() ?? 0,
      restDue: json['rest_due'] as bool? ?? false,
      restMessage: json['rest_message'] as String? ?? '',
    );
  }
}

/// GET /drive/state 응답 — 앱을 껐다 켰을 때 '진행 중인 운행'을 이어 가기 위한 서버의 지금 상태
///   active : 이어서 운행할 것이 있음 (2 · 3단계 · 휴식 중 · 최근 ping) → 홈 화면에 [이어서 운행] 배너
///   resting / restLeftSec : 쉬는 중이면 남은 초 (휴식 화면을 이어 연다)
///   summary / guidance : 지금 단계를 만든 가장 최근 경고의 글 (이어서 연 경고 화면에 보여 줌)
class DriveState {
  final bool active;
  final int stage;
  final String status;
  final bool resting;
  final int restLeftSec;
  final int driveMin;
  final String summary;
  final String guidance;

  const DriveState({
    required this.active,
    required this.stage,
    required this.status,
    required this.resting,
    required this.restLeftSec,
    required this.driveMin,
    required this.summary,
    required this.guidance,
  });

  factory DriveState.fromJson(Map<String, dynamic> json) {
    return DriveState(
      active: json['active'] as bool? ?? false,
      stage: (json['stage'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? '',
      resting: json['resting'] as bool? ?? false,
      restLeftSec: (json['rest_left_sec'] as num?)?.toInt() ?? 0,
      driveMin: (json['drive_min'] as num?)?.toInt() ?? 0,
      summary: json['summary'] as String? ?? '',
      guidance: json['guidance'] as String? ?? '',
    );
  }
}
