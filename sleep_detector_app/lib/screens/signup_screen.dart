// ═══════════════════════════════════════════════════════════════
// screens/signup_screen.dart — 회원가입 (이름 · 이메일 · 비밀번호 · 전화번호 · 차량번호 · 개인정보 동의)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
//
// [이 파일이 하는 일]
//   - 로그인 화면의 [회원가입] 탭을 누르면 열리는 가입 화면
//   - 입력 → 칸마다 형식 검사(서버와 같은 규칙) → 개인정보 동의 체크 → AuthService.signup → 서버가 users 에 저장
//   - 가입에 성공하면 이메일을 들고 로그인 화면으로 돌아간다 (Navigator.pop(email)) — 로그인 화면이 이메일 칸을 채워 줌
//
// [서버 약속] POST /users/signup {email, password, name, phone, vehicle_no, privacy_agreed}
//   - 전화번호는 '010-1234-5678', 차량번호는 '12가 3456' · '서울 12가 3456' 모양으로 서버가 정리해 저장
//   - 이 화면의 검사는 빨리 알려 주려는 것이고, 최종 검사는 서버가 한다 (서버가 틀리다고 하면 그 문구를 그대로 보여 줌)
//   - 개인정보 동의는 서버 DB 에 칸을 늘리지 않아서 저장하지 않고, '동의해야 가입' 만 서버가 확인한다
//
// [고칠 곳] 동의 문구는 아래 _consentText — 팀에서 확정한 문구로 바꿀 것 (보관 기간 등)
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  // 서버(schema/request.py)와 같은 규칙
  static final RegExp _emailRule = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _vehicleRule = RegExp(r'^(?:[가-힣]{2,4}\s*)?\d{2,3}\s*[가-힣]\s*\d{4}$');
  static final RegExp _specialRule = RegExp(r'[!@#$%^&*(),.?":{}|<>]');

  static const String _consentText =
      '졸음 가드는 회원가입과 졸음 경고 대응을 위해 아래 개인정보를 수집 · 이용해요.\n\n'
      '• 수집 항목: 이름, 이메일, 비밀번호(암호화해서 저장), 전화번호, 차량번호\n'
      '• 이용 목적: 로그인 등 계정 관리, 졸음 경고가 났을 때 관리자가 기사님께 연락\n'
      '• 보관 기간: 서비스를 이용하는 동안\n\n'
      '동의하지 않으면 회원가입을 할 수 없어요.';

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();

  bool _agreed = false;
  bool _agreeError = false; // 동의 안 하고 눌렀을 때 체크박스 아래에 안내
  bool _loading = false;
  String? _error; // 서버가 돌려준 오류 문구

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _passwordConfirm.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  // ── 칸별 검사 (문제 없으면 null) ─────────────────────────────
  String? _checkName(String? v) => (v ?? '').trim().isEmpty ? '이름을 입력하세요' : null;

  String? _checkEmail(String? v) => _emailRule.hasMatch((v ?? '').trim()) ? null : '이메일 형식이 올바르지 않아요';

  String? _checkPassword(String? v) {
    final p = v ?? '';
    if (p.length < 8) return '비밀번호는 8자리 이상이어야 해요';
    if (!RegExp(r'[A-Z]').hasMatch(p)) return '대문자를 1개 이상 넣어 주세요';
    if (!RegExp(r'[a-z]').hasMatch(p)) return '소문자를 1개 이상 넣어 주세요';
    if (!RegExp(r'[0-9]').hasMatch(p)) return '숫자를 1개 이상 넣어 주세요';
    if (!_specialRule.hasMatch(p)) return '특수문자를 1개 이상 넣어 주세요 (! @ # \$ % ^ & * 등)';
    return null;
  }

  String? _checkPasswordConfirm(String? v) => v == _password.text ? null : '비밀번호가 일치하지 않아요';

  String? _checkPhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length >= 9 && digits.length <= 11 ? null : '전화번호 형식이 올바르지 않아요 (예: 010-1234-5678)';
  }

  String? _checkVehicle(String? v) =>
      _vehicleRule.hasMatch((v ?? '').trim()) ? null : '차량번호 형식이 올바르지 않아요 (예: 12가 3456, 서울 12가 3456)';

  // ── 가입 ────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    final formOk = _formKey.currentState!.validate();
    setState(() {
      _agreeError = !_agreed;
      _error = null;
    });
    if (!formOk || !_agreed) return;

    setState(() => _loading = true);
    try {
      await AuthService.signup(
        email: _email.text.trim(),
        password: _password.text,
        name: _name.text.trim(),
        phone: _phone.text.trim(),
        vehicleNo: _vehicle.text.trim(),
        privacyAgreed: _agreed,
      );
      if (mounted) Navigator.of(context).pop(_email.text.trim());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '가입하지 못했어요. 잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showConsent() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('개인정보 수집 · 이용 동의'),
        content: const SingleChildScrollView(
          child: Text(_consentText, style: TextStyle(fontSize: 14, height: 1.5)),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('닫기'))],
      ),
    );
  }

  // ── 화면 (Figma 시안: 인사 · 아이콘 입력칸 · 둥근 동의 체크 · 큰 버튼, 디자인만 바꿈 — 검사 · 가입은 위 함수 그대로) ──
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        toolbarHeight: 66,
        leading: IconButton(
          icon: const Icon(Icons.chevron_left, size: 30),
          tooltip: '뒤로 가기',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text('회원가입',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.5,
                color: AppColors.textPrimary)),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 17, 22, 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('안전 운전을 시작해 볼까요?',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.8,
                        color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                const Text('꼭 필요한 정보만 알려 주세요.',
                    style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 21),
                AuthField(
                  label: '이름',
                  icon: Icons.person_outline,
                  controller: _name,
                  hint: '이름을 입력하세요',
                  enabled: !_loading,
                  height: 53,
                  textInputAction: TextInputAction.next,
                  validator: _checkName,
                ),
                const SizedBox(height: 13),
                AuthField(
                  label: '이메일',
                  icon: Icons.mail_outline,
                  controller: _email,
                  hint: '이메일을 입력하세요',
                  enabled: !_loading,
                  height: 53,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: _checkEmail,
                ),
                const SizedBox(height: 13),
                AuthField(
                  label: '비밀번호',
                  icon: Icons.lock_outline,
                  controller: _password,
                  hint: '비밀번호를 입력하세요',
                  helper: '대소문자·숫자·특수문자 포함 8자리 이상',
                  password: true,
                  enabled: !_loading,
                  height: 53,
                  textInputAction: TextInputAction.next,
                  validator: _checkPassword,
                ),
                const SizedBox(height: 13),
                AuthField(
                  label: '비밀번호 확인',
                  icon: Icons.lock_outline,
                  controller: _passwordConfirm,
                  hint: '다시 입력하세요',
                  password: true,
                  enabled: !_loading,
                  height: 53,
                  textInputAction: TextInputAction.next,
                  validator: _checkPasswordConfirm,
                ),
                const SizedBox(height: 13),
                AuthField(
                  label: '전화번호',
                  icon: Icons.phone_outlined,
                  controller: _phone,
                  hint: '010-1234-5678',
                  enabled: !_loading,
                  height: 53,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9\-]'))],
                  validator: _checkPhone,
                ),
                const SizedBox(height: 13),
                AuthField(
                  label: '차량번호',
                  icon: Icons.local_shipping_outlined,
                  controller: _vehicle,
                  hint: '12가 3456',
                  enabled: !_loading,
                  height: 53,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: _checkVehicle,
                ),
                const SizedBox(height: 6),
                const Text(
                  '졸음 경고가 나면 관리자가 이 연락처로 연락해요.',
                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                ),
                const SizedBox(height: 10),
                _consentRow(),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!, style: const TextStyle(color: AppColors.danger, fontSize: 13, fontWeight: FontWeight.w600)),
                ],
                const SizedBox(height: 14),
                if (_loading)
                  const SizedBox(height: 58, child: Center(child: CircularProgressIndicator()))
                else
                  AuthButton(text: '가입하기', onPressed: _submit),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // 동의 줄 (Figma .check-row — 둥근 네모 체크 · 글 · 오른쪽 화살표 = 내용 보기)
  Widget _consentRow() {
    void toggle() => setState(() {
          _agreed = !_agreed;
          if (_agreed) _agreeError = false;
        });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 50,
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: _loading ? null : toggle,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _agreed ? AppColors.navy : Colors.white,
                          border: Border.all(
                              color: _agreed
                                  ? AppColors.navy
                                  : (_agreeError ? AppColors.danger : AppColors.cardBorder),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: _agreed ? const Icon(Icons.check, size: 17, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text('(필수) 개인정보 수집 및 이용에 동의합니다',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary)),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                onPressed: _showConsent,
                tooltip: '동의 내용 보기',
                icon: const Icon(Icons.chevron_right, size: 22, color: AppColors.textMuted),
              ),
            ],
          ),
        ),
        if (_agreeError)
          const Text('개인정보 수집 · 이용에 동의해야 가입할 수 있어요',
              style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
