// ═══════════════════════════════════════════════════════════════
// screens/login_screen.dart — 로그인 · 회원가입
// ═══════════════════════════════════════════════════════════════
// 담당: C (10/14 D → C)   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/login_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 이메일 · 구글 로그인 (서버 JWT 로 통일)
//   - [회원가입] 탭 → signup_screen.dart (전화번호 · 차량번호 · 개인정보 동의까지 받는 가입 화면)
//   - (첫 실행 사용 동의는 splash_screen — 이미 로그인한 폰에도 한 번 나오게)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart'; // 안드로이드,ios 스타일의 기본 디자인 UI 요소가 들어있는 Flutter 공식 핵심 라이브러리
import '../theme.dart'; // 앱 전체에 적용할 디자인 시스템
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'main_screen.dart';
import 'signup_screen.dart';
import '../widgets/auth_ui.dart';

// StatefulWidget - 클래스가 두개
// 위젯은 화면을 다시 그릴 때마다 새로 만들어진다. 입력값이 사라진다. 값은 State에 따로 보관
class LoginScreen extends StatefulWidget{ // 위젯 클래스(껍데기)
  const LoginScreen({super.key});

  @override // 부모 클래스(StatefulWidget)에서 상속받은 createState()함수 재정의
  State<LoginScreen> createState() => _LoginScreenState(); // 상태를 관리할 _LoginScreenState 객체 생성
  // LoginScreen용 state로 함수 반환 타입
  // createState() 함수를 통해서 상태변수가 들어있는 상태 객체 생성
}
// 호이스팅 : Dart 컴파일러는 파일 전체를 먼저 읽고 클래스 구조를 파악하므로 선언 위치는 상관 없음
class _LoginScreenState extends State<LoginScreen> { // 상태 클래스(알맹이), 이 파일 내부에서만 쓰이는 private 클래스
  // 1.상태 변수 - 화면이 기억하는 값
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  // 2.dispose - 컨트롤러 정리
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose(); // 맨 마지막에 정리
  }

  void _goHome() {
    ApiService.resetUnauthorized(); // 다시 로그인했으니 다음 만료 때 또 로그인 화면으로 보낼 수 있게
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const MainScreen()),
    );
  }
  // 3.setState - 화면 다시 그리기
    // 이메일 로그인 (서버 JWT)
  Future<void> _loginWithEmail() async {
    if (_emailController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력하세요');
      return;
    }
    setState(() {_isLoading = true; _error = null;}); // 로딩 켜기 + 오류 지우기
    try {
      await AuthService.login(
        email: _emailController.text.trim(),
        password: _passwordController.text,
      );
      if (mounted) _goHome();
    } catch (e) { // 실패하면 오류 메시지
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally { // 성공/실패 상관없이 로딩 끄기
      if (mounted) setState(() => _isLoading = false);
    }
  }
    // 회원가입 — 입력칸이 많아서 별도 화면(signup_screen.dart). 가입에 성공하면 이메일을 들고 돌아온다
  Future<void> _openSignup() async {
    final email = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
    if (email == null || !mounted) return; // 뒤로 가기로 닫음 = 가입 안 함
    setState(() {
      _emailController.text = email; // 가입한 이메일을 채워 두고 비밀번호만 치면 되게
      _passwordController.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar( // 가장 가까운 Scaffold를 찾아 거기에 띄운다
      const SnackBar(content: Text('회원가입 완료! 로그인해주세요')),
    );
  }

  // 구글 로그인 (Firebase → 서버 JWT)
  Future<void> _signInWithGoogle() async {
    setState(() {_isLoading = true; _error = null;});
    try {
      // 구글 로그인 3단계 (구글 계정 선택 → Firebase 확인 → 서버 JWT 저장)는
      // D 의 AuthService.loginWithGoogle() 이 한 번에 처리한다 (google_sign_in 7 의 initialize 포함) — 10/15 팀장
      await AuthService.loginWithGoogle();
      if (mounted) _goHome();
    } catch (e) { // 취소 · 실패 메시지는 AuthService 가 한국어로 만들어 준다
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 화면 (Figma 시안: 로고 · 인사 · 아이콘 입력칸 · 큰 버튼, 디자인만 바꿈 — 기능은 위 함수 그대로) ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView( // 키보드가 올라와도 아래 버튼까지 스크롤해서 볼 수 있다
          padding: const EdgeInsets.fromLTRB(22, 34, 22, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Center(child: AuthLogo(size: 82)),
              const SizedBox(height: 19),
              const Text('다시 만나 반가워요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: -1,
                      color: AppColors.textPrimary)),
              const SizedBox(height: 6),
              const Text('졸음을 먼저 알아채 안전을 지켜드려요',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              const SizedBox(height: 29),
              _loginForm(),
              const SizedBox(height: 25),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('처음 오셨나요?', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                  TextButton(
                    onPressed: _isLoading ? null : _openSignup,
                    style: TextButton.styleFrom(minimumSize: const Size(0, 44)),
                    child: const Text('회원가입',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.navy)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: '이메일',
          icon: Icons.mail_outline,
          controller: _emailController,
          hint: '이메일을 입력하세요',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_isLoading,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: '비밀번호',
          icon: Icons.lock_outline,
          controller: _passwordController,
          hint: '비밀번호를 입력하세요',
          password: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _loginWithEmail(),
          enabled: !_isLoading,
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[ // 오류 메시지(있을 때만)
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
        ],
        if (_isLoading)
          const SizedBox(height: 58, child: Center(child: CircularProgressIndicator()))
        else ...[
          AuthButton(text: '로그인', onPressed: _loginWithEmail),
          const SizedBox(height: 14),
          _divider(), // 또는
          const SizedBox(height: 14),
          AuthButton(
            text: 'Google로 계속하기',
            primary: false,
            onPressed: _signInWithGoogle,
            leading: const Text('G',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xFF4285F4))),
          ),
        ],
      ],
    );
  }

  Widget _divider() => const Row(
    children: [
      Expanded(child: Divider(color: AppColors.cardBorder)),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('또는', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
      Expanded(child: Divider(color: AppColors.cardBorder)),
    ],
  );
}
