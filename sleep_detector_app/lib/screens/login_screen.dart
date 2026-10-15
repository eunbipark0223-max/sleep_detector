// ═══════════════════════════════════════════════════════════════
// screens/login_screen.dart — 로그인 · 회원가입
// ═══════════════════════════════════════════════════════════════
// 담당: C (10/14 D → C)   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/login_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 이메일 · 구글 로그인 (서버 JWT 로 통일)
//   - 첫 실행 때 카메라 · 마이크 · 위치 사용 동의 안내
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart'; // 안드로이드,ios 스타일의 기본 디자인 UI 요소가 들어있는 Flutter 공식 핵심 라이브러리
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../theme.dart'; // 앱 전체에 적용할 디자인 시스템
import '../services/auth_service.dart';
import 'main_screen.dart';

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
  bool _isSignup = false;
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  @override
  // 2.dispose - 컨트롤러 정리
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    super.dispose(); // 맨 마지막에 정리
  }

  void _goHome() {
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
    // 회원가입
  Future<void> _signup() async {
    if (_nameController.text.isEmpty ||
        _emailController.text.isEmpty ||
        _passwordController.text.isEmpty) {
      setState(() => _error = '모든 항목을 입력하세요');
      return;
    }
    if (_passwordController.text != _passwordConfirmController.text) {
      setState(() => _error = '비밀번호가 일치하지 않습니다');
      return;
    }
    setState(() {_isLoading = true; _error = null;});
    try {
      await AuthService.signup(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          name: _nameController.text.trim()
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar( // 가장 가까운 Scaffold를 찾아 거기에 띄운다
          const SnackBar(content: Text('회원가입 완료! 로그인해주세요')),
        );
        setState(() => _isSignup = false);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // 구글 로그인 (Firebase → 서버 JWT)
  Future<void> _signInWithGoogle() async {
    setState(() {_isLoading = true; _error = null;});
    try {
      // 구글 로그인 3단계

      // 1. 구글 계정 선택창 : 구글에게 물어본다 - 계정 선택 창이 뜬다 - 사용자가 계정을 고르면 그 정보가 googleUser에 담긴다
      final googleUser = await GoogleSignIn.instance.authenticate();
      final idToken = googleUser.authentication.idToken; // idToken 꺼내기
      // 2. Firebase에 등록한다 - idToken(구글이 발급한 신분증) - Firebase가 이걸 구글에 확인해서 진짜인지 검증
      final credential = GoogleAuthProvider.credential(idToken: idToken); // Firebase 자격 증명 : 구글 신분증을 Firebase 형식으로 바꾼다
      final userCred = await FirebaseAuth.instance.signInWithCredential(credential); // Firebase 로그인
      final fbUser = userCred.user!;
      // 3. 우리 서버에 보낸다 - 서버 JWT를 받아 저장
      await AuthService.loginWithGoogle(
        email: fbUser.email ?? googleUser.email,
        name: fbUser.displayName ?? '구글 사용자',
        firebaseUid: fbUser.uid,
      );
      if (mounted) _goHome();
    } on GoogleSignInException catch (e) {
      if (e.code != GoogleSignInExceptionCode.canceled) { // 취소는 오류가 아님
        if (mounted) setState(() => _error = '구글 로그인 실패: ${e.code.name}');
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar( // appBarTheme이 적용된 것
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, size: 20),
            SizedBox(width: 8),
            Text('졸음 가드', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
      body: SingleChildScrollView( // 입력칸을 누르면 키보드가 올라와 아래쪽 버튼이 가려진다. 스크롤해서 볼 수 있다
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      _tab('로그인', !_isSignup, () => setState(() => _isSignup = false)),
                      _tab('회원가입', _isSignup, () => setState(() => _isSignup = true)),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: _isSignup ? _signupForm() : _loginForm(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  // 4.조건부 화면 - 탭에 따라 다른 폼, 상태에 따라 다른 위젯
  // 탭
  Widget _tab(String label, bool active, VoidCallback onTap){
    return Expanded( // 탭 두개가 정확히 반씩 차지한다
      child: InkWell( // 누를 수 있게 만들고 물결 효과를 준다
        onTap: onTap, // setState(() => _isSignup = false)
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: active ? AppColors.primary : AppColors.cardBorder,
                width: active ? 2 : 0.5,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
  // 5.TextField - 입력칸 + 컨트롤러
  // TextField - 입력칸
  Widget _loginForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch, //  가로를 꽉 채운다
      children: [
        _label('이메일'),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: '이메일을 입력하세요'),
        ),
        const SizedBox(height: 14),
        _label('비밀번호'),
        TextField(
          controller: _passwordController,
          obscureText: true, // 입력한 글자를 ●로 가린다
          decoration: const InputDecoration(hintText: '비밀번호를 입력하세요'),
        ),
        const SizedBox(height: 18),
        if (_error != null) ...[ // 오류 메시지(있을 때만)
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          const SizedBox(height: 12),
        ],
        if(_isLoading)
          const Center(child: CircularProgressIndicator())
        else ...[
          ElevatedButton(onPressed: _loginWithEmail, child: const Text('로그인')), // theme.dart의 elevatedButtonTheme
          const SizedBox(height: 12),
          _divider(), // 또는
          const SizedBox(height: 12),
          _googleButton(), // 구글 로그인 버튼
        ],
      ],
    );
  }
  Widget _signupForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _label('이름'),
        TextField(controller: _nameController,
            decoration: const InputDecoration(hintText: '이름을 입력하세요')),
        const SizedBox(height: 12),
        _label('이메일'),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(hintText: '이메일을 입력하세요'),
        ),
        const SizedBox(height: 12),
        _label('비밀번호'),
        TextField(
          controller: _passwordController,
          obscureText: true, // 입력한 글자를 ●로 가린다
          decoration: const InputDecoration(hintText: '대소문자·숫자·특수문자 포함 8자리 이상'),
        ),
        const SizedBox(height: 12),
        _label('비밀번호 확인'),
        TextField(controller: _passwordConfirmController, obscureText: true,
            decoration: const InputDecoration(hintText: '다시 입력하세요')),
        const SizedBox(height: 18),
        if (_error != null) ...[ // 오류 메시지(있을 때만)
          Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13)),
          const SizedBox(height: 12),
        ],
        if(_isLoading)
          const Center(child: CircularProgressIndicator())
        else
          ElevatedButton(onPressed: _signup, child: const Text('회원가입')), // theme.dart의 elevatedButtonTheme
      ],
    );
  }
  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(text, style: const TextStyle(
      fontSize: 13, fontWeight: FontWeight.w500)),
  );

  Widget _divider() => Row(
    children: [
      const Expanded(child: Divider(color: AppColors.cardBorder)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text('또는', style: TextStyle(
          fontSize: 12, color: AppColors.textMuted)),
      ),
      const Expanded(child: Divider(color: AppColors.cardBorder)),
    ],
  );

  // 3. 구글 버튼
  Widget _googleButton() => OutlinedButton.icon(
      onPressed: _signInWithGoogle,
      icon: const Text('G', style: TextStyle(
        fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF4285F4))),
      label: const Text('Google로 계속하기'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 46),
        side: const BorderSide(color: AppColors.cardBorder),
        foregroundColor: AppColors.textPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
  );
}