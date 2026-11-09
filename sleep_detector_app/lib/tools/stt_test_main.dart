// ═══════════════════════════════════════════════════════════════
// tools/stt_test_main.dart — 운전 중 음성 퀴즈 STT 시험 도구 (앱과 따로 실행)
// ═══════════════════════════════════════════════════════════════
// 담당: 팀장   |   우선: P1 (KPI ⑤ 음성 퀴즈 인식률)
// 수업 원본: (없음, 🔴 신규) — 앱 화면이 아니라 측정용. 로그인 · 서버 없이 폰 안에서만 돈다
//
// [실행]  (sleep_detector_app 폴더, 시연 폰 USB 연결)
//   flutter run -t lib/tools/stt_test_main.dart
//
// [하는 일]
//   - 사람(a · b · c · d · t) · 환경(quiet 조용한 곳 / noise 주행 소음)을 고르고 [시작]
//   - 서버 voice_quiz_service 와 같은 문제 20개: 따라 말하기 10 + 덧셈 10 (섞어서)
//   - 말하기 · 듣기는 앱과 똑같이 lib/services/voice_service.dart 로 (11/02 — 시험 = 실제 서비스 검증)
//       VoiceService.speak(문제) → VoiceService.listen(type, display) — 듣는 방식은 voice_service 맨 위 설명
//       (10/29 이 도구로 11차례 시험해 정한 방식을 voice_service 로 옮김: 조용한 곳 95%)
//   - 문제마다 인식 글자 · 걸린 시간을 화면 표 + 콘솔(CSV 줄) + 파일로
//       파일: /sdcard/Android/data/com.example.sleep_detector_app/files/stt_test.csv (이어 붙임)
//       PC 로 가져오기: adb pull /sdcard/Android/data/com.example.sleep_detector_app/files/stt_test.csv
//       저장이 안 되면: adb logcat -d -s flutter -v raw 에서 [stt_csv] 줄
//   - 채점은 PC 에서 서버와 같은 코드로: venv\Scripts\python tools/stt_score.py stt_test.csv
//
// [주의]
//   - 따라 말하기 문장은 sleep_detector_api/knowledge/voice_quiz/repeat_sentences.txt 와 같게 (바꾸면 둘 다)
//   - 녹음 · 음성 파일은 남기지 않는다 (인식 글자만). 결과 CSV 는 GitHub 에 올리지 않는다
// ═══════════════════════════════════════════════════════════════
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';

import '../services/voice_service.dart';

const _csvPath = '/sdcard/Android/data/com.example.sleep_detector_app/files/stt_test.csv';
const _csvHeader = 'person,cond,n,type,display,expected,heard,ms_first,ms_total,status';
const _people = ['a', 'b', 'c', 'd', 't'];
const _conds = {'quiet': '조용한 곳', 'noise': '주행 소음'};

// 서버 knowledge/voice_quiz/repeat_sentences.txt 와 같은 문장
const _sentences = [
  '졸리면 참지 말고 쉬어 가겠습니다', '안전 운전을 최우선으로 하겠습니다', '졸음운전은 절대 하지 않겠습니다', '창문을 열고 환기하겠습니다', '졸음쉼터에서 잠깐 쉬겠습니다',
  '피곤하면 운전을 멈추겠습니다', '차간 거리를 유지하겠습니다', '앞지르기를 서두르지 않겠습니다', '기다리는 가족을 생각하겠습니다', '오늘도 무사히 도착하겠습니다',
  '휴게소에 들러 몸을 풀겠습니다', '눈이 감기면 바로 쉬겠습니다', '무리한 운행은 거절하겠습니다', '안전띠를 꼭 매고 달리겠습니다', '신호를 잘 지키겠습니다',
  '선글라스로 눈부심을 막겠습니다', '충분히 자고 운전하겠습니다', '가까운 쉼터에서 쉬겠습니다', '보행자를 먼저 생각하겠습니다', '안전하게 집으로 돌아가겠습니다',
  '쉼터 위치를 미리 알아 두겠습니다', '졸음이 오면 쉼터로 가겠습니다', '졸음을 버티지 않고 쉬겠습니다', '납품 시간보다 안전을 지키겠습니다', '짐보다 내 몸을 먼저 챙기겠습니다',
  '과속하지 않고 천천히 가겠습니다', '빨간불에는 꼭 멈추겠습니다', '노란불에는 욕심내지 않겠습니다', '초록불에도 좌우를 살피겠습니다', '비 오는 날엔 더 천천히 가겠습니다',
  '장거리 운행 전 차를 점검하겠습니다', '안개가 끼면 등을 켜고 가겠습니다', '터널에서는 전조등을 켜겠습니다', '깜빡이를 켜고 차로를 바꾸겠습니다', '양보하며 운전하겠습니다',
  '화가 나도 경적을 참겠습니다', '급한 차는 먼저 보내 드리겠습니다', '조금 늦어도 안전하게 가겠습니다', '급할수록 천천히 가겠습니다', '운전 중 휴대전화를 보지 않겠습니다',
  '핸들에서 손을 떼지 않겠습니다', '바른 자세로 앉아 운전하겠습니다', '목과 어깨를 풀고 출발하겠습니다', '출발 전에 충분히 쉬겠습니다', '밤길에는 더 조심하겠습니다',
  '법규를 지키는 기사가 되겠습니다', '가족에게 웃으며 도착하겠습니다', '잠은 집에 가서 자겠습니다', '피곤한 날은 더 자주 쉬겠습니다', '눈 크게 뜨고 정신 차리겠습니다',
  '신호 대기 중에도 집중하겠습니다', '졸음이 오면 바로 차를 세우겠습니다', '쉼터 표지판이 보이면 들르겠습니다', '커피보다 휴식을 택하겠습니다', '운전 전에 술을 마시지 않겠습니다',
  '졸음이 오는 약은 피하겠습니다', '몸이 아프면 운전을 쉬겠습니다', '무거운 짐은 단단히 묶겠습니다', '출발 전에 짐을 꼼꼼히 살피겠습니다', '사각지대를 꼭 확인하겠습니다',
  '후진할 때 뒤를 잘 살피겠습니다', '횡단보도 앞에서 멈추겠습니다', '어린이 보호구역을 지키겠습니다', '주차할 때 주변을 둘러보겠습니다', '골목에서는 아이들을 살피겠습니다',
  '내리막에선 저단 기어를 쓰겠습니다', '커브길에서는 속도를 줄이겠습니다', '출발 전에 거울 위치를 맞추겠습니다', '얼어붙은 길을 조심하겠습니다', '바람이 세면 더 조심하겠습니다',
  '밤에는 전조등을 켜고 달리겠습니다', '상향등을 함부로 켜지 않겠습니다', '차로를 지키며 달리겠습니다', '끼어들기를 하지 않겠습니다', '갓길로 달리지 않겠습니다',
  '속도계를 자주 확인하겠습니다', '서두르지 않고 여유 있게 가겠습니다', '내비 조작은 차를 세우고 하겠습니다', '운전 중에 문자를 하지 않겠습니다',
  '길을 놓쳐도 급하게 돌지 않겠습니다', '졸음 경고를 무시하지 않겠습니다', '하품이 연달아 나면 휴식하겠습니다', '머리가 멍하면 바람을 쐬겠습니다', '운행 일정을 넉넉하게 잡겠습니다',
  '졸음을 커피로 버티지 않겠습니다', '쉬는 시간을 아끼지 않겠습니다', '쉼터에서 스트레칭을 하겠습니다', '쉼터에서 눈을 붙이고 가겠습니다', '물을 마시며 정신을 차리겠습니다',
  '차 안 공기를 자주 바꾸겠습니다', '히터를 너무 세게 틀지 않겠습니다', '식사 후 잠깐 걷고 출발하겠습니다', '밤샘 운전을 하지 않겠습니다', '전날 밤에는 푹 자겠습니다',
  '동료에게 졸음을 숨기지 않겠습니다', '관리자에게 피로를 알리겠습니다', '다른 운전자를 배려하겠습니다', '오토바이와 자전거를 살피겠습니다', '비상등으로 고마움을 전하겠습니다',
  '도착할 때까지 긴장하겠습니다',
];

void main() => runApp(const MaterialApp(home: SttTestScreen(), debugShowCheckedModeBanner: false));

class _Quiz {
  final String type; // repeat · add
  final String display; // 화면 글자
  final String expected; // 정답 (문장 / 숫자)
  final String speak; // TTS 로 읽을 문장 (서버 make_quiz 와 같은 모양)
  _Quiz(this.type, this.display, this.expected, this.speak);
}

class _Row {
  final String person, cond, type, display, expected, heard, status;
  final int n, msFirst, msTotal;
  _Row(this.person, this.cond, this.n, this.type, this.display, this.expected, this.heard, this.msFirst,
      this.msTotal, this.status);

  static String _q(String s) => '"${s.replaceAll('"', "'")}"';
  String toCsv() =>
      [person, cond, n, type, _q(display), _q(expected), _q(heard), msFirst, msTotal, status].join(',');
}

// ── 서버 voice_quiz_service 와 같은 출제 ──
const _sinoDigits = ['', '일', '이', '삼', '사', '오', '육', '칠', '팔', '구'];

String _koreanNumber(int n) {
  // 0~99 → '이십삼' (TTS 가 '23' 을 '스물셋'으로 읽지 않게, 서버 to_korean_number 와 같음)
  final t = n ~/ 10, u = n % 10;
  return '${t == 0 ? '' : '${t == 1 ? '' : _sinoDigits[t]}십'}${_sinoDigits[u]}';
}

List<_Quiz> _makeQuizzes(Random rnd) {
  final sentences = [..._sentences]..shuffle(rnd);
  final out = <_Quiz>[
    for (final s in sentences.take(10)) _Quiz('repeat', s, s, '따라 말하세요. $s.'),
  ];
  for (var i = 0; i < 10; i++) {
    // 받아올림 없는 두 자리 + 두 자리, 일의 자리 1~8 (서버 _make_add 와 같음)
    final t1 = 1 + rnd.nextInt(8), t2 = 1 + rnd.nextInt(9 - t1);
    final u1 = 1 + rnd.nextInt(8), u2 = 1 + rnd.nextInt(9 - u1);
    var a = t1 * 10 + u1, b = t2 * 10 + u2;
    if (rnd.nextBool()) (a, b) = (b, a);
    out.add(_Quiz('add', '$a + $b = ?', '${a + b}', '${_koreanNumber(a)} 더하기 ${_koreanNumber(b)}. 답을 말해 주세요.'));
  }
  return out..shuffle(rnd);
}

class SttTestScreen extends StatefulWidget {
  const SttTestScreen({super.key});

  @override
  State<SttTestScreen> createState() => _SttTestScreenState();
}

class _SttTestScreenState extends State<SttTestScreen> {
  final _rows = <_Row>[];

  String _person = 't';
  String _cond = 'quiet';
  bool _ready = false;
  bool _running = false;
  bool _stopAsked = false;
  String _status = '준비 중…';
  String _now = ''; // 지금 문제
  String _partial = ''; // 듣는 중 글자
  String _banner = ''; // 크게 띄우는 안내 (첫 띠링 '말씀해 주세요' · 두 번째부터 '다시 한번 말씀해 주세요')

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 인식기는 VoiceService 가 처음 들을 때 준비함 (쓸 수 없으면 listen 이 null → 시험을 멈추고 알림)
    setState(() {
      _ready = true;
      _status = '준비 완료 — 사람 · 환경을 고르고 [시작]';
    });
  }

  Future<void> _run() async {
    setState(() {
      _running = true;
      _stopAsked = false;
    });
    final quizzes = _makeQuizzes(Random());
    for (var i = 0; i < quizzes.length && !_stopAsked; i++) {
      final q = quizzes[i];
      setState(() {
        _now = '${i + 1}/${quizzes.length}  ${q.display}';
        _partial = '';
        _banner = '';
        _status = '🔊 문제 읽는 중…';
      });
      await VoiceService.speak(q.speak);
      if (_stopAsked) break;
      setState(() => _status = '🎤 듣는 중… (최대 ${VoiceService.defaultListenSec}초)');
      final watch = Stopwatch()..start();
      final heard = await VoiceService.listen(
        type: q.type,
        display: q.display,
        onPartial: (t) => mounted ? setState(() => _partial = t) : null,
        onGuide: (g) => mounted ? setState(() => _banner = g) : null,
      );
      // 걸린 시간은 마이크를 켠 뒤부터 (VoiceService 가 TTS 뒤 1초 기다린 것은 뺌 — 예전 기록과 같은 기준)
      final total = max(0, watch.elapsedMilliseconds - VoiceService.micDelay.inMilliseconds);
      final first = VoiceService.lastAnswerSec == null ? -1 : (VoiceService.lastAnswerSec! * 1000).round();
      final status = heard == null ? 'unavailable' : (heard.isEmpty ? 'no_speech' : 'ok');
      if (heard == null) {
        setState(() => _status = '음성 인식을 쓸 수 없어요 (마이크 권한 · Google 음성 인식 · 한국어 확인)');
        break;
      }
      final row = _Row(_person, _cond, i + 1, q.type, q.display, q.expected, heard, first, total, status);
      debugPrint('[stt_csv] ${row.toCsv()}');
      setState(() {
        _rows.insert(0, row);
        _banner = '';
      });
      await Future.delayed(const Duration(milliseconds: 1200));
    }
    await _save();
    setState(() => _running = false);
  }

  Future<void> _save() async {
    final mine = _rows.reversed.toList();
    try {
      final file = File(_csvPath);
      await file.parent.create(recursive: true);
      final fresh = !await file.exists();
      await file.writeAsString('${fresh ? '$_csvHeader\n' : ''}${mine.map((r) => r.toCsv()).join('\n')}\n',
          mode: FileMode.append);
      _status = '저장 완료 ${mine.length}개 → $_csvPath';
    } catch (e) {
      // Android 11+ 는 이 폴더를 앱이 직접 못 만들 수 있음 → 로그에서 꺼냄 (eye_measure_main 과 같음)
      _status = '파일 저장 실패 — PC 에서 adb logcat -d -s flutter -v raw | findstr stt_csv 로 꺼내기 ($e)';
    }
    _rows.clear();
  }

  @override
  void dispose() {
    VoiceService.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('STT 시험 (음성 퀴즈)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              const Text('사람 '),
              DropdownButton<String>(
                value: _person,
                items: [for (final p in _people) DropdownMenuItem(value: p, child: Text(p))],
                onChanged: _running ? null : (v) => setState(() => _person = v!),
              ),
              const SizedBox(width: 24),
              const Text('환경 '),
              DropdownButton<String>(
                value: _cond,
                items: [for (final e in _conds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: _running ? null : (v) => setState(() => _cond = v!),
              ),
            ]),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: !_ready ? null : (_running ? () => setState(() => _stopAsked = true) : _run),
              child: Text(_running ? '그만 (지금 문제까지 저장)' : '시작 (20문제)'),
            ),
            const SizedBox(height: 12),
            Text(_status),
            const SizedBox(height: 8),
            Text(_now, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
            if (_banner.isNotEmpty)
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
                decoration: BoxDecoration(
                  color: _banner.contains('다시') ? Colors.orange.shade100 : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(_banner,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, height: 1.3)),
              ),
            Text(_partial, style: const TextStyle(fontSize: 18, color: Colors.indigo)),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final r in _rows)
                    ListTile(
                      dense: true,
                      title: Text('${r.n}. ${r.display}'),
                      subtitle: Text('들은 글자: ${r.heard.isEmpty ? '(없음)' : r.heard}  · ${r.msTotal}ms · ${r.status}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
