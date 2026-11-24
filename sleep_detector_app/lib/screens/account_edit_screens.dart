// ═══════════════════════════════════════════════════════════════
// screens/account_edit_screens.dart — 내 정보 한 칸 바꾸기 · 비밀번호 변경 (11/18 C)
// ═══════════════════════════════════════════════════════════════
//   - EditFieldScreen : 이름 · 전화번호 · 차량번호 한 칸을 바꾸는 화면 (애플 설정 → 이름 바꾸기처럼)
//                       위 제목 · 칸 하나 · 맞으면 체크/틀리면 X · 아래 [저장]. 저장하면 바뀐 내 정보를 돌려준다
//   - EmailChangeScreen : 비밀번호 + 새 이메일 인증 → 바로 바뀜 (POST /users/me/email/request · confirm)
//   - PasswordScreen  : 지금 비밀번호 · 새 비밀번호 · 새 비밀번호 확인 → [변경하기] (PUT /users/me/password)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';
import '../widgets/verify_field.dart';
import '../design_tokens.dart';

class EditFieldScreen extends StatefulWidget {
  final String title; // '이름 변경'
  final String label; // '이름'
  final String initial;
  final String hint;
  final bool Function(String) isValid;
  final String invalidNote;
  final String? note; // 칸 아래 안내 (예: '졸음 경고 시 관리자 연락에만 사용돼요')
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final Future<Map<String, dynamic>> Function(String value) save;

  const EditFieldScreen({
    super.key,
    required this.title,
    required this.label,
    required this.initial,
    required this.hint,
    required this.isValid,
    required this.invalidNote,
    required this.save,
    this.note,
    this.keyboardType,
    this.inputFormatters,
  });

  @override
  State<EditFieldScreen> createState() => _EditFieldScreenState();
}

class _EditFieldScreenState extends State<EditFieldScreen> {
  late final _c = TextEditingController(text: widget.initial);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  bool get _ok => widget.isValid(_c.text.trim());
  bool get _changed => _c.text.trim() != widget.initial.trim();

  void _onChangePressed() {
    if (_saving) return;
    if (!_changed) {
      setState(() => _error = '바뀐 내용이 없어요\n새로 입력해 주세요');
      return;
    }
    if (!_ok) {
      setState(() => _error = widget.invalidNote);
      return;
    }
    _save();
  }

  Future<void> _save() async {
    if (!_ok || !_changed || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = await widget.save(_c.text.trim());
      if (mounted) Navigator.of(context).pop(user);
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '저장하지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // (11/18 사용자 요청 · 아이폰 설정 > 이름 바꾸기처럼)
  //   위 가운데 '이름 변경' · 오른쪽 위 [완료] (바뀌고 맞을 때만 남색) · 둥근 칸 하나 안에 입력 + 지우기(ⓧ)
  //   칸 위 작은 회색 이름 · 칸 아래 작은 안내 / 틀리면 빨간 안내
  @override
  Widget build(BuildContext context) {
    final text = _c.text.trim();
    final bad = text.isNotEmpty && !_ok;
    return Scaffold(
      backgroundColor: AppColors.background,
      // (11/18 피드백) 위 제목은 그냥 '이름' · 바꾸기는 칸 아래 '이름 변경' 글자 (로그인 화면 '이메일 찾기 · 비밀번호 찾기' 와 같은 모양)
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 8),
              child: Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
            ),
            Container(
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: bad ? AuthUi.error : AppColors.cardBorder, width: bad ? 1.4 : 1),
              ),
              padding: const EdgeInsets.only(left: 16, right: 4),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    autofocus: true,
                    enabled: !_saving,
                    keyboardType: widget.keyboardType,
                    inputFormatters: widget.inputFormatters,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                    onChanged: (_) => setState(() => _error = null),
                    style: const TextStyle(fontSize: 17, color: AppColors.textPrimary),
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(color: AppColors.textMuted),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
                if (_c.text.isNotEmpty && !_saving)
                  IconButton(
                    onPressed: () => setState(() {
                      _c.clear();
                      _error = null;
                    }),
                    tooltip: '지우기',
                    icon: const Icon(Icons.cancel_rounded, size: 20, color: Color(0xFFC4C7CE)),
                  ),
              ]),
            ),
            if (bad)
              AuthNote(widget.invalidNote, error: true)
            else if (_error != null)
              AuthNote(_error!, error: true)
            else if (widget.note != null)
              AuthNote(widget.note!, color: AppColors.textMuted),
            const SizedBox(height: 14),
            // 늘 눌림 — 안 바뀌었거나 틀리면 칸 아래에 알려 줌
            Center(
              child: _saving
                  ? const Padding(
                      padding: EdgeInsets.all(10),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.navy)))
                  : TextButton(
                      onPressed: _onChangePressed,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      child: Text('${widget.label} 변경'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class PasswordScreen extends StatefulWidget {
  const PasswordScreen({super.key});

  @override
  State<PasswordScreen> createState() => _PasswordScreenState();
}

class _PasswordScreenState extends State<PasswordScreen> {
  static final RegExp _special = RegExp(r'[!@#$%^&*(),.?":{}|<>]');
  final _now = TextEditingController();
  final _next = TextEditingController();
  final _again = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _now.dispose();
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

  bool get _ready => _now.text.isNotEmpty && _rulesOk(_next.text) && _again.text == _next.text;

  Future<void> _save() async {
    if (!_ready || _saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await AuthService.changePassword(current: _now.text, next: _next.text);
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('비밀번호 변경'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            AuthField(
              label: '지금 비밀번호',
              controller: _now,
              hint: '지금 쓰는 비밀번호',
              password: true,
              enabled: !_saving,
              textInputAction: TextInputAction.next,
              onChanged: refresh,
            ),
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
              const SizedBox(height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
            else
              AuthButton(text: '변경하기', onPressed: _ready ? _save : null),
          ],
        ),
      ),
    );
  }
}

/// (11/18 C) 이메일 변경 — 지금 비밀번호 → 새 이메일 [인증번호 받기] → 인증번호 [확인] 하면 바로 바뀜
///   서버: POST /users/me/email/request {new_email, current_password} · /users/me/email/confirm {new_email, code}
///   바뀌면 바뀐 내 정보(Map)를 돌려주고 닫힌다. 구글 계정은 내 정보 화면에서 이 줄을 숨긴다
class EmailChangeScreen extends StatefulWidget {
  final String current; // 지금 이메일 (위에 흐리게 보여 줌)
  const EmailChangeScreen({super.key, required this.current});

  @override
  State<EmailChangeScreen> createState() => _EmailChangeScreenState();
}

class _EmailChangeScreenState extends State<EmailChangeScreen> {
  static final RegExp _emailRule = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
  late final _now = TextEditingController(text: widget.current);
  final _password = TextEditingController();
  Map<String, dynamic>? _changed;

  @override
  void dispose() {
    _now.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('이메일'), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            AuthField(label: '지금 이메일', controller: _now, readOnly: true),
            const SizedBox(height: 13),
            AuthField(
              label: '비밀번호',
              controller: _password,
              hint: '지금 쓰는 비밀번호',
              password: true,
              textInputAction: TextInputAction.next,
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 13),
            VerifyField(
              label: '새 이메일',
              hint: '새 이메일을 입력하세요',
              formatOk: (s) => _emailRule.hasMatch(s) && s != widget.current,
              invalidNote: '이메일 형식이 올바르지 않아요',
              demoWord: '메일',
              keyboardType: TextInputType.emailAddress,
              canSend: _password.text.isNotEmpty,
              send: (v) => AuthService.requestEmailChange(newEmail: v, currentPassword: _password.text),
              verify: (v, code) async {
                _changed = await AuthService.confirmEmailChange(newEmail: v, code: code);
                return 'ok';
              },
              onVerified: (_, _) => Navigator.of(context).pop(_changed),
            ),
            const AuthNote('비밀번호를 입력하면 새 이메일로 인증번호를 받을 수 있어요', color: AppColors.textMuted),
          ],
        ),
      ),
    );
  }
}
