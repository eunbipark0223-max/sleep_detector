// ═══════════════════════════════════════════════════════════════
// main.dart — 앱 시작 (Firebase 초기화 · 첫 화면 splash)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/main.dart (🟢 그대로, 앱 이름만 '졸음 가드')
//
// [이 파일이 하는 일]
//   - Firebase 초기화 후 MaterialApp → splash_screen
//   - theme.dart 의 색 사용
//
// [주의]
//   - 이 파일에 main() 을 쓰기 전까지는 flutter run 이 되지 않습니다 (지금은 설명만 있음)
//   - Firebase 초기화는 android/app/google-services.json 이 있어야 된다 (GitHub 에 없음 — 팀장에게 받기)
//
// [연결] screens/splash_screen.dart 의 SplashScreen (C) — 저장된 토큰을 보고 메인 / 로그인으로 보낸다
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const SleepDetectorApp());
}

class SleepDetectorApp extends StatelessWidget {
  const SleepDetectorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '졸음 가드',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
    );
  }
}
