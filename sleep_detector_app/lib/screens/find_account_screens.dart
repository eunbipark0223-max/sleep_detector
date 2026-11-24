// ═══════════════════════════════════════════════════════════════
// screens/find_account_screens.dart — 이메일 찾기 · 비밀번호 찾기 (11/18 C)
// ═══════════════════════════════════════════════════════════════
//   로그인 화면의 [이메일 찾기 · 비밀번호 찾기] 에서 연다 (애플 스타일: 흰 바탕 · 칸 하나씩 · 아래 큰 버튼)
//   - FindEmailScreen    : 전화번호 인증 → 그 번호로 가입한 이메일(가려서) 보여 줌   POST /users/find-email
//   - ResetPasswordScreen: 가입한 이메일 인증 → 새 비밀번호 · 확인 → [변경하기]     POST /users/password/reset
//                          바꾸면 이메일을 들고 로그인 화면으로 돌아간다 (Navigator.pop(email))
//   인증 칸은 회원가입과 같은 VerifyField (시연용 서버는 인증번호를 칸 아래에 보여 줌)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/phone_format.dart';
import '../widgets/auth_ui.dart';
import '../widgets/verify_field.dart';
import '../design_tokens.dart';

class FindEmailScreen extends StatefulWidget {
  /// [비밀번호 찾기] 를 누르고 닫힐 때 돌려주는 값
  static const String goReset = 'reset';
  const FindEmailScreen({super.key});

  @override
  State<FindEmailScreen> createState() => _FindEmailScreenState();
}

class _FindEmailScreenState extends State<FindEmailScreen> {
  List<Map<String, dynamic>>? _found;
  bool _loading = false;
  String? _error;

  static bool _phoneOk(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 9 && digits.length <= 11;
  }

  Future<void> _find(String phone, String token) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await AuthService.findEmail(phone: phone, phoneToken: token);
      if (mounted) setState(() => _found = list);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '이메일을 찾지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AuthUi.page,
      appBar: AppBar(title: const Text('이메일 찾기'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: _found == null ? _askPhone() : _result(_found!),
        ),
      ),
    );
  }

  List<Widget> _askPhone() => [
        const _Lead('가입할 때 인증한 전화번호를 입력하세요'),
        const SizedBox(height: 20),
        VerifyField(
          label: '전화번호',
          hint: '010-1234-5678',
          formatOk: _phoneOk,
          invalidNote: '전화번호 형식이 올바르지 않아요',
          demoWord: '문자',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneHyphenFormatter()],
          enabled: !_loading,
          send: AuthService.sendPhoneCode,
          verify: AuthService.verifyPhoneCode,
          onVerified: _find,
          onReset: () => setState(() => _error = null),
        ),
        if (_error != null) AuthNote(_error!, error: true),
        if (_loading) ...[
          const SizedBox(height: 24),
          const Center(child: CircularProgressIndicator(color: AppColors.navy)),
        ],
      ];

  List<Widget> _result(List<Map<String, dynamic>> list) => [
        const _Lead('이 전화번호로 가입한 계정이에요'),
        const SizedBox(height: 20),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(color: AppColors.cardBorder),
          ),
          child: Column(children: [
            for (var i = 0; i < list.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, indent: 16, color: AppColors.line),
              _EmailRow(email: '${list[i]['email'] ?? ''}', google: list[i]['provider'] == 'google'),
            ],
          ]),
        ),
        const SizedBox(height: 28),
        AuthButton(text: '로그인하기', onPressed: () => Navigator.of(context).pop()),
        const SizedBox(height: 12),
        AuthButton(
          text: '비밀번호 찾기',
          primary: false,
          // 로그인 화면으로 돌아가 거기서 비밀번호 찾기를 연다 (바꾼 이메일을 로그인 칸에 채우려고)
          onPressed: () => Navigator.of(context).pop(FindEmailScreen.goReset),
        ),
      ];
}

class _EmailRow extends StatelessWidget {
  final String email;
  final bool google;
  const _EmailRow({required this.email, required this.google});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(children: [
        Expanded(
          child: Text(email,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(color: AppColors.fill, borderRadius: BorderRadius.circular(999)),
          child: Text(google ? '구글' : '이메일',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
      ]),
    );
  }
}

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  static final RegExp _emailRule = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  static final RegExp _special = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
  final _next = TextEditingController();
  final _again = TextEditingController();
  String? _email;
  String? _token;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _next.dispose();
    _again.dispose();
    super.dispose();
  }

  // 회원가입과 같은 규칙 (서버 check_password_rules)
  static bool _rulesOk(String p) =>
      p.length >= 8 &&
      RegExp(r'[A-Z]').hasMatch(p) &&
      RegExp(r'[a-z]').hasMatch(p) &&
      RegExp(r'[0-9]').hasMatch(p) &&
      _special.hasMatch(p);

  bool get _ready => _token != null && _rulesOk(_next.text) && _again.text == _next.text;

  Future<void> _save() async {
    if (!_ready || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.resetPassword(email: _email!, emailToken: _token!, newPassword: _next.text);
      if (mounted) Navigator.of(context).pop(_email);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '변경하지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    void refresh(String _) => setState(() {});
    final verified = _token != null;
    return Scaffold(
      backgroundColor: AuthUi.page,
      appBar: AppBar(title: const Text('비밀번호 찾기'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
          children: [
            _Lead(verified ? '새 비밀번호를 입력하세요' : '가입한 이메일로 인증번호를 받아 주세요'),
            const SizedBox(height: 20),
            VerifyField(
              label: '이메일',
              hint: '이메일을 입력하세요',
              formatOk: (s) => _emailRule.hasMatch(s),
              invalidNote: '이메일 형식이 올바르지 않아요',
              demoWord: '메일',
              keyboardType: TextInputType.emailAddress,
              enabled: !_saving,
              send: AuthService.sendEmailCode,
              verify: AuthService.verifyEmailCode,
              onVerified: (email, token) => setState(() {
                _email = email;
                _token = token;
              }),
              onReset: () => setState(() {
                _email = null;
                _token = null;
              }),
            ),
            // 인증이 끝나면 새 비밀번호 칸이 아래로 나타남
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: !verified
                  ? const SizedBox(width: double.infinity)
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      const SizedBox(height: 13),
                      AuthField(
                        label: '새 비밀번호',
                        controller: _next,
                        hint: '새 비밀번호',
                        password: true,
                        enabled: !_saving,
                        textInputAction: TextInputAction.next,
                        onChanged: refresh,
                        valid: _next.text.isEmpty ? null : _rulesOk(_next.text),
                        invalidNote: '대문자, 숫자, 특수문자를 포함하여 8자 이상 입력해 주세요',
                      ),
                      const SizedBox(height: 13),
                      AuthField(
                        label: '새 비밀번호 확인',
                        controller: _again,
                        hint: '한 번 더 입력하세요',
                        password: true,
                        enabled: !_saving,
                        textInputAction: TextInputAction.done,
                        onChanged: refresh,
                        onFieldSubmitted: (_) => _save(),
                        valid: _again.text.isEmpty ? null : _again.text == _next.text,
                        invalidNote: '비밀번호가 일치하지 않아요',
                      ),
                      if (_error != null) AuthNote(_error!, error: true),
                      const SizedBox(height: 24),
                      if (_saving)
                        const SizedBox(
                            height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
                      else
                        AuthButton(text: '변경하기', onPressed: _ready ? _save : null),
                    ]),
            ),
          ],
        ),
      ),
    );
  }
}

/// 화면 위 한 줄 안내 (크게 · 굵게, 애플 설정의 큰 설명처럼)
class _Lead extends StatelessWidget {
  final String text;
  const _Lead(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: AuthUi.noteIndent),
        child: Text(text,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600, height: 1.4, color: AppColors.textPrimary)),
      );
}
