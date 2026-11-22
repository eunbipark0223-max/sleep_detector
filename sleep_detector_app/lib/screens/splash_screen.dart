// ═══════════════════════════════════════════════════════════════
// screens/splash_screen.dart — 스플래시 · 자동 로그인
// ═══════════════════════════════════════════════════════════════
// 담당: C (10/14 D → C)   |   우선: P0
//
// [이 파일이 하는 일]
//   - (11/16 팀장) 첫 실행 사용 동의 창은 뺌 — [운행 시작] 때 권한 안내창 → 휴대폰 권한 창으로 한 번에 받음 (home_screen)
//   - 저장된 토큰 확인 → 메인 / 로그인으로 이동
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════


import 'package:flutter/material.dart';
import '../theme.dart';
import '../widgets/web_ui.dart';
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

class _SplashScreenState extends State<SplashScreen> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card, // (11/17) 로그인 · 회원가입과 같은 흰 바탕
      body: Stack(
        children: [
          // 트럭 부엉이 시작 화면 그림 ("졸음 가드" 글씨 포함, 노션 '메인 로고 아이디어' 스플래시, 11/10) — 화면 폭에 꽉 차게
          Positioned.fill(
            child: const Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                // (11/17) 그림은 아직 안 넣음 — 자리만 표시
                ImageSlot(label: '메인 캐릭터 이미지', width: 200, height: 200, radius: 28),
                SizedBox(height: 20),
                Text('졸음가드', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ]),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // "졸기 전 · 졸 때 · 졸고 나서" 는 위 부엉이 3개 이름으로 옮김 (11/11)

                  // (11/17 사용자 요청) '운수 안전관리팀 · Sleep Guard System' 글씨 뺌
                  const CircularProgressIndicator(
                    color: AppColors.navy,
                    strokeWidth: 2.5,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
