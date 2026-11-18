// ═══════════════════════════════════════════════════════════════
// screens/account_edit_screens.dart — 내 정보 한 칸 바꾸기 · 비밀번호 변경 (11/18 C)
// ═══════════════════════════════════════════════════════════════
//   - EditFieldScreen : 이름 · 전화번호 · 차량번호 한 칸을 바꾸는 화면 (애플 설정 → 이름 바꾸기처럼)
//                       위 제목 · 칸 하나 · 맞으면 체크/틀리면 X · 아래 [저장]. 저장하면 바뀐 내 정보를 돌려준다
//   - PasswordScreen  : 지금 비밀번호 · 새 비밀번호 · 새 비밀번호 확인 → [변경하기] (PUT /users/me/password)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../widgets/auth_ui.dart';

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

  @override
  Widget build(BuildContext context) {
    final text = _c.text.trim();
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          children: [
            AuthField(
              label: widget.label,
              controller: _c,
              hint: widget.hint,
              enabled: !_saving,
              keyboardType: widget.keyboardType,
              inputFormatters: widget.inputFormatters,
              textInputAction: TextInputAction.done,
              onFieldSubmitted: (_) => _save(),
              onChanged: (_) => setState(() {}),
              valid: text.isEmpty ? null : _ok,
              invalidNote: widget.invalidNote,
              helper: widget.note,
            ),
            if (_error != null) AuthNote(_error!, error: true),
            const SizedBox(height: 24),
            if (_saving)
              const SizedBox(height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
            else
              AuthButton(text: '저장', onPressed: _ok && _changed ? _save : null),
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
      backgroundColor: AppColors.card,
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
