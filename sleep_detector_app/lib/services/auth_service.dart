// ═══════════════════════════════════════════════════════════════
// services/auth_service.dart — 회원가입 · 로그인 · 구글 로그인 · 토큰 저장
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/services/auth_service.dart (🟢 그대로 복사)
//
// [이 파일이 하는 일]
//   - 수업 파일을 그대로 복사해서 쓴다 (토큰은 flutter_secure_storage)
//
// [서버 약속 — sleep_detector_api/routers/user.py]
//   - POST /users/signup  {email, password, name, phone, vehicle_no, privacy_agreed} → 201 사용자 · 이미 있으면 409 · 비밀번호 · 전화 · 차량번호 · 동의 규칙 어기면 422(메시지 목록)
//   - POST /users/login   {email, password}                      → {success, access_token, token_type, user}
//   - POST /users/google  {email, name, firebase_uid}            → 로그인과 같은 응답 (구글 로그인 뒤 서버 JWT 로 통일)
//   - GET  /users/me      Authorization: Bearer 토큰              → 내 정보 (토큰이 틀리면 401)
//   - POST · GET · DELETE /users/me/photo                        → 프로필 사진 올리기(멀티파트 file) · 받기(토큰 필요) · 지우기
//   - PATCH /users/me     {phone?, vehicle_no?}                  → 내 전화번호 · 차량번호 저장 (빠진 칸은 그대로, '' 면 지움, 형식이 틀리면 422)
//
// [쓰는 법]
//   - 실패는 AuthException(message) 으로 던진다 — message 는 화면에 그대로 보여 줘도 되는 글 (서버 detail · 422 메시지)
//   - 다른 서비스(api_service)는 await AuthService.authHeaders() 로 토큰 헤더를 받아 쓴다
//   - 서버 주소: config.dart 의 AppConfig.baseUrl 한 곳만 쓴다 (모든 서비스가 같은 값)
//     기본 http://10.0.2.2:8000 (에뮬레이터). 실기기는 flutter run --dart-define=API_BASE_URL=http://PC주소:8000
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../config.dart';

/// 화면에 그대로 보여 줘도 되는 오류 글을 담는다.
/// (11/17) 구글 계정 고르기 창을 닫음 — 오류가 아니라서 화면에 아무 말도 하지 않는다
class GoogleCanceled implements Exception {
  const GoogleCanceled();
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;
  const AuthException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static const String _tokenKey = 'access_token';
  static const Duration _timeout = Duration(seconds: 15);
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static bool _googleReady = false;

  // ── 토큰 저장 ────────────────────────────────────────────────
  static Future<String?> getToken() => _storage.read(key: _tokenKey);

  static Future<void> saveToken(String token) => _storage.write(key: _tokenKey, value: token);

  static Future<void> clearToken() => _storage.delete(key: _tokenKey);

  static Future<bool> isLoggedIn() async => (await getToken()) != null;

  // ── 내 눈 기준 (운행 시작 전 측정값) ─────────────────────────────
  // 앱을 껐다 켜고 [이어서 운행]으로 들어올 때 측정 화면을 건너뛰어도 같은 기준을 쓰도록 폰에 저장해 둔다.
  // 로그아웃하면 같이 지운다 (다른 사람이 같은 폰으로 로그인해도 남의 기준이 쓰이지 않게)
  static const String _eyeThresholdKey = 'eye_threshold';

  static Future<void> saveEyeThreshold(double value) =>
      _storage.write(key: _eyeThresholdKey, value: value.toString());

  /// 저장된 내 눈 기준. 없거나 이상한 값이면 null → 받는 쪽이 기본 기준을 쓴다
  static Future<double?> getEyeThreshold() async {
    try {
      final v = double.tryParse(await _storage.read(key: _eyeThresholdKey) ?? '');
      return (v != null && v >= AppConfig.calibMin && v <= AppConfig.calibMax) ? v : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> clearEyeThreshold() => _storage.delete(key: _eyeThresholdKey);

  // (11/17 C) 알림 화면을 마지막으로 본 시각 — 그 뒤에 생긴 경고만 '새 알림' (빨간 점 · 숫자)
  static const String _noticeSeenKey = 'notice_seen_at';
  static Future<DateTime?> getNoticeSeenAt() async =>
      DateTime.tryParse(await _storage.read(key: _noticeSeenKey) ?? '');
  static Future<void> saveNoticeSeenAt(DateTime t) => _storage.write(key: _noticeSeenKey, value: t.toIso8601String());

  // (11/18 C) 알림 = 관리자가 조치를 완료한 경고만. 조치 시각은 서버가 안 알려 줘서 '이미 본 경고 id' 로 읽음을 가린다
  static const String _noticeIdsKey = 'notice_seen_ids';
  static Future<Set<int>> getNoticeSeenIds() async =>
      (await _storage.read(key: _noticeIdsKey) ?? '').split(',').map(int.tryParse).whereType<int>().toSet();
  static Future<void> saveNoticeSeenIds(Set<int> ids) => _storage.write(key: _noticeIdsKey, value: ids.join(','));

  /// 로그인이 필요한 요청에 붙일 헤더 (토큰이 없으면 Authorization 없이)
  static Future<Map<String, String>> authHeaders() async {
    final token = await getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ── 회원가입 · 로그인 ────────────────────────────────────────
  /// 이메일 회원가입. 가입만 하고 로그인은 하지 않는다 (가입 뒤 login 을 부른다).
  /// 전화번호 · 차량번호는 서버가 형식을 검사해 정리해서 users 에 저장하고, 틀리면 422 문구가 AuthException 으로 온다.
  /// privacyAgreed 는 개인정보 수집 · 이용 동의 (false 면 서버가 거절 — 화면에서 먼저 막아 둔다).
  static Future<Map<String, dynamic>> signup({
    required String email,
    required String password,
    required String name,
    String? phone,
    String? vehicleNo,
    bool privacyAgreed = false,
    String? empNo, // (11/17 C) 사번 — 보내면 phoneToken 도 꼭 (서버가 전화 인증을 확인)
    String? phoneToken,
    String? emailToken, // (11/17 C) 이메일 인증 표 — empNo 를 보내면 꼭
  }) async {
    final res = await _send(() => http.post(_uri('/users/signup'), headers: _json, body: jsonEncode({
      'email': email,
      'password': password,
      'name': name,
      'phone': ?phone,
      'vehicle_no': ?vehicleNo,
      'privacy_agreed': privacyAgreed,
      'emp_no': ?empNo,
      'phone_token': ?phoneToken,
      'email_token': ?emailToken,
    })));
    if (res.statusCode != 201 && res.statusCode != 200) throw _error(res);
    return _decode(res);
  }

  /// (11/17 C) 회원가입 1단계 — 사번이 회사 명단에 있고 아직 가입 안 했는지. 맞으면 서버가 정리한 사번을 돌려준다
  static Future<String> checkEmployee(String empNo) async {
    final res = await _send(() => http.post(_uri('/users/employee/check'), headers: _json, body: jsonEncode({'emp_no': empNo})));
    if (res.statusCode != 200) throw _error(res);
    return (_decode(res)['emp_no'] ?? empNo).toString();
  }

  /// (11/17 C) 전화번호 인증번호 받기. 시연용 서버는 문자 대신 번호를 돌려준다 (진짜 문자를 보내면 null)
  static Future<String?> sendPhoneCode(String phone) async {
    final res = await _send(() => http.post(_uri('/users/phone/send'), headers: _json, body: jsonEncode({'phone': phone})));
    if (res.statusCode != 200) throw _error(res);
    final code = _decode(res)['demo_code'];
    return code?.toString();
  }

  /// (11/17 C) 이메일 인증번호 받기. 시연용 서버는 메일 대신 번호를 돌려준다
  static Future<String?> sendEmailCode(String email) async {
    final res = await _send(() => http.post(_uri('/users/email/send'), headers: _json, body: jsonEncode({'email': email})));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res)['demo_code']?.toString();
  }

  /// (11/17 C) 이메일 인증번호 확인 — 맞으면 가입할 때 같이 보낼 인증 표(email_token)
  static Future<String> verifyEmailCode(String email, String code) async {
    final res = await _send(
        () => http.post(_uri('/users/email/verify'), headers: _json, body: jsonEncode({'email': email, 'code': code})));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res)['email_token'].toString();
  }

  /// (11/17 C) 인증번호 확인 — 맞으면 가입할 때 같이 보낼 인증 표(phone_token)
  static Future<String> verifyPhoneCode(String phone, String code) async {
    final res = await _send(
        () => http.post(_uri('/users/phone/verify'), headers: _json, body: jsonEncode({'phone': phone, 'code': code})));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res)['phone_token'].toString();
  }

  /// 이메일 로그인. 성공하면 토큰을 저장하고 사용자 정보(id · email · name · role)를 돌려준다.
  static Future<Map<String, dynamic>> login({required String email, required String password}) async {
    final res = await _send(() => http.post(_uri('/users/login'), headers: _json, body: jsonEncode({'email': email, 'password': password})));
    if (res.statusCode != 200) throw _error(res);
    return _saveLogin(_decode(res));
  }

  /// 구글 로그인 → Firebase 로 확인 → 서버에 email · name · firebase_uid 를 보내 서버 JWT 를 받는다.
  static Future<Map<String, dynamic>> loginWithGoogle() async {
    final User firebaseUser;
    try {
      if (!_googleReady) {
        await GoogleSignIn.instance.initialize();
        _googleReady = true;
      }
      final account = await GoogleSignIn.instance.authenticate();
      final credential = GoogleAuthProvider.credential(idToken: account.authentication.idToken);
      final result = await FirebaseAuth.instance.signInWithCredential(credential);
      final user = result.user;
      if (user == null || user.email == null) throw const AuthException('구글 계정 정보를 가져오지 못했어요');
      firebaseUser = user;
    } on GoogleSignInException catch (e) {
      // (11/17) 기사님이 계정 고르기 창을 닫은 것 → 화면에 문구 없이 그냥 로그인 화면 그대로 (GoogleCanceled)
      if (e.code == GoogleSignInExceptionCode.canceled) throw const GoogleCanceled();
      throw AuthException('구글 로그인에 실패했어요 (${e.code.name})');
    } on FirebaseAuthException catch (e) {
      throw AuthException('구글 로그인에 실패했어요 (${e.code})');
    }

    final email = firebaseUser.email!;
    final name = (firebaseUser.displayName ?? '').trim().isNotEmpty ? firebaseUser.displayName!.trim() : email.split('@').first;
    final res = await _send(() => http.post(_uri('/users/google'), headers: _json, body: jsonEncode({'email': email, 'name': name, 'firebase_uid': firebaseUser.uid})));
    if (res.statusCode != 200) {
      await logout(); // 서버가 거절하면 Firebase 쪽 로그인도 풀어 둔다 (다음에 다시 고를 수 있게)
      throw _error(res);
    }
    return _saveLogin(_decode(res));
  }

  /// (11/17 팀장) 기사 이름만 — '박은비' (없으면 '') · 서버 detect._driver_name 과 같음
  ///   화면(홈 인사): '$이름 기사님' · 음성: '$이름님' — 이름이 없으면 둘 다 '기사님'
  static String driverName(String? name) => (name ?? '').trim();

  /// 저장된 토큰으로 내 정보를 가져온다 (스플래시의 자동 로그인 확인용).
  /// 토큰이 없거나 서버가 거절(401 · 404)하면 null — 그때는 토큰을 지운다. 연결 오류는 AuthException (로그아웃시키지 않음).
  static Future<Map<String, dynamic>?> me() async {
    final token = await getToken();
    if (token == null) return null;
    final res = await _send(() async => http.get(_uri('/users/me'), headers: await authHeaders()));
    if (res.statusCode == 200) return _decode(res);
    if (res.statusCode == 401 || res.statusCode == 404) {
      await clearToken();
      return null;
    }
    throw _error(res);
  }

  // ── 연락처 · 차량번호 (서버: PATCH /users/me) ─────────────────────────────
  /// 내 전화번호 · 차량번호 저장 (관리자가 경고를 보고 바로 연락할 때 쓴다).
  /// 넘기지 않은(null) 칸은 그대로 두고, 빈 글자('')를 넘기면 서버가 지운다. 돌려받는 것은 바뀐 내 정보.
  /// 형식이 틀리면(422) 서버 문구가 AuthException 으로 온다 (예: '전화번호 형식이 올바르지 않아요 (예: 010-1234-5678)').
  static Future<Map<String, dynamic>> updateProfile({String? phone, String? vehicleNo, String? name}) async {
    final body = <String, dynamic>{
      'name': ?name, // (11/18) 내 정보에서 이름 바꾸기
      'phone': ?phone,
      'vehicle_no': ?vehicleNo,
    };
    final res = await _send(() async => http.patch(_uri('/users/me'), headers: await authHeaders(), body: jsonEncode(body)));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res);
  }

  /// (11/18 C) 비밀번호 변경 — PUT /users/me/password. 지금 비밀번호가 틀리거나 새 비밀번호 규칙이 틀리면 서버 문구로 AuthException
  static Future<void> changePassword({required String current, required String next}) async {
    final res = await _send(() async => http.put(_uri('/users/me/password'),
        headers: await authHeaders(), body: jsonEncode({'current_password': current, 'new_password': next})));
    if (res.statusCode != 200) throw _error(res);
  }

  /// (11/18 C) 이메일 변경 1단계 — 새 이메일 + 지금 비밀번호 → 새 이메일로 인증번호. 시연용 서버는 번호(dev_code)를 돌려준다
  static Future<String?> requestEmailChange({required String newEmail, required String currentPassword}) async {
    final res = await _send(() async => http.post(_uri('/users/me/email/request'),
        headers: await authHeaders(), body: jsonEncode({'new_email': newEmail, 'current_password': currentPassword})));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res)['dev_code']?.toString();
  }

  /// (11/18 C) 이메일 변경 2단계 — 인증번호가 맞으면 바뀐 내 정보
  static Future<Map<String, dynamic>> confirmEmailChange({required String newEmail, required String code}) async {
    final res = await _send(() async => http.post(_uri('/users/me/email/confirm'),
        headers: await authHeaders(), body: jsonEncode({'new_email': newEmail, 'code': code})));
    if (res.statusCode != 200) throw _error(res);
    return _decode(res);
  }

  /// (11/18 C) 이메일 찾기 — 전화번호 인증 표(phone_token)로 그 번호로 가입한 이메일(가려진 것) 목록
  static Future<List<Map<String, dynamic>>> findEmail({required String phone, required String phoneToken}) async {
    final res = await _send(() => http.post(_uri('/users/find-email'),
        headers: _json, body: jsonEncode({'phone': phone, 'phone_token': phoneToken})));
    if (res.statusCode != 200) throw _error(res);
    final list = _decode(res)['emails'];
    return list is List ? list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() : const [];
  }

  /// (11/18 C) 비밀번호 찾기 — 가입한 이메일 인증 표(email_token)로 새 비밀번호 저장
  static Future<void> resetPassword({required String email, required String emailToken, required String newPassword}) async {
    final res = await _send(() => http.post(_uri('/users/password/reset'),
        headers: _json, body: jsonEncode({'email': email, 'email_token': emailToken, 'new_password': newPassword})));
    if (res.statusCode != 200) throw _error(res);
  }

  // ── 프로필 사진 (서버: POST · GET · DELETE /users/me/photo) ──────────────
  /// 내 프로필 사진 바이트. 사진이 없으면(404) null.
  /// 사진은 로그인 토큰이 있어야 받을 수 있어서(주소만으로는 안 열림) Image.network 대신 바이트로 받아 Image.memory 로 그린다.
  static Future<Uint8List?> fetchPhoto() async {
    final res = await _send(() async => http.get(_uri('/users/me/photo'), headers: await authHeaders()));
    if (res.statusCode == 200) return res.bodyBytes;
    if (res.statusCode == 404) return null;
    throw _error(res);
  }

  /// 프로필 사진 올리기. 서버가 정한 확장자(jpg · jpeg · png · webp · heic) · 5MB 를 어기면 서버 문구가 AuthException 으로 온다.
  static Future<void> uploadPhoto(Uint8List bytes, String filename) async {
    final headers = await authHeaders()
      ..remove('Content-Type'); // 멀티파트의 Content-Type 은 http 가 경계값과 함께 직접 붙인다
    final res = await _send(() async {
      final request = http.MultipartRequest('POST', _uri('/users/me/photo'))
        ..headers.addAll(headers)
        ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename, contentType: _imageType(filename)));
      return http.Response.fromStream(await request.send());
    });
    if (res.statusCode != 200) throw _error(res);
  }

  /// 프로필 사진 지우기 (서버도 파일을 지운다).
  static Future<void> deletePhoto() async {
    final res = await _send(() async => http.delete(_uri('/users/me/photo'), headers: await authHeaders()));
    if (res.statusCode != 200) throw _error(res);
  }

  static MediaType _imageType(String filename) {
    final lower = filename.toLowerCase();
    if (lower.endsWith('.png')) return MediaType('image', 'png');
    if (lower.endsWith('.webp')) return MediaType('image', 'webp');
    if (lower.endsWith('.heic')) return MediaType('image', 'heic');
    return MediaType('image', 'jpeg');
  }

  /// 로그아웃 — 토큰을 지우고 Firebase · 구글 로그인도 푼다 (둘 중 하나가 실패해도 토큰은 이미 지워진다).
  static Future<void> logout() async {
    await clearToken();
    try {
      await clearEyeThreshold();
    } catch (_) {}
    try {
      await _storage.delete(key: _noticeSeenKey); // (11/17) 다른 계정으로 들어오면 알림을 처음부터 '안 읽음' 으로
      await _storage.delete(key: _noticeIdsKey);
    } catch (_) {}
    try {
      await FirebaseAuth.instance.signOut();
    } catch (_) {}
    try {
      if (_googleReady) await GoogleSignIn.instance.signOut();
    } catch (_) {}
  }

  // ── 안쪽 도우미 ──────────────────────────────────────────────
  static const Map<String, String> _json = {'Content-Type': 'application/json'};

  static Uri _uri(String path) => Uri.parse('${AppConfig.baseUrl}$path');

  static Future<http.Response> _send(Future<http.Response> Function() request) async {
    try {
      return await request().timeout(_timeout);
    } on TimeoutException {
      throw const AuthException('서버 응답이 없어요. 잠시 뒤 다시 시도해 주세요');
    } catch (_) {
      throw const AuthException('서버에 연결할 수 없어요. 네트워크와 서버 주소를 확인해 주세요');
    }
  }

  // 서버는 UTF-8 JSON 이지만 charset 표시가 없으면 http 가 한글을 깨뜨릴 수 있어 bodyBytes 를 직접 UTF-8 로 푼다
  static Map<String, dynamic> _decode(http.Response res) {
    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return data is Map<String, dynamic> ? data : <String, dynamic>{};
  }

  static Future<Map<String, dynamic>> _saveLogin(Map<String, dynamic> data) async {
    final token = data['access_token'];
    if (token is! String || token.isEmpty) throw const AuthException('로그인 응답에 토큰이 없어요');
    await saveToken(token);
    final user = data['user'];
    return user is Map ? Map<String, dynamic>.from(user) : <String, dynamic>{};
  }

  /// 서버 오류 → 화면에 보여 줄 글. detail 이 글자면 그대로, 422 처럼 목록이면 msg 들을 줄바꿈으로 이어서
  /// (pydantic 이 붙이는 'Value error, ' 는 뗀다 — 비밀번호 규칙 메시지가 깔끔하게 보이게)
  static AuthException _error(http.Response res) {
    String? message;
    try {
      final detail = _decode(res)['detail'];
      if (detail is String && detail.isNotEmpty) {
        message = detail;
      } else if (detail is List) {
        final lines = detail
            .map((e) => e is Map ? '${e['msg'] ?? ''}'.replaceFirst('Value error, ', '') : '$e')
            .where((s) => s.isNotEmpty)
            .toList();
        if (lines.isNotEmpty) message = lines.join('\n');
      }
    } catch (_) {}
    return AuthException(message ?? '요청에 실패했어요 (${res.statusCode})', res.statusCode);
  }
}
