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

import '../models/sleep_response.dart';
import 'auth_service.dart';

class ApiService {
  static const String _baseUrl = String.fromEnvironment(
      'API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');

  static Uri _uri(String path) => Uri.parse('$_baseUrl$path');

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
}