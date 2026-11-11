// ═══════════════════════════════════════════════════════════════
// widgets/auth_ui.dart — 로그인 · 회원가입 화면 디자인 부품 (Figma 시안 '졸음운전 감지 앱')
// ═══════════════════════════════════════════════════════════════
// 디자인만 담당 — 검사 규칙 · 서버 호출은 각 화면(login_screen · signup_screen)이 그대로 가진다
//   - AuthField   : 위에 이름표, 왼쪽 아이콘, 둥근 테두리(15), 누르면 남색 테두리, 비밀번호는 눈 아이콘으로 보기 · 숨기기
//   - AuthButton  : 높이 58 · 모서리 17 · 굵은 17 글씨 (primary = 남색, secondary = 흰 바탕 + 테두리)
//   - AuthLogo    : 부엉이 로고 (모서리 22%, 그림자)
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme.dart';

class AuthUi {
  AuthUi._();
  static const Color fieldFill = Color(0xFFFBFCFE);
  static const Color placeholder = Color(0xFFA2A8BA);
  static const Color disabledBg = Color(0xFFE1E4EC);
}

/// 부엉이 로고 (Figma .logo — 모서리 22%, 남색 그림자)
class AuthLogo extends StatelessWidget {
  final double size;
  const AuthLogo({super.key, this.size = 82});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        boxShadow: const [BoxShadow(color: Color(0x261F2A5C), blurRadius: 24, offset: Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.22),
        child: Image.asset('assets/owl/logo.png', fit: BoxFit.cover),
      ),
    );
  }
}

/// 이름표 + 아이콘 입력칸 (Figma .field)
class AuthField extends StatefulWidget {
  final String label;
  final IconData icon;
  final TextEditingController controller;
  final String? hint;
  final bool password;
  final bool enabled;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final double height;
  final String? helper; // 칸 아래 작은 안내 (긴 규칙 문구가 칸 안에서 잘리지 않게)

  const AuthField({
    super.key,
    required this.label,
    required this.icon,
    required this.controller,
    this.hint,
    this.password = false,
    this.enabled = true,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onFieldSubmitted,
    this.height = 56,
    this.helper,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  bool _hidden = true; // 비밀번호 가리기

  OutlineInputBorder _border(Color c, [double w = 1.5]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(15),
        borderSide: BorderSide(color: c, width: w),
      );

  @override
  Widget build(BuildContext context) {
    final vPad = (widget.height - 22) / 2; // 글자 높이 약 22 → 칸 높이를 시안과 맞춤
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        const SizedBox(height: 7),
        TextFormField(
          controller: widget.controller,
          enabled: widget.enabled,
          obscureText: widget.password && _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator,
          onFieldSubmitted: widget.onFieldSubmitted,
          style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(fontSize: 15, color: AuthUi.placeholder),
            helperText: widget.helper,
            helperStyle: const TextStyle(fontSize: 12, color: AppColors.textMuted),
            helperMaxLines: 2,
            filled: true,
            fillColor: AuthUi.fieldFill,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: vPad),
            prefixIcon: Padding(
              padding: const EdgeInsets.only(left: 15, right: 10),
              child: Icon(widget.icon, size: 21, color: AppColors.textMuted),
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: widget.password
                ? IconButton(
                    onPressed: () => setState(() => _hidden = !_hidden),
                    // 아이콘 = 지금 상태 (가려져 있으면 눈에 빗금, 보이면 눈) — 팀장 확인 11/12
                    icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        size: 20, color: AppColors.textMuted),
                    tooltip: _hidden ? '비밀번호 보기' : '비밀번호 숨기기',
                  )
                : null,
            errorStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.danger),
            errorMaxLines: 2,
            border: _border(AppColors.cardBorder),
            enabledBorder: _border(AppColors.cardBorder),
            disabledBorder: _border(AppColors.cardBorder),
            focusedBorder: _border(AppColors.navy),
            errorBorder: _border(AppColors.danger),
            focusedErrorBorder: _border(AppColors.danger),
          ),
        ),
      ],
    );
  }
}

/// 큰 버튼 (Figma .button.primary / .button.secondary)
class AuthButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  final bool primary;
  final Widget? leading;

  const AuthButton({super.key, required this.text, this.onPressed, this.primary = true, this.leading});

  @override
  Widget build(BuildContext context) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(17));
    const textStyle = TextStyle(fontSize: 17, fontWeight: FontWeight.w800);
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 9)],
        Text(text, style: textStyle),
      ],
    );
    if (primary) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(17),
          boxShadow: onPressed == null
              ? null
              : const [BoxShadow(color: Color(0x251F2A5C), blurRadius: 20, offset: Offset(0, 9))],
        ),
        child: ElevatedButton(
          onPressed: onPressed,
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: AppColors.navy,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AuthUi.disabledBg,
            disabledForegroundColor: AuthUi.placeholder,
            elevation: 0,
            shape: shape,
          ),
          child: child,
        ),
      );
    }
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(58),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.cardBorder, width: 1.5),
        shape: shape,
      ),
      child: child,
    );
  }
}
