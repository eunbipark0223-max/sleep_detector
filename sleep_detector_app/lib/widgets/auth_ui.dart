// ═══════════════════════════════════════════════════════════════
// widgets/auth_ui.dart — 로그인 · 회원가입 화면 디자인 부품 (Figma 시안 '졸음운전 감지 앱')
// ═══════════════════════════════════════════════════════════════
// 디자인만 담당 — 검사 규칙 · 서버 호출은 각 화면(login_screen · signup_screen)이 그대로 가진다
//   - AuthField   : 위에 이름표, 왼쪽 아이콘, 둥근 테두리(15), 누르면 남색 테두리, 비밀번호는 눈 아이콘으로 보기 · 숨기기
//   - AuthButton  : 높이 58 · 모서리 17 · 굵은 17 글씨 (primary = 남색, secondary = 흰 바탕 + 테두리)
//   - AuthLogo    : 부엉이 로고 (모서리 22%, 그림자)
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import '../design_tokens.dart';
import 'press.dart';
import 'package:flutter/services.dart';

import '../theme.dart';
import 'web_ui.dart';

// (11/17 저녁 · 관리자 웹 로그인과 같게) 화면 전체 흰색 + 연회색 입력칸(아이콘 없음) + 남색 알약 버튼
class AuthUi {
  AuthUi._();
  static const Color page = AppColors.background; // 화면 바탕 — 전체 흰색 (사용자 요청 11/17)
  static const Color fieldFill = AppColors.card; // (11/19) 크림 바탕 위 흰 입력칸
  static const Color placeholder = AppColors.textMuted;
  static const Color disabledBg = AppColors.fill;
  static const Color label = AppColors.textPrimary;
  static const Color hint = AppColors.textMuted;
  static const Color error = AppColors.urgent;
  static const double controlHeight = 53; // 입력칸 · 큰 버튼 공통 높이
  static const double noteIndent = 6; // 칸 아래 설명 글이 칸보다 안쪽으로 들어가는 정도 (아주 살짝)
  static const Color appleBlue = Color(0xFF007AFF); // 애플 시스템 파랑 (iOS 기본 버튼 색)
  static const Color readOnlyFill = AppleGray.fill; // 바꿀 수 없는 칸 바탕 (입력칸보다 살짝 진한 회색)
}

/// 칸 안 작은 버튼 — 남색 알약 + 흰 글자 (큰 버튼과 같은 남색으로 통일, 그림자는 아주 옅게)
///   예: [인증번호 받기] · [재전송] · [확인]
class AuthTinyButton extends StatelessWidget {
  final String text;
  final VoidCallback? onPressed;
  const AuthTinyButton({super.key, required this.text, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    return Press(enabled: on, scale: 0.92, child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: on ? const [BoxShadow(color: Color(0x0D1F2A5C), blurRadius: 2, offset: Offset(0, 1))] : null,
      ),
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white,
          backgroundColor: AppColors.navy,
          disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
          disabledBackgroundColor: AppColors.navy.withValues(alpha: 0.35),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: -0.2),
        ),
        child: Text(text),
      ),
    ));
  }
}

/// 위쪽 [로그인 | 회원가입] 알약 전환 (readdy) — 지금 화면 쪽이 흰색
class AuthTabs extends StatelessWidget {
  final bool signup;
  final VoidCallback? onLogin;
  final VoidCallback? onSignup;
  const AuthTabs({super.key, required this.signup, this.onLogin, this.onSignup});

  @override
  Widget build(BuildContext context) {
    Widget tab(String t, bool on, VoidCallback? tap) => Expanded(
          child: GestureDetector(
            onTap: on ? null : tap,
            child: Container(
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.card : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: on ? const [BoxShadow(color: Color(0x141F2A5C), blurRadius: 6, offset: Offset(0, 1))] : null),
              child: Text(t,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: on ? AppColors.textPrimary : AppColors.textSecondary)),
            ),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.field, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [tab('로그인', !signup, onLogin), tab('회원가입', signup, onSignup)]),
    );
  }
}

/// 부엉이 로고 (Figma .logo — 모서리 22%, 남색 그림자)
class AuthLogo extends StatelessWidget {
  final double size;
  const AuthLogo({super.key, this.size = 82});

  @override
  Widget build(BuildContext context) {
    // (11/17) 로고 그림은 아직 안 넣음 — 자리만 표시
    return ImageSlot.logo(size: size);
  }
}

/// 칸 아래 작은 설명 · 오류 글 — 입력칸보다 아주 살짝(6) 안쪽에서 시작 (11/17 사용자 요청, 모든 칸 같게)
class AuthNote extends StatelessWidget {
  final String text;
  final bool error;
  final Color? color;
  const AuthNote(this.text, {super.key, this.error = false, this.color});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: AuthUi.noteIndent, top: 6),
        child: Text(text,
            style: TextStyle(
              fontSize: 12,
              height: 1.4,
              fontWeight: error ? FontWeight.w600 : FontWeight.w400,
              color: color ?? (error ? AuthUi.error : AuthUi.hint),
            )),
      );
}

/// 이름표 + 입력칸 (11/17 아이콘 없음 — icon 은 비워 둠)
///   - valid: true = 받으려는 값 모양이 맞음 → 칸 오른쪽 끝 초록 체크
///            false = 틀림 → 빨간 X + 칸 아래 invalidNote (왜 틀렸는지)
///            null = 아직 아무것도 안 침 → 표시 없음
///   - readOnly: 바꿀 수 없는 칸 (사번) — 흐린 글자 · 조금 더 진한 회색 바탕
///   - 오류 · 안내 글은 칸 아래 AuthNote 로 (모든 칸 같은 들여쓰기)
class AuthField extends StatefulWidget {
  final String label;
  final IconData? icon; // (11/17) 안 씀 — 넣어도 화면에는 안 보임
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final Widget? suffix; // 칸 오른쪽 안 버튼 (예: [인증번호 받기])
  final String? hint;
  final bool password;
  final bool enabled;
  final bool readOnly;
  final bool? valid;
  final String? invalidNote; // valid == false 일 때 칸 아래 안내
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final List<TextInputFormatter>? inputFormatters;
  final FormFieldValidator<String>? validator;
  final ValueChanged<String>? onFieldSubmitted;
  final double height;
  final String? helper; // 칸 아래 작은 안내

  const AuthField({
    super.key,
    required this.label,
    this.icon,
    required this.controller,
    this.onChanged,
    this.suffix,
    this.hint,
    this.password = false,
    this.enabled = true,
    this.readOnly = false,
    this.valid,
    this.invalidNote,
    this.keyboardType,
    this.textInputAction,
    this.inputFormatters,
    this.validator,
    this.onFieldSubmitted,
    this.height = AuthUi.controlHeight, // (11/17) 로그인 · 사번 · 회원가입 칸 모두 같은 높이
    this.helper,
  });

  @override
  State<AuthField> createState() => _AuthFieldState();
}

class _AuthFieldState extends State<AuthField> {
  final _fieldKey = GlobalKey<FormFieldState<String>>();
  bool _hidden = true; // 비밀번호 가리기
  String? _err; // [가입하기] 때 검사에 걸린 문구 (칸 아래 AuthNote 로 보여 줌)

  OutlineInputBorder _border(Color c, [double w = 1.5]) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: c == Colors.transparent ? BorderSide.none : BorderSide(color: c, width: w),
      );

  // 검사 결과를 받아 두었다가 칸 아래에 직접 그린다 (Flutter 기본 오류 글은 칸 안쪽 18 만큼 들어가서 안 씀)
  String? _validate(String? v) {
    final msg = widget.validator?.call(v);
    if (msg != _err) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _err = msg);
      });
    }
    return msg == null ? null : '';
  }

  // 한 번 오류가 난 칸은 고칠 때마다 다시 검사 (고치면 빨간 테두리 · 문구가 바로 사라지게)
  void _changed(String v) {
    if (_err != null) _fieldKey.currentState?.validate();
    widget.onChanged?.call(v);
  }

  @override
  Widget build(BuildContext context) {
    final vPad = (widget.height - 22) / 2; // 글자 높이 약 22 → 칸 높이를 시안과 맞춤
    final right = <Widget>[
      if (widget.suffix != null) widget.suffix!,
      if (widget.valid == true)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.check_circle, size: 20, color: AppColors.normal),
        ),
      if (widget.valid == false)
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 6),
          child: Icon(Icons.cancel, size: 20, color: AuthUi.error),
        ),
      if (widget.password)
        IconButton(
          onPressed: () => setState(() => _hidden = !_hidden),
          // 아이콘 = 지금 상태 (가려져 있으면 눈에 빗금, 보이면 눈) — 팀장 확인 11/12
          icon: Icon(_hidden ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AuthUi.hint),
          tooltip: _hidden ? '비밀번호 보기' : '비밀번호 숨기기',
        ),
    ];
    final note = (_err != null && _err!.isNotEmpty)
        ? AuthNote(_err!, error: true)
        : (widget.valid == false && widget.invalidNote != null)
            ? AuthNote(widget.invalidNote!, error: true)
            : (widget.helper != null ? AuthNote(widget.helper!) : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AuthUi.label)),
        const SizedBox(height: 7),
        TextFormField(
          key: _fieldKey,
          controller: widget.controller,
          enabled: widget.enabled,
          readOnly: widget.readOnly,
          obscureText: widget.password && _hidden,
          keyboardType: widget.keyboardType,
          textInputAction: widget.textInputAction,
          inputFormatters: widget.inputFormatters,
          validator: widget.validator == null ? null : _validate,
          onFieldSubmitted: widget.onFieldSubmitted,
          onChanged: _changed,
          cursorColor: AppColors.navy,
          // 바꿀 수 없는 칸은 흐린 글자 (비활성처럼)
          style: TextStyle(fontSize: 15, color: widget.readOnly ? AppColors.textMuted : AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: widget.hint,
            hintStyle: const TextStyle(fontSize: 15, color: AuthUi.placeholder),
            filled: true,
            // (11/17) 바탕은 다른 칸과 똑같이 (진한 회색이면 칸이 더 커 보임) — 바꿀 수 없는 칸은 흐린 글자로만 표시
            fillColor: AuthUi.fieldFill,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 18, vertical: vPad),
            suffixIcon: right.isEmpty
                ? null
                : Padding(
                    padding: const EdgeInsets.only(right: 10), // 오른쪽 끝에 붙지 않게
                    child: Row(mainAxisSize: MainAxisSize.min, children: right),
                  ),
            // 기본 오류 글은 숨기고(빨간 테두리만) 아래 AuthNote 로 보여 줌
            errorStyle: const TextStyle(fontSize: 0, height: 0),
            border: _border(Colors.transparent),
            enabledBorder: _border(AppColors.cardBorder), // (11/19) 크림 위 흰 칸 — 옅은 테두리
            disabledBorder: _border(Colors.transparent),
            focusedBorder: _border(widget.readOnly ? Colors.transparent : AppColors.navy, 1.2),
            errorBorder: _border(AuthUi.error),
            focusedErrorBorder: _border(AuthUi.error),
          ),
        ),
        ?note,
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
  final double? contentWidth; // (11/18) 주면 아이콘 + 글자를 이 폭 안에서 왼쪽부터 — 위아래 버튼 글자 시작점 맞춤
  final double height; // (11/18) 홈 운행 버튼은 조금 낮게 (48)

  const AuthButton(
      {super.key, required this.text, this.onPressed, this.primary = true, this.leading, this.contentWidth, this.height = AuthUi.controlHeight});

  @override
  Widget build(BuildContext context) {
    // (11/17 관리자 웹) 남색 알약 (primary) · 흰 알약 + 회색 테두리 (secondary)
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(999));
    // (11/17 사용자 요청) [Google로 계속하기] 글씨 굵기를 [로그인] 과 같게 보이게 — 흰 바탕 검은 글씨는 같은 굵기여도 더 굵어 보여서 한 단계 가볍게
    final textStyle = TextStyle(fontSize: 16, fontWeight: primary ? FontWeight.w600 : FontWeight.w500);
    final Widget row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 9)],
        Text(text, style: textStyle),
      ],
    );
    final Widget child = contentWidth == null ? row : SizedBox(width: contentWidth, child: Align(alignment: Alignment.centerLeft, child: row));
    // (11/19 디자인 시스템) 남색 큰 버튼은 Headspace 처럼 아래로만 2px 납작한 그림자 — 살짝 떠 있는 느낌
    return Press(enabled: onPressed != null, child: DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        boxShadow: primary && onPressed != null ? AppShadow.button : null,
      ),
      child: ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        minimumSize: Size.fromHeight(height), // 기본은 입력칸과 같은 높이 — 로그인 · 가입하기 · 사번 확인 · 구글 모두 같게
        backgroundColor: primary ? AppColors.navy : AppColors.card,
        foregroundColor: primary ? Colors.white : AppColors.textPrimary,
        side: primary ? null : const BorderSide(color: AppColors.fill),
        disabledBackgroundColor: AuthUi.disabledBg,
        disabledForegroundColor: AuthUi.placeholder,
        elevation: 0,
        shape: shape,
      ),
      child: child,
    )));
  }
}
