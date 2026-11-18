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
import '../services/api_service.dart';
import '../services/auth_service.dart';
import 'find_account_screens.dart';
import 'main_screen.dart';
import 'signup_screen.dart';
import '../widgets/auth_ui.dart';
import '../widgets/google_logo.dart';
import '../theme.dart';

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
  // (11/17 사용자 요청) 구글 계정 고르기 창이 떠 있는 동안 뒤 화면은 그냥 흰색 (입력칸 · 버튼 숨김)
  bool _googleOpen = false;
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

  // (11/18 사용자 요청) 이메일 찾기 · 비밀번호 찾기
  Future<void> _openFindEmail() async {
    final r = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const FindEmailScreen()));
    if (r == FindEmailScreen.goReset && mounted) await _openResetPassword();
  }

  Future<void> _openResetPassword() async {
    final email = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ResetPasswordScreen()));
    if (email == null || !mounted) return;
    setState(() {
      _emailController.text = email; // 바꾼 계정 이메일을 채워 두고 새 비밀번호만 치면 되게
      _passwordController.clear();
      _error = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('비밀번호를 바꿨어요\n새 비밀번호로 로그인해 주세요')));
  }

  // 구글 로그인 (Firebase → 서버 JWT)
  Future<void> _signInWithGoogle() async {
    setState(() {_isLoading = true; _googleOpen = true; _error = null;});
    try {
      // 구글 로그인 3단계 (구글 계정 선택 → Firebase 확인 → 서버 JWT 저장)는
      // D 의 AuthService.loginWithGoogle() 이 한 번에 처리한다 (google_sign_in 7 의 initialize 포함) — 10/15 팀장
      await AuthService.loginWithGoogle();
      if (mounted) _goHome();
    } on GoogleCanceled {
      // (11/17 사용자 요청) 창을 닫은 건 오류가 아님 — 아무 문구도 띄우지 않는다
    } catch (e) { // 실패 메시지는 AuthService 가 한국어로 만들어 준다
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() {_isLoading = false; _googleOpen = false;});
    }
  }

  // ── 화면 (Figma 시안: 로고 · 인사 · 아이콘 입력칸 · 큰 버튼, 디자인만 바꿈 — 기능은 위 함수 그대로) ──
  @override
  Widget build(BuildContext context) {
    // (11/17 사용자 요청) 화면 전체 흰색 · 카드 없음 · 로고 자리 → 입력칸 → 버튼 → 회원가입 (제목 · 배지 · 권한 안내 글 없음)
    return Scaffold(
      backgroundColor: AuthUi.page,
      body: _googleOpen ? const SizedBox.expand() : SafeArea(
        child: Center(
          child: SingleChildScrollView( // 키보드가 올라와도 아래 버튼까지 스크롤해서 볼 수 있다
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: AuthLogo(size: 64)),
                const SizedBox(height: 36),
                _loginForm(),
                const SizedBox(height: 24),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('계정이 없나요? ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  GestureDetector(
                    onTap: _isLoading ? null : _openSignup,
                    child: const Text('회원가입하기',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ]),
              ],
            ),
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
          controller: _emailController,
          hint: '이메일을 입력하세요',
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_isLoading,
        ),
        const SizedBox(height: 14),
        AuthField(
          label: '비밀번호',
          controller: _passwordController,
          hint: '비밀번호를 입력하세요',
          password: true,
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _loginWithEmail(),
          enabled: !_isLoading,
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[ // 오류 메시지(있을 때만)
          AuthNote(_error!, error: true),
          const SizedBox(height: 12),
        ],
        if (_isLoading)
          const SizedBox(height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
        else ...[
          AuthButton(text: '로그인', onPressed: _loginWithEmail),
          const SizedBox(height: 6),
          _findRow(), // 이메일 찾기 | 비밀번호 찾기
          const SizedBox(height: 6),
          _divider(), // 또는
          const SizedBox(height: 14),
          AuthButton(
            text: 'Google로 계속하기',
            primary: false,
            onPressed: _signInWithGoogle,
            leading: const GoogleLogo(size: 20), // 구글 공식 G 로고 (관리자 웹과 같게)
          ),
        ],
      ],
    );
  }

  // 로그인 버튼 아래 작은 회색 글자 두 개 · 가운데 얇은 세로줄 (애플 로그인 화면처럼)
  Widget _findRow() {
    Widget link(String text, VoidCallback onTap) => TextButton(
          onPressed: onTap,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          child: Text(text),
        );
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      link('이메일 찾기', _openFindEmail),
      Container(width: 1, height: 11, color: AppColors.fill),
      link('비밀번호 찾기', _openResetPassword),
    ]);
  }

  Widget _divider() => Row(
    children: [
      const Expanded(child: Divider(color: AppColors.fill)),
      const Padding(
        padding: EdgeInsets.symmetric(horizontal: 12),
        child: Text('또는', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
      ),
      const Expanded(child: Divider(color: AppColors.fill)),
    ],
  );
}
