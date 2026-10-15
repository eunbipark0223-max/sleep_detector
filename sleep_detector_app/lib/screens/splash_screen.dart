// ═══════════════════════════════════════════════════════════════
// screens/splash_screen.dart — 스플래시 · 자동 로그인
// ═══════════════════════════════════════════════════════════════
// 담당: C (10/14 D → C)   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/splash_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 저장된 토큰 확인 → 메인 / 로그인으로 이동
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════


import 'package:flutter/material.dart';
import '../theme.dart';
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _goNext();
  }

  // 자동 로그인 - 토큰 확인 후 분기
  Future<void> _goNext() async {
    await Future.delayed(const Duration(seconds: 2));
    final loggedIn = await AuthService.isLoggedIn();
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
      backgroundColor: AppColors.primary,
      body: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(28),
                  ),
                  child: const Icon(Icons.warning_amber_rounded,
                      size: 52, color: Colors.white),
                ),
                const SizedBox(height: 28),
                const Text(
                  '졸음 가드', // 기획안 타이틀 반영
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '졸기 전 · 졸 때 · 졸고 나서', // 기획안 서브타이틀 반영
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 56),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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