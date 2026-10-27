// ═══════════════════════════════════════════════════════════════
// models/drive_status.dart — POST /drive/ping 응답 모양
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