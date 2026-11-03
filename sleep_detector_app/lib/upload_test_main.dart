import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/auth_service.dart';
import 'theme.dart';

// 홈 화면부터 여는 시험용 시작 파일 (git 에 올리지 않아요!)
// 홈 [운행 시작] → 측정 화면 → 운행 화면(DriveScreen) 흐름을 시험한다
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AuthService.saveToken('mock-token-1'); // 로그인 대신 가짜 토큰
  runApp(MaterialApp(
    theme: buildAppTheme(),
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      appBar: AppBar(title: const Text('홈 (시험용)')),
      body: const HomeScreen(),
    ),
  ));
}