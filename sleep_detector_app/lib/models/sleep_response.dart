// ═══════════════════════════════════════════════════════════════
// models/sleep_response.dart — POST /detect 응답 모양
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/models/detection_response.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - isSleep · stage · status · ear · eyeOpenProb · method · perclos · reason
//   - summary · guidance · driverVoice · sleepCount10min · regulations · eventId · earThreshold
//   - VoiceQuiz 클래스: quizId · type · speak · display · listenSec (정답 없음)
//   -   /quiz/answer 응답의 next_quiz 도 같은 VoiceQuiz 로 읽음
//   - Regulation 클래스는 수업 그대로 (title · source · content)
//
// [주의]
//   - 서버 기획안 9-3 의 칸 이름과 정확히 맞출 것 (snake_case → camelCase)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
// AI 응답 담는 그릇
// 중첩 모델 - 모델 안에 모델

// 응답 결과 JSON 문자열 이 중 첩되어 있으면 모델도 중첩
// 가장 바깥 모델 - 안에 다른 모델들을 담는다
class SleepResponse {
  // 필드(멤버 변수) 선언
  final bool isSleep;
  final bool faceFound; // 서버 사진에서 얼굴을 찾았는지 (11/11 — 고개 숙임 취소 뒤 재전송 시간 · 안내 음성)
  final int stage;
  final String status;
  final String reason;
  final double? ear;
  final double? eyeOpenProb;
  final String method;
  final double? perclos;
  final double? earThreshold;
  final String summary;
  final String guidance;
  final String driverVoice;
  final int sleepCount10min;
  final int? eventId;
  final List<Regulation> regulations;
  final VoiceQuiz? voiceQuiz;

  SleepResponse({
    required this.isSleep,
    this.faceFound = false,
    required this.stage,
    required this.status,
    required this.reason,
    this.ear,
    this.eyeOpenProb,
    required this.method,
    this.perclos,
    this.earThreshold,
    required this.summary,
    required this.guidance,
    required this.driverVoice,
    required this.sleepCount10min,
    this.eventId,
    required this.regulations,
    this.voiceQuiz,
  });

  // factory 생성자
  // 생성자 내부에서 return 키워드를 사용해 원하는 객체를 직접 리턴
  // JSON 파싱 및 데이터 변환
  // JSON(Map) 형태의 데이터를 받아 SleepResponse 모델 클래스의 인스턴스(객체)를 생성
  factory SleepResponse.fromJson(Map<String, dynamic> json){
    return SleepResponse(
      isSleep: json['is_sleep'] as bool? ?? false,
      faceFound: json['face_found'] == true,
      stage: _toInt(json['stage']),
      status: json['status'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
      ear: _toDouble(json['ear']),
      eyeOpenProb: _toDouble(json['eye_open_prob']),
      method: json['method'] as String? ?? '',
      perclos: _toDouble(json['perclos']),
      earThreshold: _toDouble(json['ear_threshold']),
      summary: json['summary'] as String? ?? '',
      guidance: json['guidance'] as String? ?? '',
      driverVoice: json['driver_voice'] as String? ?? '',
      sleepCount10min: _toInt(json['sleep_count_10min']),
      eventId: json['event_id'] == null ? null : _toInt(json['event_id']),
      regulations: (json['regulations'] as List<dynamic>? ?? [])
          .map((r) => Regulation.fromJson(r as Map<String, dynamic>))
          .toList(), // .toList()를 빼먹으면 목록이 아니라 '계산 예약'이 남는다
      voiceQuiz: json['voice_quiz'] == null
          ? null
          : VoiceQuiz.fromJson(json['voice_quiz'] as Map<String, dynamic>),
    );
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;
  static double? _toDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

}



// RAG 규정 하나
class Regulation {
  final String title; // 문서 제목
  final String source; // 출처
  final String content; // 내용

  Regulation({required this.title, required this.source, required this.content});

  Map<String, dynamic> toJson() => {'title': title, 'source': source, 'content': content};

  factory Regulation.fromJson(Map<String, dynamic> json) {
    return Regulation(
      title: json['title'] as String? ?? '관련 규정',
      source: json['source'] as String? ?? '',
      content: json['content'] as String? ?? '',
    );
  }
}

// 음성 퀴즈 한 문제 (정답은 없어요 — 서버만 알아요)
class VoiceQuiz {
  final String quizId;
  final String type;
  final String speak; // 앱이 소리로 읽을 글
  final String display; // 화면에 크게 보여 줄 글
  final int listenSec; // 몇 초 동안 들을지

  VoiceQuiz({
    required this.quizId,
    required this.type,
    required this.speak,
    required this.display,
    required this.listenSec,
  });

  factory VoiceQuiz.fromJson(Map<String, dynamic> json) {
    return VoiceQuiz(
      quizId: json['quiz_id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      speak: json['speak'] as String? ?? '',
      display: json['display'] as String? ?? '',
      listenSec: SleepResponse._toInt(json['listen_sec']),
    );
  }
}
