// ═══════════════════════════════════════════════════════════════
// services/api_service.dart — 서버 통신 함수 모음
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/services/api_service.dart (🟡 수정, 사진 전송은 uploadProfilePhoto 방식)
//
// [이 파일이 하는 일]
//   - 모든 요청에 로그인 토큰(JWT) 붙이기 (수업 그대로)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - sendDetect(jpgBytes, reason, closedSec, perclos, eyeOpenProb, lat, lng) → SleepResponse   POST /detect
//   - sendPing(perclos) → DriveStatus   POST /drive/ping
//   - startDrive()   POST /drive/start
//   - sendCalibration(사진 파일)   POST /drive/calibrate
//   - startRest() · resumeDrive()   POST /drive/rest · /drive/resume
//   - submitAnswer(quizId, answerText, answerSec) → passed · nextQuiz · stage · message   POST /quiz/answer
//   - fetchMyEvents() → List<SleepEvent>   GET /events/my
//   - sendChat(message)   POST /chat  (수업 앱에서 빠져 있던 함수)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';
import '../models/drive_status.dart';
import '../models/sleep_event.dart';
import '../models/sleep_response.dart';
import 'auth_service.dart';

class ApiService {
  // 서버 주소는 AppConfig.baseUrl 한 곳에서만 가져와요 (팀 규칙)
  static Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  // ── 공통 도우미 (이 파일 안에서만 쓰는 것) ──────────────────────

  // 서버가 알려 준 실패 이유를 꺼내요. 못 꺼내면 기본 문구를 써요
  static String _errorMessage(http.Response res) {
    try {
      final err = jsonDecode(utf8.decode(res.bodyBytes));
      if (err is Map && err['detail'] is String) return err['detail'] as String;
    } catch (_) {}
    return '요청에 실패했습니다 (${res.statusCode})';
  }

  // 서버에 JSON 편지를 보내고 답장(Map)을 받아요
  static Future<Map<String, dynamic>> _postJson(String path, [Map<String, dynamic>? body]) async {
    final headers = await AuthService.authHeaders();
    final res = await http
        .post(_uri(path), headers: headers, body: body == null ? null : jsonEncode(body))
        .timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }
    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // ── 함수들 (이름 약속 그대로) ───────────────────────────────────

  // sendDetect (서버에 사진전송, 졸음판정 결과 서버에서 받아오기)
  static Future<SleepResponse> sendDetect(Uint8List jpgBytes, {
    String reason = '',
    double? closedSec,
    double? perclos,
    double? eyeOpenProb,
    double? lat,
    double? lng,
  }) async {
    final headers = await AuthService.authHeaders();
    headers.remove('Content-Type');
    final request = http.MultipartRequest('POST', _uri('/detect'))
      ..headers.addAll(headers)
      ..fields['reason'] = reason
      ..fields['closed_sec'] = closedSec?.toString() ?? ''
      ..fields['perclos'] = perclos?.toString() ?? ''
      ..fields['eye_open_prob'] = eyeOpenProb?.toString() ?? ''
      ..fields['latitude'] = lat?.toString() ?? ''
      ..fields['longitude'] = lng?.toString() ?? ''
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        jpgBytes,
        filename: 'frame.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception('요청에 실패했습니다 (${res.statusCode})');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    return SleepResponse.fromJson(data);
  }

  // fetchMyEvents (서버에서 내 졸음 경고 기록 목록 받아오기)
  static Future<List<SleepEvent>> fetchMyEvents() async {
    final headers = await AuthService.authHeaders();
    final res = await http.get(_uri('/events/my'), headers: headers).timeout(const Duration(seconds: 15));

    if (res.statusCode != 200) {
      throw Exception('경고 목록을 불러오지 못했습니다 (${res.statusCode})');
    }

    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List<dynamic>;
    return list.map((e) => SleepEvent.fromJson(e as Map<String, dynamic>)).toList();
  }

  // sendPing (30초마다 "운전 중이에요, 눈 감긴 비율은 이만큼이에요" 알리고 현재 단계 받기)
  static Future<DriveStatus> sendPing([double? perclos]) async {
    final data = await _postJson('/drive/ping', {'perclos': perclos});
    return DriveStatus.fromJson(data);
  }

  // startDrive (운전 시작했어요)
  static Future<Map<String, dynamic>> startDrive() => _postJson('/drive/start');

  // sendCalibration (눈 뜬 사진으로 "내 눈 기준" 맞추기)
  static Future<Map<String, dynamic>> sendCalibration(Uint8List jpgBytes) async {
    final headers = await AuthService.authHeaders();
    headers.remove('Content-Type');
    final request = http.MultipartRequest('POST', _uri('/drive/calibrate'))
      ..headers.addAll(headers)
      ..files.add(http.MultipartFile.fromBytes(
        'file',
        jpgBytes,
        filename: 'calib.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));
    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final res = await http.Response.fromStream(streamed);

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res));
    }

    return jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
  }

  // startRest (쉬는 중이에요)
  static Future<Map<String, dynamic>> startRest() => _postJson('/drive/rest');

  // resumeDrive (다시 출발해요)
  static Future<Map<String, dynamic>> resumeDrive() => _postJson('/drive/resume');

  // submitAnswer (음성 퀴즈 답을 보내고 통과 여부 받기)
  static Future<QuizAnswerResult> submitAnswer(String quizId, String answerText, [double? answerSec]) async {
    final data = await _postJson('/quiz/answer', {
      'quiz_id': quizId,
      'answer_text': answerText,
      'answer_sec': answerSec,
    });
    return QuizAnswerResult.fromJson(data);
  }

  // sendChat (AI 규정 도우미에게 질문 보내고 답 받기)
  static Future<Map<String, dynamic>> sendChat(String message) => _postJson('/chat', {'message': message});
}

// submitAnswer 의 답장 (통과 여부 · 다음 문제 · 단계 · 안내 글)
class QuizAnswerResult {
  final bool passed;
  final VoiceQuiz? nextQuiz;
  final bool stageUp;
  final int stage;
  final String status;
  final String message;

  QuizAnswerResult({
    required this.passed,
    this.nextQuiz,
    required this.stageUp,
    required this.stage,
    required this.status,
    required this.message,
  });

  factory QuizAnswerResult.fromJson(Map<String, dynamic> json) {
    return QuizAnswerResult(
      passed: json['passed'] as bool? ?? false,
      nextQuiz: json['next_quiz'] == null
          ? null
          : VoiceQuiz.fromJson(json['next_quiz'] as Map<String, dynamic>),
      stageUp: json['stage_up'] as bool? ?? false,
      stage: (json['stage'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? '',
      message: json['message'] as String? ?? '',
    );
  }
}