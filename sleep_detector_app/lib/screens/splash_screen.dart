// ═══════════════════════════════════════════════════════════════
// screens/splash_screen.dart — 스플래시 · 자동 로그인
// ═══════════════════════════════════════════════════════════════
// 담당: C (10/14 D → C)   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/splash_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 첫 실행 때 카메라 · 마이크 · 위치 사용 동의 — 쉬운 말로만 (동의해야 다음으로, 동의 안 하면 앱 종료)
//   - 저장된 토큰 확인 → 메인 / 로그인으로 이동
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

/// 시작 화면 그림(assets/owl/splash.png)의 바탕 남색
const Color _splashNavy = Color(0xFF010972);

class _SplashScreenState extends State<SplashScreen> {
  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _consentKey = 'privacy_consent'; // 한 번 동의하면 다시 묻지 않는다 (로그아웃해도 그대로)

  @override
  void initState() {
    super.initState();
    _goNext();
  }

  // 자동 로그인 - 토큰 확인 후 분기
  Future<void> _goNext() async {
    // 로그인 만료(401) 때 어느 화면에 있든 로그인 화면으로 보내는 함수를 ApiService 에 넣어 둔다
    // (스플래시는 앱의 첫 화면이라 여기서 받은 Navigator 는 앱이 끝날 때까지 그대로 쓸 수 있다)
    final navigator = Navigator.of(context);
    ApiService.onUnauthorized = () => navigator.pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );

    await Future.delayed(const Duration(seconds: 2));
    if (!await _checkConsent()) return;
    var loggedIn = await AuthService.isLoggedIn();
    // 토큰이 있어도 만료됐을 수 있다 → 서버에 확인 (만료면 me() 가 토큰을 지우고 null)
    // 서버 연결 오류는 로그아웃시키지 않고 그대로 들어간다 (운행 중 401 이 오면 그때 로그인 화면으로)
    if (loggedIn) {
      try {
        loggedIn = await AuthService.me() != null;
      } catch (_) {}
    }
    if (!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => loggedIn ? const MainScreen() : const LoginScreen(),
      ),
    );
  }

  // 첫 실행 동의 — 이미 동의했으면 바로 true, 동의 안 함을 누르면 앱을 끄고 false
  Future<bool> _checkConsent() async {
    if (await _storage.read(key: _consentKey) == 'yes') return true;
    if (!mounted) return false;
    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('사용 동의'),
          content: const SingleChildScrollView(
            // 기사님은 일반 사용자 — 서버 · 관리자 · 사진 처리 같은 기술 설명은 빼고 쓰는 기능만 쉬운 말로 (11/09 팀장)
            child: Text(
              '졸음운전을 막기 위해 아래 기능을 사용해요.\n\n'
              '• 카메라: 눈을 감는지 확인해요\n'
              '• 마이크: 음성 퀴즈 대답을 들어요\n'
              '• 위치: 졸음 경고가 난 곳을 기록해요',
              style: TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('동의 안 함')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('동의하고 시작')),
          ],
        ),
      ),
    );
    if (agreed != true) {
      SystemNavigator.pop();
      return false;
    }
    await _storage.write(key: _consentKey, value: 'yes');
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _splashNavy, // 그림 바탕과 같은 남색 (그림 위아래 빈자리가 이어져 보이게)
      body: Stack(
        children: [
          // 트럭 부엉이 시작 화면 그림 ("졸음 가드" 글씨 포함, 노션 '메인 로고 아이디어' 스플래시, 11/10) — 화면 폭에 꽉 차게
          Positioned.fill(
            child: Image.asset('assets/owl/splash.png', fit: BoxFit.contain, semanticLabel: '졸음 가드'),
          ),
          // (11/11) 트럭 위에 단계 부엉이 3개 — 졸기 전(초록) · 졸 때(주황) · 졸고 나서(빨강). 노랑은 빼고 3개만
          LayoutBuilder(builder: (context, box) {
            final imgH = box.maxWidth * 1671 / 941; // 그림 비율 그대로 폭에 맞췄을 때 높이
            final truckTop = (box.maxHeight - imgH) / 2 + imgH * 0.27; // 그림 속 트럭 지붕 위치
            return Stack(children: [
              Positioned(
                left: 0,
                right: 0,
                top: (truckTop - 130).clamp(8.0, double.infinity),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _StageOwl(owl: 'assets/owl/owl_face0.png', label: '졸기 전'),
                    _StageOwl(owl: 'assets/owl/owl_face2.png', label: '졸 때'),
                    _StageOwl(owl: 'assets/owl/owl_face3.png', label: '졸고 나서'),
                  ],
                ),
              ),
            ]);
          }),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "졸기 전 · 졸 때 · 졸고 나서" 는 위 부엉이 3개 이름으로 옮김 (11/11)

                  const CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2.5,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '운수 안전관리팀',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.9),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Sleep Guard System',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  )
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 시작 화면 트럭 위 작은 부엉이 + 이름 (졸기 전 · 졸 때 · 졸고 나서)
class _StageOwl extends StatelessWidget {
  final String owl;
  final String label;
  const _StageOwl({required this.owl, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Image.asset(owl, width: 72, height: 72),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
      ],
    );
  }
}
