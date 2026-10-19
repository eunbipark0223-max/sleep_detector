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

import 'package:flutter/material.dart'; // 안드로이드,ios 스타일의 기본 디자인 UI 요소가 들어있는 Flutter 공식 핵심 라이브러리
import '../theme.dart'; // 앱 전체에 적용할 디자인 시스템
import '../services/auth_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

class SplashScreen extends StatefulWidget{ // extends StatelessWidget 화면이 켜진 후 스스로 데이터가 바뀌어 화면을 재연출할 필요가 없는(상태가 없는) 정적 위젯
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
 // key는 이 위젯의 위치를 식별할 때 사용하는 고유 ID
  @override
  void initState() { // 화면이 만들어질 때 딱 한 번 실행
    super.initState();
    _goNext(); // initState는 async로 만들 수 없다
  }

  // 자동 로그인 - 토큰 확인 후 분기
  Future<void> _goNext() async { // 나중에 끝나는데 돌려줄 값은 없다
    await Future.delayed(const Duration(seconds: 2));
    final loggedIn = await AuthService.isLoggedIn();
    if(!mounted) return;

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
          builder: (_) => loggedIn ? const MainScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) { // Flutter가 이 위젯을 화면에 그려야 할 때 자동으로 호출하는 함수
    // BuildContext context 이 위젯이 전체 위젯 나무(Widget Tree)에서 어느 위치에 속해 있는지레 대한 지도 정보
    return Scaffold(
      backgroundColor: AppColors.primary,
        body: Stack(
          children: [
            Center(
              // 로고는 중앙
              child: Column(
                mainAxisSize: MainAxisSize.min, // 없으면 가운데 정렬이 안된다
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
                    '졸음 가드',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'AI가 지키는 졸음 없는 운전',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.85),
                    ),
                  ),
                ],
              ),
            ),
            Align(
              // 부서명은 하단
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
                      'AI 졸음 감지 · 능동형 안전 알림',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.9),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sleepy Driving Guard',
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