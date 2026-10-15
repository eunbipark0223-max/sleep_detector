// ═══════════════════════════════════════════════════════════════
// screens/main_screen.dart — 하단 탭 (홈 · 운행 기록 · 규정 도우미)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/main_screen.dart (🟡 탭 변경)
//
// [이 파일이 하는 일]
//   - 수업: 홈 · 위험 지도 · 내 신고 → 홈 · 운행 기록 · 규정 도우미
//   - ≡ 메뉴: 내 정보 · 로그아웃
//
// [연결 — 각 화면의 클래스 이름]
//   - 홈 HomeScreen · 운행 기록 HistoryScreen (D) · 규정 도우미 ChatScreen (B) · 내 정보 ProfileScreen (D) · 로그아웃 뒤 LoginScreen (C)
//   - 탭을 누를 때마다 그 화면을 새로 만든다 (운행 기록은 열 때마다 최신 경고 목록)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const List<String> _titles = ['홈', '운행 기록', '규정 도우미'];

  int _index = 0;

  Widget _page(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return const HistoryScreen();
      default:
        return const ChatScreen();
    }
  }

  Future<void> _onMenu(String value) async {
    if (value == 'profile') {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('로그아웃', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_index]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            tooltip: '메뉴',
            onSelected: _onMenu,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'profile', child: Text('내 정보')),
              PopupMenuItem(value: 'logout', child: Text('로그아웃')),
            ],
          ),
        ],
      ),
      body: _page(_index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.history), label: '운행 기록'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '규정 도우미'),
        ],
      ),
    );
  }
}
