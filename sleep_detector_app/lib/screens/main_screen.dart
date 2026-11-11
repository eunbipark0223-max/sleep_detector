// ═══════════════════════════════════════════════════════════════
// screens/main_screen.dart — 하단 탭 (홈 · 운행 기록 · 가까운 졸음쉼터 · 규정 도우미)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/main_screen.dart (🟡 탭 변경)
//
// [이 파일이 하는 일]
//   - 수업: 홈 · 위험 지도 · 내 신고 → 홈 · 운행 기록 · 가까운 졸음쉼터 · 규정 도우미
//   - 가까운 졸음쉼터: 홈 화면 버튼에서 아래 탭으로 옮김 (11/10 팀장 의견, C 가 옮김)
//       지도 화면(B)은 제목줄이 따로 있어서, 이 탭에서는 위 제목줄 · ≡ 메뉴를 숨긴다 (제목줄이 두 줄로 겹치지 않게)
//   - ≡ 메뉴: 내 정보 · 로그아웃
//
// [연결 — 각 화면의 클래스 이름]
//   - 홈 HomeScreen · 운행 기록 HistoryScreen (D) · 가까운 졸음쉼터 MapScreen (B) · 규정 도우미 ChatScreen (B) · 내 정보 ProfileScreen (D) · 로그아웃 뒤 LoginScreen (C)
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
import 'map_screen.dart';
import 'guide_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';

// [사진 1장 테스트] 같은 개발용 메뉴를 보일지 (기본 숨김 — 팀장 11/11, 시연 · 측정 때 --dart-define=SHOW_DEV_TOOLS=true)
const bool _showDevTools = bool.fromEnvironment('SHOW_DEV_TOOLS');

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  static const List<String> _titles = ['홈', '운행 기록', '가까운 졸음쉼터', '규정 도우미'];
  static const int _mapTab = 2; // 지도 화면은 제목줄이 따로 있음 → 이 탭에서는 위 제목줄을 숨김

  int _index = 0;

  Widget _page(int index) {
    switch (index) {
      case 0:
        return HomeScreen(onOpenRecords: () => setState(() => _index = 1)); // [전체 보기] → 운행 기록 탭
      case 1:
        return const HistoryScreen();
      case _mapTab:
        return const MapScreen();
      default:
        return const ChatScreen();
    }
  }

  Future<void> _onMenu(String value) async {
    if (value == 'guide') {
      // 앱 사용 가이드 (11/11 · 부엉이로 쓰는 순서 · 색의 뜻)
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      return;
    }
    if (value == 'photo') {
      // 사진 1장 테스트 — 홈 버튼에서 ≡ 메뉴로 옮김 (11/11 · 비상 시연 · 측정용이라 기사님 홈에는 안 둠)
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
      return;
    }
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

  // 홈 탭 제목줄 (Figma 시안 '졸음운전 감지 앱2' — 디자인만, 메뉴 동작은 _onMenu 그대로)
  PreferredSizeWidget _homeBar([String title = '안녕하세요, 기사님']) {
    PopupMenuItem<String> item(String value, IconData icon, String text, {bool danger = false}) => PopupMenuItem(
          value: value,
          height: 54,
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: const Color(0xFFEDF0F8), borderRadius: BorderRadius.circular(11)),
                child: Icon(icon, size: 20, color: danger ? AppColors.danger : AppColors.navy),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(text,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: danger ? AppColors.danger : AppColors.textPrimary)),
              ),
              if (!danger) const Icon(Icons.chevron_right, size: 18, color: AppColors.textMuted),
            ],
          ),
        );
    return AppBar(
      toolbarHeight: 66,
      backgroundColor: const Color(0xFFF8F9FC),
      surfaceTintColor: const Color(0xFFF8F9FC),
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      titleSpacing: 18,
      centerTitle: false,
      title: Text(title, // 왼쪽 위 로고는 뺌 (11/12 팀장)
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: AppColors.textPrimary)),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: PopupMenuButton<String>(
            tooltip: '메뉴',
            onSelected: _onMenu,
            offset: const Offset(0, 54),
            color: Colors.white,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(19), side: const BorderSide(color: AppColors.cardBorder)),
            itemBuilder: (_) => [
              item('profile', Icons.person_outline, '내 정보'),
              item('guide', Icons.menu_book_outlined, '앱 사용 가이드'),
              if (_showDevTools) item('photo', Icons.photo_camera_outlined, '사진 1장 테스트'), // 개발용 (기본 숨김)
              item('logout', Icons.logout, '로그아웃', danger: true),
            ],
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: const Icon(Icons.menu, color: AppColors.navy),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _index == _mapTab ? null : _index == 0 ? _homeBar() : _index == 1 ? _homeBar('운행 기록') : AppBar(
        title: Text(_titles[_index]),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu),
            tooltip: '메뉴',
            onSelected: _onMenu,
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'guide', child: Text('앱 사용 가이드')),
              if (_showDevTools) const PopupMenuItem(value: 'photo', child: Text('사진 1장 테스트')), // 개발용 (기본 숨김)
              const PopupMenuItem(value: 'profile', child: Text('내 정보')),
              const PopupMenuItem(value: 'logout', child: Text('로그아웃')),
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
          NavigationDestination(icon: Icon(Icons.local_cafe_outlined), selectedIcon: Icon(Icons.local_cafe), label: '가까운 졸음쉼터'),
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: '규정 도우미'),
        ],
      ),
    );
  }
}
