// ═══════════════════════════════════════════════════════════════
// screens/main_screen.dart — 하단 탭 (홈 · 운행 기록 · 가까운 졸음쉼터 · 규정 도우미)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
//
// [이 파일이 하는 일]
//   - 탭: 홈 · 운행 기록 · 가까운 졸음쉼터 · 규정 도우미
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
import 'dart:async';

import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../design_tokens.dart';
import '../theme.dart';
import '../widgets/press.dart';
import '../widgets/contact_dialog.dart';
import '../widgets/web_ui.dart';
import 'chat_screen.dart';
import 'history_screen.dart';
import 'home_screen.dart';
import 'login_screen.dart';
import 'map_screen.dart';
import 'notice_screen.dart';
import 'guide_screen.dart';
import 'profile_screen.dart';
import 'upload_screen.dart';
import '../widgets/month_report.dart';

// [사진 1장 테스트] 같은 개발용 메뉴를 보일지 (기본 숨김 — 팀장 11/11, 시연 · 측정 때 --dart-define=SHOW_DEV_TOOLS=true)
const bool _showDevTools = bool.fromEnvironment('SHOW_DEV_TOOLS');

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  // (11/18 피드백) 규정 도우미를 다시 아래 탭으로 — 홈 · 운행 기록 · 졸음쉼터 · 규정 도우미 · MY
  static const List<String> _titles = ['홈', '운행 기록', '가까운 졸음쉼터', '규정 도우미', 'MY'];
  static const int _mapTab = 2; // 지도 화면은 제목줄이 따로 있음 → 이 탭에서는 위 제목줄을 숨김
  static const int _chatTab = 3;
  static const int _myTab = 4; // (11/17) 아래 탭 MY — 사용 가이드 · 로그아웃 (예전 ≡ 메뉴)

  int _index = 0;
  String _callName = '기사님'; // (11/16 팀장) 홈 인사에 이름 — 음성 · 리포트와 같은 부르는 말
  String _email = '';
  String _plainName = ''; // (11/18) MY 카드 — '기사님' 붙이지 않은 이름

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _requireContact());
    _loadUnread(); // 알림 종 빨간 숫자
    // (11/17) 안 읽은 알림 숫자를 30초마다 다시 센다 (운행 중 생긴 경고 · 관리자 처리도 바로 반영)
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) => _loadUnread());
  }

  Timer? _unreadTimer;

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  void _setName(Map<String, dynamic>? user) {
    final n = AuthService.driverName(user?['name'] as String?);
    final name = n.isEmpty ? '기사님' : '$n 기사님'; // (11/17) 화면은 '이름 + 기사님'
    _plainName = n; // (11/18) MY 카드에는 '기사님' 없이 이름만
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
      case _chatTab:
        return const ChatScreen();
      default:
        return const MapScreen();
    }
  }

  // (11/17 사용자 요청) 알림 = 홈 오른쪽 위 종 버튼. 빨간 숫자 = 알림 화면을 마지막으로 본 뒤 생긴 경고 수
  int _unread = 0;

  Future<void> _loadUnread() async {
    try {
      // (11/18) 알림 = 관리자가 조치완료한 경고 중 아직 안 본 것 (notice_screen 과 같은 기준)
      final seen = await AuthService.getNoticeSeenIds();
      final n = noticeEvents(await ApiService.fetchMyEvents()).where((e) => !seen.contains(e.id)).length;
      if (mounted && n != _unread) setState(() => _unread = n);
    } catch (_) {} // 서버 연결이 안 되면 숫자 없이
  }

  Future<void> _openNotice() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NoticeScreen()));
    _loadUnread();
  }

  // 머리줄 오른쪽 둥근 아이콘 버튼 (빨간 숫자 배지 선택)
  Widget _barIcon(IconData icon, String tip, VoidCallback onTap, {int badge = 0, Widget? child}) {
    return Stack(clipBehavior: Clip.none, children: [
      IconButton(
        tooltip: tip,
        onPressed: onTap,
        icon: child ?? Icon(icon, size: 26, color: AppColors.textPrimary),
        style: IconButton.styleFrom(minimumSize: const Size(44, 44)),
      ),
      // (11/18 피드백) 새 알림 = 숫자 없이 아이폰처럼 빨간 점 하나 (남색은 알림인지 잘 안 보여서 빨강으로)
      if (badge > 0)
        Positioned(
          right: 10,
          top: 9,
          child: Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: const Color(0xFFFF3B30), // 애플 시스템 빨강
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.background, width: 1.5),
            ),
          ),
        ),
    ]);
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
      // (11/18 피드백) 홈 머리줄 왼쪽 = 기사 프로필(남색 동그라미) + '안녕하세요, 홍길동 기사님' — 누르면 내 정보
      title: title == null
          ? Align(alignment: Alignment.centerLeft, child: _homeProfile())
          : Text(
              title,
              // (11/18 디자인 토큰) 홈을 뺀 탭 제목 모두 같은 단계 · 'MY' 는 영어 두 글자가 붙어 보여서 글자 사이만 아주 살짝
              style: AppType.title1.copyWith(color: AppColors.textPrimary, letterSpacing: title == 'MY' ? 0.8 : null),
            ),
      // (11/17 사용자 요청) ≡ 버튼 없음 — 메뉴는 아래 탭 [MY] 로. 홈은 오른쪽 위에 [규정 도우미 로봇] [알림 종]
      actions: title == null
          ? [
              _barIcon(Icons.notifications_none_rounded, '알림', _openNotice, badge: _unread),
              const SizedBox(width: 18), // (11/18 피드백) 종을 조금 안쪽으로
            ]
          : null,
      // (11/18 피드백) 머리줄 아래 선은 뺌 — 흰 바탕이 이어지게
    );
  }

  // 홈 왼쪽 위 — 남색 프로필 동그라미 + 인사 두 줄 (누르면 내 정보)
  Widget _homeProfile() {
    final initial = _plainName.isEmpty ? '나' : _plainName.characters.first;
    return Press(
      scale: 0.97,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onMenu('profile'),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // (11/18 피드백) 글자를 동그라미 정가운데에 · '안녕하세요' 없이 '김기사 기사님' 만
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
            child: Text(initial,
                textAlign: TextAlign.center,
                strutStyle: const StrutStyle(fontSize: 17, height: 1, forceStrutHeight: true),
                style: const TextStyle(fontSize: 17, height: 1, fontWeight: FontWeight.w700, color: Colors.white)),
          ),
          const SizedBox(width: 11),
          // (11/19 사용자 요청) '좋은 오후예요' 같은 인사 없이 이름만
          Text(_callName,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.4, color: AppColors.navy)),
        ]),
      ),
    );
  }

  // ── MY 탭 (11/17 사용자 요청 — ≡ 메뉴 대신, 다른 앱의 아래 'MY' 탭처럼) ─────────────
  //   애플 설정 화면처럼 흰 카드 묶음: [내 프로필 카드] · [사용 가이드] · [로그아웃]
  Widget _myPage() {
    final initial = _plainName.isEmpty ? '나' : _plainName.characters.first;
    // (11/18 피드백) 로그아웃은 맨 아래 (아래 여백 조금) · 투명도 있는 남색 알약
    return Column(children: [
      Expanded(child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 110), // (11/18) 다른 탭과 같은 위쪽 여백 · (11/19) 떠 있는 탭바 높이만큼
      children: [
        // 내 프로필 — 누르면 내 정보 화면
        _myGroup([
          _myRow(
            onTap: () => _onMenu('profile'),
            leading: Container(
              width: 52,
              height: 52,
              alignment: Alignment.center,
              // (11/18 피드백) 프로필만 남색 — 동그라미 남색 · 글자 흰색
              decoration: const BoxDecoration(color: AppColors.navy, shape: BoxShape.circle),
              child: Text(initial, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
            // (11/18 사용자 요청) '기사님' · 이메일 빼고 이름만 + '내 정보 보기'
            title: _callName, // (11/18 피드백) '홍길동 기사님' (이름이 없으면 '기사님')
            sub: '내 정보 보기',
            height: 84,
          ),
        ]),
        const SizedBox(height: 24),
        // (11/19 사용자 요청 · Headspace 통계) 이번 달 운행 분석 — 경고 수 · 단계별 · 시간대 · 정리
        const MonthReport(),
        const SizedBox(height: 24),
        _myGroup([
          _myRow(onTap: () => _onMenu('guide'), icon: Icons.menu_book_rounded, title: '사용 가이드'),
          if (_showDevTools) _myRow(onTap: () => _onMenu('photo'), icon: Icons.photo_camera_rounded, title: '사진 1장 테스트'),
        ]),
        const SizedBox(height: 14),
        // (11/18 피드백) 로그아웃 — 원래 자리 · 남색
        _myGroup([
          _myRow(onTap: () => _onMenu('logout'), icon: Icons.logout_rounded, title: '로그아웃', color: AppColors.navy, chevron: false),
        ]),
      ],
    )),

    ]);
  }

  // 흰 카드 하나에 줄 여러 개 — 줄 사이 얇은 선 (아이콘 뒤부터)
  Widget _myGroup(List<Widget> rows) => WebCard(
        padding: EdgeInsets.zero,
        child: Column(children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1, thickness: 1, indent: 56, color: AppColors.line),
            rows[i],
          ],
        ]),
      );

  // MY 한 줄 — 모든 줄 같은 높이(56) · 같은 아이콘(22) · 같은 글자(15.5)
  Widget _myRow({
    required VoidCallback onTap,
    required String title,
    IconData? icon,
    Widget? leading,
    String? sub,
    Color? color,
    bool chevron = true,
    double height = 56,
  }) {
    return Press(scale: 0.98, child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Row(children: [
            leading ?? Icon(icon, size: 22, color: color ?? AppColors.textSecondary),
            SizedBox(width: leading != null ? 14 : 16),
            Expanded(
              child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: sub != null ? 17 : AppType.body.fontSize, // 애플 본문 17
                        fontWeight: sub != null ? FontWeight.w600 : FontWeight.w500,
                        color: color ?? AppColors.textPrimary)),
                if (sub != null) ...[
                  const SizedBox(height: 2),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
                ],
              ]),
            ),
            if (chevron) const Icon(Icons.chevron_right_rounded, size: 22, color: AppleGray.chevron),
          ]),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // (11/19 사용자 요청) 홈 · 운행 기록 · MY 는 내용이 떠 있는 탭바 뒤로 자연스럽게 흐름 (탭바 둘레 아이보리 틀 없이)
      //   졸음쉼터(지도) · 규정 도우미(아래 입력칸)는 가리지 않게 그대로
      extendBody: _index == 0 || _index == 1 || _index == _myTab,
      appBar: _index == _mapTab
          ? null
          : _index == 0
          ? _homeBar() // 홈은 로고 자리만
          : _homeBar(_titles[_index]), // 운행 기록 · 규정 도우미 · MY = 왼쪽 큰 제목 (규정 도우미 화면은 탭 안)
      // (11/18 피드백) 탭을 바꾸면 내용이 부드럽게 바뀜 (살짝 옆으로 미끄러지며 나타남)
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        switchInCurve: AppMotion.curve,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0.04, 0), end: Offset.zero).animate(anim),
            child: child,
          ),
        ),
        child: KeyedSubtree(key: ValueKey(_index), child: _index == _myTab ? _myPage() : _page(_index)),
      ),
      bottomNavigationBar: _TabBar(
        index: _index,
        onTap: (i) {
          setState(() => _index = i);
          if (i == 0) _loadUnread(); // 홈으로 돌아오면 알림 숫자 다시
        },
      ),
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
    (Icons.smart_toy_outlined, Icons.smart_toy_rounded, '규정 도우미'), // (11/18 피드백) 다시 아래 탭으로
    (Icons.person_outline_rounded, Icons.person_rounded, 'MY'), // (11/17) ≡ 메뉴 대신
  ];

  // (11/19 사용자 요청) 탭바 색은 남색 하나로 — 평소 연한 남색 · 누르면 진한 남색
  static final Color _soft = AppColors.navy.withValues(alpha: 0.38);

  @override
  Widget build(BuildContext context) {
    // (11/19 사용자 요청 · Headspace 탭바) 화면 위에 둥둥 떠 있는 둥근 흰 알약 — 고른 탭 뒤에 연한 둥근 칸이 미끄러져 옴
    //   색은 남색 하나 (평소 연한 남색 · 고르면 진한 남색)
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
        child: Container(
          height: 64,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.94), // 뒤로 흐르는 내용이 아주 살짝 비침
            borderRadius: BorderRadius.circular(999),
            boxShadow: const [
              BoxShadow(color: Color(0x142D2C2B), blurRadius: 24, offset: Offset(0, 6)),
              BoxShadow(color: Color(0x0A2D2C2B), blurRadius: 4, offset: Offset(0, 1)),
            ],
          ),
          child: LayoutBuilder(builder: (context, c) {
            final w = c.maxWidth / _items.length;
            return Stack(children: [
              // 고른 탭 뒤 연한 둥근 칸 (따뜻한 연회색 — 사진처럼)
              AnimatedPositioned(
                duration: AppMotion.normal,
                curve: AppMotion.curve,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(color: AppleGray.fill, borderRadius: BorderRadius.circular(999)),
                ),
              ),
              Row(children: [
                for (var i = 0; i < _items.length; i++)
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onTap(i),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_items[i].$2, size: 21, color: i == index ? AppColors.navy : _soft), // (11/19) 애플처럼 조금 작게
                        const SizedBox(height: 3),
                        Text(_items[i].$3,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: i == index ? FontWeight.w700 : FontWeight.w500,
                              color: i == index ? AppColors.navy : _soft,
                            )),
                      ]),
                    ),
                  ),
              ]),
            ]);
          }),
        ),
      ),
    );
  }
}
