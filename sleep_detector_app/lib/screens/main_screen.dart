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
import '../widgets/contact_dialog.dart';
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
  String _callName = '기사님'; // (11/16 팀장) 홈 인사에 이름 — 음성 · 리포트와 같은 부르는 말
  String _email = ''; // 오른쪽 메뉴 머리에 보임
  final GlobalKey<ScaffoldState> _scaffoldKey =
      GlobalKey<ScaffoldState>(); // ≡ 버튼 → 오른쪽 메뉴 열기

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireContact());
  }

  void _setName(Map<String, dynamic>? user) {
    final name = AuthService.callName(user?['name'] as String?);
    final email = (user?['email'] as String? ?? '').trim();
    if (mounted && (name != _callName || email != _email)) {
      setState(() {
        _callName = name;
        _email = email;
      });
    }
  }

  // 내 정보에서 이름을 바꿨을 수 있어서 다시 읽는다 (실패하면 그대로)
  Future<void> _reloadName() async {
    try {
      _setName(await AuthService.me());
    } catch (_) {}
  }

  // (11/12 팀장 · D 요청) 기사 계정인데 전화번호 · 차량번호가 비어 있으면 입력 창 — 저장해야 진행, 막히면 [로그아웃]만.
  //   이메일 · Google · 자동 로그인 모두 이 화면으로 들어오므로 여기 한 곳에서 확인한다. '가입 첫날'이 아니라 '값이 비었는지'로 판단
  //   (입력 전에 앱을 꺼도 다음에 다시 뜸). 서버 연결이 안 되면 묻지 않고 넘어감 (운행은 막지 않음)
  Future<void> _requireContact() async {
    Map<String, dynamic>? user;
    try {
      user = await AuthService.me();
    } catch (_) {
      return;
    }
    _setName(user);
    if (!mounted || !ContactRules.missing(user)) return;
    String text(String k) => (user![k] ?? '').toString().trim();
    final result = await showDialog<Object>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ContactDialog(
        phone: text('phone'),
        vehicleNo: text('vehicle_no'),
        required: true,
      ),
    );
    if (!mounted) return;
    if (result == ContactDialog.logout) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (route) => false,
      );
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('연락처를 저장했어요')));
  }

  Widget _page(int index) {
    switch (index) {
      case 0:
        return HomeScreen(
          onOpenRecords: () => setState(() => _index = 1),
        ); // [전체 보기] → 운행 기록 탭
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
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const GuideScreen()));
      return;
    }
    if (value == 'photo') {
      // 사진 1장 테스트 — 홈 버튼에서 ≡ 메뉴로 옮김 (11/11 · 비상 시연 · 측정용이라 기사님 홈에는 안 둠)
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const UploadScreen()));
      return;
    }
    if (value == 'profile') {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const ProfileScreen()));
      _reloadName();
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('로그아웃할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              '로그아웃',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await AuthService.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  // 홈 탭 제목줄 (Figma 시안 '졸음운전 감지 앱2' — 디자인만, 메뉴 동작은 _onMenu 그대로)
  PreferredSizeWidget _homeBar([String? title]) {
    title ??= '안녕하세요, $_callName';
    return AppBar(
      toolbarHeight: 66,
      backgroundColor: const Color(0xFFF8F9FC),
      surfaceTintColor: const Color(0xFFF8F9FC),
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      titleSpacing: 18,
      centerTitle: false,
      title: Text(
        title, // 왼쪽 위 로고는 뺌 (11/12 팀장)
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.5,
          color: AppColors.textPrimary,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 18),
          child: _menuButton(),
        ),
      ],
    );
  }

  // ≡ 버튼 (흰 네모) — 누르면 오른쪽 메뉴
  Widget _menuButton() {
    return Semantics(
      label: '메뉴',
      button: true,
      child: Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _scaffoldKey.currentState?.openEndDrawer(),
          child: const SizedBox(
            width: 46,
            height: 46,
            child: Icon(Icons.menu, color: AppColors.navy),
          ),
        ),
      ),
    );
  }

  // 메뉴 한 줄 — 누르면 메뉴를 닫고 해당 화면으로
  Widget _menuItem(String value, IconData icon, String text) {
    return ListTile(
      // (11/16) 메뉴 폭을 줄여서 여백 · 간격도 줄임 — '앱 사용 가이드' 가 한 줄에 들어가게
      contentPadding: const EdgeInsets.only(left: 16, right: 8, top: 2, bottom: 2),
      horizontalTitleGap: 12,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: const Color(0xFFEDF0F8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 22, color: AppColors.navy),
      ),
      title: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textMuted),
      onTap: () {
        Navigator.of(context).pop(); // 메뉴 닫기
        _onMenu(value);
      },
    );
  }

  // 오른쪽 메뉴 — 위: 남색 머리(이름 · 이메일), 가운데: 메뉴, 맨 아래: 로그아웃
  Widget _menuDrawer() {
    final initial = _callName == '기사님' ? '기' : _callName.characters.first;
    return Drawer(
      backgroundColor: const Color(0xFFF8F9FC),
      width: MediaQuery.of(context).size.width * 0.58, // (11/16) 화면 절반 조금 넘게 — 뒤 홈이 보이게
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: EdgeInsets.fromLTRB(
              22,
              MediaQuery.of(context).padding.top + 24,
              22,
              22,
            ),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.only(topLeft: Radius.circular(24)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.white,
                  child: Text(
                    initial,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: AppColors.navy,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _callName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      if (_email.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          _email,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFFBEC8E9),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          _menuItem('profile', Icons.person_outline, '내 정보'),
          _menuItem('guide', Icons.menu_book_outlined, '앱 사용 가이드'),
          if (_showDevTools)
            _menuItem(
              'photo',
              Icons.photo_camera_outlined,
              '사진 1장 테스트',
            ), // 개발용 (기본 숨김)
          const Spacer(),
          const Divider(height: 1, color: AppColors.cardBorder),
          SafeArea(
            top: false,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 22,
                vertical: 6,
              ),
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: const Text(
                '로그아웃',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.danger,
                ),
              ),
              onTap: () {
                Navigator.of(context).pop();
                _onMenu('logout');
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      endDrawer: _menuDrawer(), // (11/16 팀장) ≡ 를 누르면 오른쪽에서 세로 전체로 미끄러져 나오는 메뉴
      appBar: _index == _mapTab
          ? null
          : _index == 0
          ? _homeBar()
          : _index == 1
          ? _homeBar('운행 기록')
          : _index == 3
          ? _homeBar('규정 도우미')
          : AppBar(
              title: Text(_titles[_index]),
              actions: [
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: _menuButton(),
                ),
              ],
            ),
      body: _page(_index),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '홈',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '운행 기록'),
          NavigationDestination(
            icon: Icon(Icons.location_on_outlined), // (11/16) 쉼터 = 위치 마커
            selectedIcon: Icon(Icons.location_on),
            label: '가까운 졸음쉼터',
          ),
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: '규정 도우미',
          ),
        ],
      ),
    );
  }
}
