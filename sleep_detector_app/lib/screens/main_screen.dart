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

  // 제목줄 (11/16 R안 · readdy) — 홈은 제목 없이 오른쪽 ≡ 만 (위 로고 · 앱 이름 · 인사 없음),
  //   운행 기록 · 규정 도우미는 왼쪽 큰 제목 (애플 큰 제목)
  PreferredSizeWidget _homeBar([String? title]) {
    return AppBar(
      toolbarHeight: 68,
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: 20,
      centerTitle: false,
      title: title == null
          ? null
          : Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                color: AppColors.textPrimary,
              ),
            ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 10),
          child: _menuButton(),
        ),
      ],
    );
  }

  // ≡ 버튼 — 뒤 색 없이 아이콘만 (11/16 사용자 요청 2) — 누르면 오른쪽 메뉴
  Widget _menuButton() {
    return IconButton(
      tooltip: '메뉴',
      onPressed: () => _scaffoldKey.currentState?.openEndDrawer(),
      icon: const Icon(Icons.menu_rounded, size: 28, color: AppColors.textPrimary),
      style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
    );
  }

  // 메뉴 한 줄 (readdy) — 회색 아이콘 · 글자 · 오른쪽 꺾쇠. 누르면 메뉴를 닫고 해당 화면으로
  Widget _menuItem(String value, IconData icon, String text) {
    return InkWell(
      onTap: () {
        Navigator.of(context).pop(); // 메뉴 닫기
        _onMenu(value);
      },
      child: SizedBox(
        height: 56,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textMuted),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.fill),
            ],
          ),
        ),
      ),
    );
  }

  // 메뉴 줄 사이 얇은 선 (11/16 사용자 요청 11 — 좌우 같은 여백)
  Widget get _menuLine => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Divider(height: 1, thickness: 1, color: Color(0xFFE5E8EE)),
      );

  // 오른쪽 메뉴 — 위: 남색 머리(이름 · 이메일), 가운데: 메뉴, 맨 아래: 로그아웃
  Widget _menuDrawer() {
    final initial = _callName == '기사님' ? '기' : _callName.characters.first;
    // (11/16 R안 · readdy) 위: 진한 남색 머리(동그란 이름 첫 글자 · 이름 · 이메일), 가운데: 줄로 나눈 메뉴, 맨 아래: 로그아웃
    return Drawer(
      backgroundColor: AppColors.card,
      width: MediaQuery.of(context).size.width * 0.72,
      shape: const RoundedRectangleBorder(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: AppColors.navyDeep,
            padding: EdgeInsets.fromLTRB(24, MediaQuery.of(context).padding.top + 28, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Text(initial,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
                const SizedBox(height: 16),
                Text(_callName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: Colors.white)),
                if (_email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(_email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6))),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _menuItem('profile', Icons.person_outline_rounded, '내 정보'),
          _menuLine,
          _menuItem('guide', Icons.menu_book_outlined, '앱 사용 가이드'),
          if (_showDevTools) ...[
            _menuLine,
            _menuItem('photo', Icons.photo_camera_outlined, '사진 1장 테스트'), // 개발용 (기본 숨김)
          ],
          const Spacer(),
          const Divider(height: 1, color: Color(0xFFE5E8EE)),
          SafeArea(
            top: false,
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
              leading: const Icon(Icons.logout_rounded, color: AppColors.danger),
              title: const Text(
                '로그아웃',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.danger),
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
          ? _homeBar() // 홈은 제목 없음 (위 로고 · 앱 이름 · 인사 뺌, 11/16 사용자 요청 1)
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
      bottomNavigationBar: _TabBar(index: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}

/// 하단 탭 (11/16 R안 · readdy) — 꽉 찬 흰 바탕(투명 X, 사용자 요청 5) · 위 얇은 선 · 아이콘 + 작은 글자, 고른 탭만 남색
class _TabBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _TabBar({required this.index, required this.onTap});

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, '홈'),
    (Icons.article_outlined, Icons.article_rounded, '운행 기록'),
    (Icons.location_on_outlined, Icons.location_on_rounded, '졸음쉼터'), // (11/16) 쉼터 = 위치 마커
    (Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded, '규정 도우미'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.fill)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              for (var i = 0; i < _items.length; i++)
                Expanded(
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(i == index ? _items[i].$2 : _items[i].$1,
                            size: 26, color: i == index ? AppColors.navy : AppColors.textMuted),
                        const SizedBox(height: 3),
                        Text(_items[i].$3,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: i == index ? FontWeight.w600 : FontWeight.w500,
                              color: i == index ? AppColors.navy : AppColors.textMuted,
                            )),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
