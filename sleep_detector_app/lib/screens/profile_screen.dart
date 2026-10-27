// ═══════════════════════════════════════════════════════════════
// screens/profile_screen.dart — 내 정보
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/profile_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 신고 건수 → 경고 건수, 내 기준 표시만 추가
//   - AuthService.me() 로 내 정보(이름 · 이메일 · 역할 · 가입 방식 · 가입일)를 보여 준다
//   - main_screen 의 ≡ 메뉴 → 내 정보 에서 Navigator.push 로 열리므로 Scaffold · AppBar 를 직접 가진다
//
// [연결 대기]
//   - 경고 건수: C 의 api_service.fetchMyEvents() 가 생기면 거기서 센다 (지금은 '—')
//   - 내 눈 기준: A 의 eye_monitor 개인 기준이 생기면 보여 준다 (지금은 '측정 전')
//   - 프로필 사진: 서버 /users/me/photo 는 있지만 서버 주소 통일(config.dart baseUrl) 뒤에 붙인다
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>?> _future = _load();

  // 화면(FutureBuilder)이 받기 전에 요청이 먼저 실패해도 '처리 안 된 오류'로 새지 않게 ignore() 를 붙인다
  // (오류는 FutureBuilder 가 받아서 화면에 안내로 보여 준다)
  Future<Map<String, dynamic>?> _load() {
    final future = AuthService.me();
    future.ignore();
    return future;
  }

  // setState 안에서는 값을 돌려주면 안 된다 (Future 를 돌려주면 오류) → 중괄호로 대입만 한다
  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  void _goLogin() {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('내 정보')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _Message(
              text: error is AuthException ? error.message : '내 정보를 불러오지 못했습니다',
              buttonText: '다시 시도',
              onPressed: _retry,
            );
          }
          final user = snapshot.data;
          if (user == null) {
            return _Message(text: '로그인 정보가 만료되었습니다. 다시 로그인해 주세요', buttonText: '로그인 화면으로', onPressed: _goLogin);
          }
          return _Body(user: user);
        },
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final Map<String, dynamic> user;
  const _Body({required this.user});

  String _text(String key) {
    final value = user[key];
    return value is String ? value.trim() : '';
  }

  String get _roleLabel => _text('role') == 'admin' ? '관리자' : '기사';

  String get _providerLabel => _text('provider') == 'google' ? '구글 로그인' : '이메일';

  // created_at 은 2026-10-14T09:30:00 같은 글자 — 앞 10자(날짜)만 보여 준다
  String get _joined {
    final raw = _text('created_at');
    return raw.length >= 10 ? raw.substring(0, 10) : '—';
  }

  @override
  Widget build(BuildContext context) {
    final name = _text('name');
    final email = _text('email');
    final initial = (name.isNotEmpty ? name : email).characters.firstOrNull ?? '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 36,
                  backgroundColor: AppColors.primary,
                  child: Text(initial, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w700, color: Colors.white)),
                ),
                const SizedBox(height: 12),
                Text(name.isEmpty ? '이름 없음' : name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Chip(
                  label: Text(_roleLabel),
                  backgroundColor: AppColors.background,
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(title: '계정', rows: [
          _Row(label: '가입 방식', value: _providerLabel),
          _Row(label: '가입일', value: _joined),
        ]),
        const SizedBox(height: 12),
        const _Section(title: '운전 기록', rows: [
          _Row(label: '경고 건수', value: '—'),
          _Row(label: '내 눈 기준', value: '측정 전'),
        ]),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
            const SizedBox(height: 4),
            ...rows,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final String buttonText;
  final VoidCallback onPressed;
  const _Message({required this.text, required this.buttonText, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonText)),
          ],
        ),
      ),
    );
  }
}
