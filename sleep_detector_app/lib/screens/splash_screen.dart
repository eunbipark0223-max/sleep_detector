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
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';
import '../widgets/system_status.dart';
import '../design_tokens.dart';

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
    // (11/18 피드백) 자동 로그인을 끄고 로그인했으면 → 저장된 토큰을 지우고 로그인 화면으로
    if (loggedIn && !await AuthService.getAutoLogin()) {
      await AuthService.clearToken();
      loggedIn = false;
    }
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

  // (11/24 사용자 요청) 연한 파랑 그라데이션 바탕 · 가운데 남색 둥근 네모 아이콘(흰 방패) + 앱 이름 · 맨 아래 작은 글
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppSol.pageGradient),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          child: SizedBox(
            width: double.infinity, // 가운데 정렬 (화면 폭 전체)
            child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
            const Spacer(flex: 5),
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                color: AppColors.navy,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [BoxShadow(color: AppColors.navy.withValues(alpha: 0.25), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Icon(Icons.verified_user_rounded, size: 46, color: Colors.white),
            ),
            const SizedBox(height: 22),
            const Text('졸음가드', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -0.8, color: AppColors.navy)),
            const SizedBox(height: 6),
            const Text('운전자 졸음 안전관리 솔루션', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            const Spacer(flex: 6),
            const Text('안전한 운행을 함께 지켜요', style: TextStyle(fontSize: 13, color: AppColors.textMuted)),
            const SizedBox(height: 28),
          ]),
          ),
        ),
      ),
    );
  }
}
