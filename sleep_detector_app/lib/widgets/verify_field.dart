// ═══════════════════════════════════════════════════════════════
// widgets/verify_field.dart — 인증 칸 하나 (11/18 C)
// ═══════════════════════════════════════════════════════════════
//   [값 칸 + 인증번호 받기 / 재전송] → [인증번호 칸 + 확인] → 체크
//   회원가입 화면의 인증 칸과 같은 모양 · 같은 규칙 (이메일 찾기 · 비밀번호 찾기 · 이메일 변경에서 씀)
//   - [인증번호 받기] 는 모양이 맞을 때만 (canSend 가 false 면 숨김)
//   - 값을 고치거나 지우면 처음 상태로 돌아가고 onReset 을 부른다
//   - 시연용 서버는 메일 · 문자 대신 인증번호를 돌려줘서 칸 아래에 보여 준다
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'auth_ui.dart';

class VerifyField extends StatefulWidget {
  final String label;
  final String hint;
  final bool Function(String) formatOk;
  final String invalidNote;
  final String demoWord; // '메일' · '문자'
  final Future<String?> Function(String value) send; // 돌려주는 값 = 시연용 인증번호 (없으면 null)
  final Future<String> Function(String value, String code) verify; // 돌려주는 값 = 인증 표
  final void Function(String value, String token) onVerified;
  final VoidCallback? onReset;
  final bool canSend; // 다른 칸이 먼저 채워져야 할 때 false
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextEditingController? controller;

  const VerifyField({
    super.key,
    required this.label,
    required this.hint,
    required this.formatOk,
    required this.invalidNote,
    required this.demoWord,
    required this.send,
    required this.verify,
    required this.onVerified,
    this.onReset,
    this.canSend = true,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.controller,
  });

  @override
  State<VerifyField> createState() => _VerifyFieldState();
}

class _VerifyFieldState extends State<VerifyField> {
  late final TextEditingController _value = widget.controller ?? TextEditingController();
  final _code = TextEditingController();
  bool _sent = false;
  String? _sentTo;
  String? _demo;
  String? _verifiedValue;
  String? _msg;
  bool _busy = false;

  @override
  void dispose() {
    if (widget.controller == null) _value.dispose();
    _code.dispose();
    super.dispose();
  }

  void _onChanged(String s) {
    final now = s.trim();
    final wasVerified = _verifiedValue != null && now != _verifiedValue;
    setState(() {
      if ((_sent && now != _sentTo) || wasVerified) {
        _sent = false;
        _sentTo = null;
        _demo = null;
        _verifiedValue = null;
        _code.clear();
      }
      _msg = null;
    });
    if (wasVerified) widget.onReset?.call();
  }

  Future<void> _send(String value) async {
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final demo = await widget.send(value);
      if (!mounted) return;
      setState(() {
        _sent = true;
        _sentTo = value;
        _demo = demo;
        _code.clear();
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = e.message);
    } catch (_) {
      if (mounted) setState(() => _msg = '인증번호를 보내지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _check(String value) async {
    if (_code.text.trim().length < 4) {
      setState(() => _msg = '인증번호를 입력하세요');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      final token = await widget.verify(value, _code.text.trim());
      if (!mounted) return;
      setState(() {
        _verifiedValue = value;
        _sent = false;
        _demo = null;
      });
      widget.onVerified(value, token);
    } on AuthException catch (e) {
      if (mounted) setState(() => _msg = e.message);
    } catch (_) {
      if (mounted) setState(() => _msg = '인증하지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final value = _value.text.trim();
    final verified = _verifiedValue != null && value == _verifiedValue;
    final ok = widget.formatOk(value);
    final bool? valid = verified ? true : (value.isNotEmpty && !ok ? false : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: widget.label,
          controller: _value,
          hint: widget.hint,
          enabled: widget.enabled,
          keyboardType: widget.keyboardType,
          inputFormatters: widget.inputFormatters,
          textInputAction: TextInputAction.done,
          onChanged: _onChanged,
          valid: valid,
          invalidNote: widget.invalidNote,
          suffix: verified || !ok || !widget.canSend
              ? null
              : AuthTinyButton(text: _sent ? '재전송' : '인증번호 받기', onPressed: _busy ? null : () => _send(value)),
        ),
        if (_sent && !verified) ...[
          const SizedBox(height: 10),
          AuthField(
            label: '인증번호',
            controller: _code,
            hint: '6자리 숫자',
            enabled: widget.enabled,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onFieldSubmitted: (_) => _check(value),
            suffix: AuthTinyButton(text: '확인', onPressed: _busy ? null : () => _check(value)),
          ),
          if (_demo != null)
            AuthNote('인증번호: $_demo  (${widget.demoWord} 대신 보여 드려요)', color: AppColors.textSecondary),
        ],
        if (_msg != null) AuthNote(_msg!, error: true),
      ],
    );
  }
}
