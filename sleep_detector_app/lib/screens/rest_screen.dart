// ═══════════════════════════════════════════════════════════════
// screens/rest_screen.dart — 휴식 화면 (15분 → 운행 재개 → 1단계)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
//
// [이 파일이 하는 일]
//   - startRest() → 15분 카운트다운 (눈 판정 멈춤, ping 은 계속) 🔊 '15분 쉬고 출발하세요'
//   - 15분이 지나야 [운행 재개] 켜짐 → resumeDrive() → 1단계로 drive_screen 🔊 '주의 단계로 다시 출발합니다'
//   - (11/18 팀장) [관련 규정 보기] → 휴식 관련 고정 규정 카드 창 (rest_regulations.dart · regulation_screen 의 showRegulationSheet)
//       경고 화면에서 규정을 뺀 대신 쉬는 동안 여기서 본다
//
// [주의]
//   - 퀴즈 없음
//   - 15분은 서버가 다시 검사 (앱 시계를 믿지 않음)
//
// [쓰는 법 — warning_screen 의 [정차했어요] 가 부른다]
//   - final result = await Navigator.push<Map<String, dynamic>>(context, MaterialPageRoute(builder: (_) => const RestScreen()));
//   - 화면을 열면 바로 startRest() 를 부른다. [운행 재개] 가 성공하면 서버 응답(stage · status · message)을 담아 닫힌다
//     → 받은 쪽(drive_screen)은 result['stage'] 로 화면 색을 바꾸고 카메라 판정을 다시 시작한다
//   - 휴식 중에는 뒤로 가기를 막는다 (나가는 길은 [운행 재개] 뿐). 시작 실패 때만 [돌아가기] 로 닫을 수 있고 null 을 돌려준다
//   - 눈 판정 멈춤 · ping 계속은 이 화면을 연 drive_screen(C) 쪽 몫이다
//
// [서버 약속 — sleep_detector_api/routers/detect.py]
//   - POST /drive/rest   → {success, message: '15분 쉬고 출발하세요', rest_sec: 900, started}   (DEMO_MODE 면 60초)
//   - POST /drive/resume → {success, stage, status, message}   정차 기록이 없으면 400 · 시간이 덜 지났으면 409('N초 남음')
//   - 카운트다운 시간(rest_sec)은 서버 값을 쓴다 (앱에 15분을 박아 두지 않는다)
//
// [연결됨]
//   - C 의 ApiService.startRest() · resumeDrive()  → 서버 JSON(Map)을 그대로 돌려주고, 실패하면 서버 detail 을 담은
//     Exception 을 던진다 (409 의 'N초 남음' 문구가 그대로 화면에 나온다)
//   - 팀장의 VoiceService.speak()  (11/02 — 안내 문구가 소리로 나온다)
//
// [연결 대기]
//   - 이 화면을 여는 warning_screen 의 [정차했어요] (C, 지금 warning_screen.dart 는 주석뿐)
//   - 아래 생성자의 startRest · resumeDrive · speak · now 는 테스트 · 미리보기에서 바꿔 끼우는 입구다 (비우면 기본)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoAlertDialog, CupertinoDialogAction;
import 'package:flutter/material.dart';

import '../rest_regulations.dart';
import '../services/api_service.dart';
import '../services/voice_service.dart';
import '../theme.dart';
import 'regulation_screen.dart';
import '../widgets/buddy.dart';
import '../widgets/auth_ui.dart';
import '../design_tokens.dart';
import '../widgets/owl_says.dart' show balancedLines;

class RestScreen extends StatefulWidget {
  /// 휴식 시작 (POST /drive/rest). 서버 JSON 을 돌려준다.
  final Future<Map<String, dynamic>> Function()? startRest;

  /// 운행 재개 (POST /drive/resume). 서버 JSON 을 돌려준다. 실패하면 보여 줄 글을 담은 예외를 던진다.
  final Future<Map<String, dynamic>> Function()? resumeDrive;

  /// 안내 문구 읽기 (TTS)
  final Future<void> Function(String text)? speak;

  /// 지금 시각 (테스트에서 시간을 흘려 보내려고 바꿔 끼운다)
  final DateTime Function()? now;

  const RestScreen({super.key, this.startRest, this.resumeDrive, this.speak, this.now});

  @override
  State<RestScreen> createState() => _RestScreenState();
}

enum _Phase { starting, startFailed, resting, resuming }

class _RestScreenState extends State<RestScreen> {
  _Phase _phase = _Phase.starting;
  String _message = ''; // 서버가 준 안내 문구 (예: 15분 쉬고 출발하세요)
  String? _error; // 화면에 보여 줄 오류 글
  int _totalSec = 0;
  DateTime? _startedAt;
  Duration _left = Duration.zero;
  Timer? _timer;

  static Future<Map<String, dynamic>> _defaultStartRest() => ApiService.startRest();
  static Future<Map<String, dynamic>> _defaultResumeDrive() => ApiService.resumeDrive();

  static Future<void> _defaultSpeak(String text) => VoiceService.speak(text);

  DateTime _now() => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _begin();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _begin() async {
    setState(() {
      _phase = _Phase.starting;
      _error = null;
    });
    try {
      final data = await (widget.startRest ?? _defaultStartRest)();
      if (!mounted) return;
      final sec = _toInt(data['rest_sec']);
      if (sec <= 0) throw Exception('휴식 시간을 알 수 없어요');
      _totalSec = sec;
      _startedAt = _now();
      _message = '${data['message'] ?? ''}';
      _left = Duration(seconds: sec);
      setState(() => _phase = _Phase.resting);
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      _say(_message);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.startFailed;
        _error = _messageOf(e);
      });
    }
  }

  // 남은 시간은 '시작 시각 + 서버가 준 시간' 에서 계산한다 (타이머가 밀려도, 잠깐 멈춰도 어긋나지 않게)
  void _tick() {
    final started = _startedAt;
    if (started == null || !mounted) return;
    final elapsed = _now().difference(started).inSeconds;
    final left = (_totalSec - elapsed).clamp(0, _totalSec);
    setState(() => _left = Duration(seconds: left));
    if (left == 0) _timer?.cancel();
  }

  Future<void> _resume() async {
    setState(() {
      _phase = _Phase.resuming;
      _error = null;
    });
    try {
      final data = await (widget.resumeDrive ?? _defaultResumeDrive)();
      if (!mounted) return;
      _timer?.cancel();
      _say('${data['message'] ?? ''}');
      Navigator.of(context).pop(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.resting;
        _error = _messageOf(e); // 서버가 아직 이르다고 하면(409) 그 글을 그대로 보여 주고 다시 누르게 한다
      });
    }
  }

  // (11/23) [운행 종료] — 한 번 묻고 {'end': true} 를 돌려줌 (운행 화면이 운행 종료 · 리포트를 처리)
  Future<void> _end() async {
    final yes = await showDialog<bool>(
      context: context,
      // (11/24 사용자 요청) 운행 화면 · '정차하셨나요?' 창과 같은 아이폰 알림창
      builder: (ctx) => CupertinoAlertDialog(
        title: const Padding(
          padding: EdgeInsets.only(bottom: 4),
          child: Text('운행을 끝낼까요?', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
        content: const Text('운행을 끝내면 졸음 감지가 멈춰요', style: TextStyle(fontSize: 15, height: 1.45, color: AppColors.textSecondary)),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            textStyle: const TextStyle(fontSize: 18, color: AppColors.textSecondary),
            child: const Text('계속 쉬기'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.navy),
            child: const Text('운행 종료'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    _timer?.cancel();
    Navigator.of(context).pop(<String, dynamic>{'end': true});
  }

  // 소리 내기는 실패해도 화면 흐름을 막지 않는다
  Future<void> _say(String text) async {
    if (text.isEmpty) return;
    try {
      await (widget.speak ?? _defaultSpeak)(text);
    } catch (_) {}
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  static String _messageOf(Object e) => e.toString().replaceFirst('Exception: ', '');

  String get _clock {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(_left.inMinutes)}:${two(_left.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false, // 휴식 중에는 뒤로 가기로 나갈 수 없다 (나가는 길은 [운행 재개])
      // (11/24 사용자 요청) 앱 바탕 그라데이션 · 다른 탭과 같은 자리의 큰 제목
      child: DecoratedBox(
        decoration: const BoxDecoration(gradient: AppSol.pageGradient),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            toolbarHeight: 68,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            titleSpacing: 16,
            centerTitle: false,
            title: Text('휴식', style: AppType.title1.copyWith(color: AppColors.textPrimary)),
          ),
          body: SafeArea(child: _body()),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.starting:
        return const _Centered(children: [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('휴식을 시작하는 중이에요', style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
        ]);
      case _Phase.startFailed:
        return _Centered(children: [
          const Icon(Icons.error_outline, size: 40, color: AppColors.textMuted),
          const SizedBox(height: 12),
          Text(_error ?? '', textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          FilledButton(onPressed: _begin, child: const Text('다시 시도')),
          const SizedBox(height: 8),
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('돌아가기')),
        ]);
      case _Phase.resting:
      case _Phase.resuming:
        final done = _left == Duration.zero;
        final busy = _phase == _Phase.resuming;
        final progress = _totalSec == 0 ? 0.0 : 1 - _left.inSeconds / _totalSec;
        // (11/24 사용자 요청) 흰 카드 — 상태 알약 · '남은 휴식 시간' · 큰 숫자 · 둥근 막대 / 아래 상세 줄 카드 / 맨 아래 버튼
        String hm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        final started = _startedAt;
        final ready = started?.add(Duration(seconds: _totalSec));
        final accent = done ? AppStatus.normal : AppColors.navy;
        BoxDecoration card() => BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: AppColors.cardBorder),
              boxShadow: AppShadow.card,
            );
        Widget row(String label, String value, {VoidCallback? onTap}) => InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 15, 16, 15),
                child: Row(children: [
                  Text(label, style: const TextStyle(fontSize: 15.5, color: AppColors.textSecondary)),
                  const Spacer(),
                  Text(value, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary, fontFeatures: [FontFeature.tabularFigures()])),
                  if (onTap != null) ...[const SizedBox(width: 4), const Icon(Icons.chevron_right_rounded, size: 20, color: AppleGray.chevron)],
                ]),
              ),
            );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // ① 남은 시간 카드 (계좌 잔액 카드처럼)
            Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 22),
              decoration: card(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(9, 3, 11, 3),
                    decoration: BoxDecoration(color: accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.pill)),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
                      const SizedBox(width: 5),
                      Text(done ? '휴식 완료' : '휴식 중', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: accent)),
                    ]),
                  ),
                  const Spacer(),
                  Buddy(stage: done ? 0 : 2, size: 40, breathe: false),
                ]),
                const SizedBox(height: 10),
                Text(done ? '충분히 쉬었어요' : '남은 휴식 시간', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                const SizedBox(height: 2),
                Text(_clock,
                    style: const TextStyle(fontSize: 48, height: 1.1, fontWeight: FontWeight.w800, letterSpacing: -1.2,
                        color: AppColors.textPrimary, fontFeatures: [FontFeature.tabularFigures()])),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: LinearProgressIndicator(value: progress, minHeight: 8, color: accent, backgroundColor: AppColors.field),
                ),
                if (_message.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final line in balancedLines(_message, maxChars: 22)) // (11/24) 3단계 카드처럼 줄마다 한 줄
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(line, maxLines: 1, softWrap: false, style: const TextStyle(fontSize: 14.5, color: AppColors.textSecondary)),
                    ),
                ],
              ]),
            ),
            const SizedBox(height: 12),
            // ② 상세 줄 카드 (계좌 상세처럼)
            Container(
              decoration: card(),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                row('휴식 시작', started == null ? '—' : hm(started.toLocal())),
                const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20, color: AppColors.line),
                row('다시 출발 가능', ready == null ? '—' : hm(ready.toLocal())),
                const Divider(height: 1, thickness: 1, indent: 20, endIndent: 20, color: AppColors.line),
                row('관련 규정', '보기', onTap: () => showRegulationSheet(context, RestRegulations.list)),
              ]),
            ),
            const Spacer(),
            if (_error != null) ...[
              Text(_error!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.urgent)),
              const SizedBox(height: 12),
            ],
            if (!done) ...[
              Text('휴식이 끝나면 [운행 재개]를 누를 수 있어요',
                  textAlign: TextAlign.center, style: AppType.footnote.copyWith(color: AppColors.textMuted)),
              const SizedBox(height: 10),
            ],
            AuthButton(
              text: busy ? '재개하는 중' : '운행 재개',
              onPressed: (done && !busy) ? _resume : null,
              height: AppSize.button,
              color: AppStatus.normal, // (11/23) [운행 종료] 와 구분되게 초록
            ),
            const SizedBox(height: 10),
            AuthButton(text: '운행 종료', onPressed: busy ? null : _end, height: AppSize.button), // (11/23 사용자 요청) 늘 남색 · 흰 글
          ]),
        );
    }
  }
}

class _Centered extends StatelessWidget {
  final List<Widget> children;
  const _Centered({required this.children});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final c in children) Center(child: c is FilledButton || c is ClipRRect ? SizedBox(width: double.infinity, child: c) : c),
        ]),
      ),
    );
  }
}
