// ═══════════════════════════════════════════════════════════════
// services/voice_service.dart — 음성 (TTS 말하기 + STT 듣기) 한 파일
// ═══════════════════════════════════════════════════════════════
// 담당: 팀장 (11/02 C 에서 이동)   |   우선: P1
// 수업 원본: (없음, 🔴 신규) — 듣는 방식은 10/29 STT 시험 도구(lib/tools/stt_test_main.dart)에서 검증한 그대로
//
// [이 파일이 하는 일]
//   - TTS: flutter_tts, ko-KR, awaitSpeakCompletion(true) — 말이 끝날 때까지 기다림
//   -   새 음성이 오면 이전 음성을 끊고 최신 것만 (겹쳐 말하지 않게), 듣는 중이면 듣기도 멈춤
//   - STT: speech_to_text, ko_KR, 최대 10초 (서버 voice_quiz.listen_sec, 10/29 시험으로 7 → 10)
//   -   중간 결과는 onPartial 로 계속 넘기고, 반환값은 최종 결과만 (무응답 '', 인식기 없음 null)
//   - 🔴 TTS 가 끝나고 1초 뒤에만 마이크를 켠다 (바로 켜면 자기 목소리를 듣거나 첫 듣기가 소리를 못 받음)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - speak(String text)                         → 말이 끝나면 돌아옴
//   - alarm()                                    → 진동 3번 + 짧은 경고음 (오디오 패키지가 없어 TTS 로 냄)
//   - listen({type, display, listenSec, onPartial, onGuide}) → String? (최종 글자)
//       type    : 'add'(덧셈) · 'repeat'(따라 말하기) · null(그 밖의 대답) — 서버 voice_quiz.type 그대로
//       display : 따라 말하기 문장 (서버 voice_quiz.display) — 다 들었는지 판단에만 씀, 채점은 서버
//       onGuide : 화면에 크게 띄울 안내 ('🎤 말씀해 주세요' → 인식기가 끊겨 다시 켜면 '🎤 다시 한번 말씀해 주세요')
//   - lastAnswerSec                              → 마지막 listen 에서 첫 글자가 들린 시각(초), 없으면 null
//                                                  (POST /quiz/answer 의 answer_sec)
//   - stop()                                     → 말하기 · 듣기 모두 멈춤 (화면을 닫을 때)
//
// [듣는 방식 — 10/29 시연 폰 STT 시험 11차례로 정함 (조용한 곳 95%)]
//   - 안드로이드 인식기는 말이 ~3초 안 들리거나 말하다 ~1초 쉬면 혼자 끝남 → 10초 안이면 다시 켜서 계속 듣는다
//     (켤 때마다 안드로이드가 '띠링' — 두 번째부터는 화면에 '다시 한번 말씀해 주세요')
//   - 덧셈: 두 자리 수가 들리면 끝. 조각마다 인식기를 끄고 0.3초 쉼 (안 끄면 '바쁨' 오류로 답을 통째로 놓침)
//     단 0 으로 끝나는 수('칠십' → '70')는 덜 들은 것 — 서버 덧셈은 일의 자리가 1~8 끼리라 답이 0 으로 안 끝남 (11/02)
//   - 따라 말하기: 쉬어도 바로 이어 듣고(끄고 쉬면 문장 뒤를 놓침), 문장과 0.7 이상 비슷해지면 그 자리에서 끝 (11/02 0.8 → 0.7),
//     두 번째 띠링부터 10초를 새로 줌 (처음부터 다시 말할 시간)
//   - 멈춘 뒤 최종 결과를 최대 1.5초 기다림 (안 기다리면 중간 결과만 남음: '98' → '9')
//
// [주의]
//   - 경고 · 운전 중 퀴즈 · 휴식 · 휴게 알림 · 카메라 확인 · 측정 안내가 모두 이 파일을 같이 씀
//   - 녹음 · 음성 파일은 남기지 않는다 (인식 글자만)
//   - 에뮬레이터 마이크는 불안정 → STT 시험은 실기기
//   - 채점은 서버(voice_quiz_service)만 한다. 여기 유사도 계산은 '그만 들을 때' 판단용
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」 8-4 · 8-6
// ═══════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

class VoiceService {
  VoiceService._();

  // ── 숫자 (10/29 STT 시험으로 정함) ─────────────────────────────
  static const int defaultListenSec = 10; // 서버 voice_quiz.listen_sec 이 없을 때
  static const Duration micDelay = Duration(milliseconds: 1000); // TTS 끝 → 마이크
  static const double doneScore = 0.7; // 따라 말하기 '다 들음' = 서버 통과 기준(REPEAT_MIN_SCORE, 11/02 0.8 → 0.7)과 같게
  static const String guideFirst = '🎤 말씀해 주세요';
  static const String guideAgain = '🎤 다시 한번\n말씀해 주세요';

  static final FlutterTts _tts = FlutterTts();
  static final SpeechToText _stt = SpeechToText();
  static bool _ttsReady = false;
  static bool? _sttReady; // null = 아직 안 봄, false = 쓸 수 없음
  static int _speakId = 0; // 새 speak 가 오면 1 늘림 → 이전 speak 는 조용히 끝남
  static Future<void>? _speaking; // 지금 말하는 중이면 그 Future
  static DateTime? _lastSpeakEnd;
  static int _listenId = 0; // 새 listen / stop 이 오면 1 늘림 → 이전 listen 은 그만 둠

  /// 마지막 listen 에서 첫 글자가 들린 시각(초). 무응답이면 null
  static double? lastAnswerSec;

  static Future<void> _initTts() async {
    if (_ttsReady) return;
    await _tts.setLanguage('ko-KR');
    await _tts.awaitSpeakCompletion(true);
    try {
      await _tts.setAudioAttributesForNavigation(); // 안드로이드: 길안내처럼 음악 소리를 줄이고 말함
    } catch (_) {/* 다른 플랫폼 */}
    _ttsReady = true;
  }

  static Future<bool> _initStt() async {
    if (_sttReady != null) return _sttReady!;
    try {
      final ok = await _stt.initialize(onError: (e) => debugPrint('[voice] STT 오류 ${e.errorMsg}'));
      _sttReady = ok && (await _stt.locales()).any((l) => l.localeId.startsWith('ko'));
    } catch (e) {
      debugPrint('[voice] STT 준비 실패: $e');
      _sttReady = false;
    }
    return _sttReady!;
  }

  // ═══════════════════════════════════════════════════════════
  // TTS
  // ═══════════════════════════════════════════════════════════

  /// 글을 소리로 읽는다. 말하는 중이면 끊고 새 것만, 듣는 중이면 듣기도 멈춤. 말이 끝나면 돌아온다.
  static Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    final id = ++_speakId;
    await _stopListening();
    await _initTts();
    await _tts.stop();
    if (id != _speakId) return; // 기다리는 사이 더 새 말이 옴
    final done = Completer<void>();
    _speaking = done.future;
    try {
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[voice] TTS 실패: $e');
    } finally {
      _lastSpeakEnd = DateTime.now();
      if (!done.isCompleted) done.complete();
      if (id == _speakId) _speaking = null;
    }
  }

  /// 짧은 경고 — 진동 3번 + 높은 음으로 '삐삐'. (알람음 파일을 틀 패키지가 없어서 TTS 로 냄)
  static Future<void> alarm() async {
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 120));
    }
    await _initTts();
    await _tts.setPitch(1.8);
    await speak('삐삐');
    await _tts.setPitch(1.0);
  }

  // ═══════════════════════════════════════════════════════════
  // STT
  // ═══════════════════════════════════════════════════════════

  /// 대답을 듣는다 → 최종 글자. 무응답 '' / 인식기를 쓸 수 없음 null (퀴즈를 건너뛰고 기록은 'unavailable')
  ///   말하는 중이면 끝나고 1초 뒤에 마이크를 켠다.
  static Future<String?> listen({
    String? type,
    String? display,
    int? listenSec,
    void Function(String partial)? onPartial,
    void Function(String guide)? onGuide,
  }) async {
    final id = ++_listenId;
    lastAnswerSec = null;
    if (!await _initStt()) return null;

    // TTS 가 끝나고 1초 뒤 (자기 목소리 · 첫 듣기 먹통 방지)
    if (_speaking != null) await _speaking;
    final since = _lastSpeakEnd == null ? micDelay : DateTime.now().difference(_lastSpeakEnd!);
    if (since < micDelay) await Future.delayed(micDelay - since);
    if (id != _listenId) return '';

    final isAdd = type == 'add';
    final continuous = !isAdd; // 따라 말하기 · 그 밖의 대답은 이어 듣기
    final expected = type == 'repeat' ? display : null;
    final sec = (listenSec != null && listenSec > 0) ? max(listenSec, defaultListenSec) : defaultListenSec;

    final watch = Stopwatch()..start();
    final texts = <int, String>{}; // 조각 번호 → 들은 글자 (늦게 온 최종 결과로 덮어씀)
    String joined() => (texts.keys.toList()..sort()).map((k) => texts[k]!).join(' ').trim();
    var session = 0;
    var deadline = sec * 1000;
    var enough = false;
    var busyRun = 0; // '바쁨'이 연달아 난 횟수 → 쉬는 시간을 늘림
    String? lastErr;

    while (watch.elapsedMilliseconds < deadline - 300 && id == _listenId) {
      final my = ++session;
      // 따라 말하기는 두 번째 띠링부터 처음부터 다시 말할 시간을 새로 줌 (한 번만)
      if (my == 2 && expected != null) deadline = watch.elapsedMilliseconds + sec * 1000;
      onGuide?.call(my == 1 ? guideFirst : guideAgain);
      var gotFinal = false;
      try {
        await _stt.listen(
          onResult: (SpeechRecognitionResult r) {
            if (id != _listenId) return;
            if (r.recognizedWords.isNotEmpty) {
              lastAnswerSec ??= watch.elapsedMilliseconds / 1000;
              texts[my] = r.recognizedWords;
            }
            if (r.finalResult && my == session) gotFinal = true;
            if (expected != null && _repeatScore(expected, joined()) >= doneScore) enough = true;
            onPartial?.call(joined());
          },
          listenOptions: SpeechListenOptions(
            localeId: 'ko_KR',
            listenFor: Duration(milliseconds: deadline - watch.elapsedMilliseconds),
            pauseFor: const Duration(seconds: 3),
            partialResults: true,
            cancelOnError: true,
            listenMode: ListenMode.dictation, // 문장 받아쓰기 (confirmation 은 더 빨리 끝남)
          ),
        );
      } catch (e) {
        debugPrint('[voice] 듣기 시작 실패: $e');
      }
      // 이 조각이 끝날 때까지 (인식기가 멈춤 · 시간 끝 · 문장을 다 들음 · stop)
      while (watch.elapsedMilliseconds < deadline && _stt.isListening && !enough && id == _listenId) {
        await Future.delayed(const Duration(milliseconds: 100));
      }
      if (_stt.isListening) await _stt.stop(); // 최종 결과 요청
      // 말이 들린 조각이면 최종 결과를 최대 1.5초 기다림
      final waitStart = watch.elapsedMilliseconds;
      while (texts.containsKey(my) && !gotFinal && watch.elapsedMilliseconds - waitStart < 1500) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      lastErr = _stt.lastError?.errorMsg;
      final silent = lastErr == null || lastErr == 'error_speech_timeout' || lastErr == 'error_no_match';
      // 덧셈은 조각마다 끄고 쉼, 따라 말하기는 '말이 들린 조각' 뒤에만 바로 이어 들음, '바쁨'이면 끄고 0.5초
      //   (11/02 주행 소음 시험: 아무 말도 못 들은 조각(no_match) 뒤에 끄지 않고 바로 켜면 '바쁨'이 연달아 남)
      if (!continuous || !silent || !texts.containsKey(my)) {
        await _stt.cancel();
        // '바쁨'이 연달아 나면 0.5 → 1 → 1.5초로 늘려 쉼 (11/02 주행 소음 시험: 0.5초로는 4번 연달아 나서 대답을 통째로 놓침)
        busyRun = silent ? 0 : busyRun + 1;
        await Future.delayed(Duration(milliseconds: silent ? 300 : 500 * min(busyRun, 3)));
      }
      if (enough || id != _listenId) break;
      if (!texts.containsKey(my) && texts.isNotEmpty && silent) break; // 말한 뒤 한 조각 내내 조용 = 끝
      if (isAdd && _hasFullAnswer(joined())) break; // 두 자리 수가 들림 ('9' 나 '70' 이면 이어 들음)
    }
    if (_stt.isListening) await _stt.cancel();
    await Future.delayed(const Duration(milliseconds: 300)); // 마지막 조각의 늦은 최종 결과
    final heard = joined();
    if (heard.isEmpty && lastErr != null && lastErr != 'error_speech_timeout' && lastErr != 'error_no_match') {
      debugPrint('[voice] 듣기 실패: $lastErr');
    }
    return heard;
  }

  static Future<void> _stopListening() async {
    _listenId++;
    if (_stt.isListening) await _stt.cancel();
  }

  /// 말하기 · 듣기 모두 멈춤 (화면을 닫을 때)
  static Future<void> stop() async {
    _speakId++;
    await _stopListening();
    if (_ttsReady) await _tts.stop();
  }

  // 덧셈 '답을 다 들었나' — 마지막 두 자리 이상 수가 0 으로 끝나지 않으면 다 들음
  //   서버 _make_add 는 일의 자리 1~8 끼리 받아올림 없이 더함 → 답의 일의 자리는 2~9, 0 이면 '칠십…' 에서 끊긴 것
  //   (11/02 주행 소음: 78 → '70', 84 → '80%' 에서 멈춰 오답)
  static bool _hasFullAnswer(String text) {
    final nums = RegExp(r'\d{2,}').allMatches(text).map((m) => m.group(0)!).toList();
    return nums.isNotEmpty && !nums.last.endsWith('0');
  }

  // 따라 말하기 '다 들었나' 판단용 — 서버 voice_quiz_service.repeat_score 와 같은 계산
  //   (들은 글자 중 문장과 가장 비슷한 한 토막, 공백 · 문장부호 무시)
  static String _norm(String s) => s.replaceAll(RegExp(r'[^0-9A-Za-z가-힣]'), '');

  static double _repeatScore(String expected, String heard) {
    final exp = _norm(expected), ans = _norm(heard);
    if (exp.isEmpty || ans.isEmpty) return 0;
    if (ans.contains(exp)) return 1;
    var prev = List<int>.filled(ans.length + 1, 0);
    for (var i = 1; i <= exp.length; i++) {
      final cur = <int>[i];
      for (var j = 1; j <= ans.length; j++) {
        cur.add([prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (exp[i - 1] == ans[j - 1] ? 0 : 1)].reduce(min));
      }
      prev = cur;
    }
    return max(0, 1 - prev.reduce(min) / exp.length);
  }
}
