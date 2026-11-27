// ═══════════════════════════════════════════════════════════════
// screens/signup_screen.dart — 회원가입 (사번 확인 → 정보 입력 · 전화번호 인증 → 개인정보 동의)
// ═══════════════════════════════════════════════════════════════
// 담당: D → C (11/17 사번 · 전화 인증)   |   우선: P0
//
// [이 파일이 하는 일]
//   1단계 사번 확인 : 회사 명단에 있는 사번만 다음으로 (POST /users/employee/check)
//   2단계 정보 입력 : 이름 · 이메일 · 비밀번호(규칙 체크 표시) · 비밀번호 확인 · 전화번호 인증 · 차량번호 · 동의
//     - 전화번호: [인증번호 받기] → 6자리 입력 → [확인] (POST /users/phone/send · /users/phone/verify)
//       시연용 서버는 문자를 보내지 않고 인증번호를 화면 아래에 보여 준다
//     - 인증한 뒤 전화번호를 고치면 다시 인증
//   가입에 성공하면 이메일을 들고 로그인 화면으로 돌아간다 (Navigator.pop(email))
//
// [서버 약속] POST /users/signup {email, password, name, phone, vehicle_no, privacy_agreed, emp_no, phone_token}
//   - 이 화면의 검사는 빨리 알려 주려는 것이고, 최종 검사는 서버가 한다 (서버가 틀리다고 하면 그 문구를 그대로 보여 줌)
//
// [모양] (11/17 사용자 요청) 화면 전체 흰색 · 입력칸 아이콘 없음 · 인사 문구 없음
// [동의 문구] 아래 _consentText — 11/16 에 얼굴 사진 · 위치 · Gemini 전송 · 30일 보관을 넣음 · (11/18 팀장) 가입 항목에 사번 추가
//   (11/26) Gemini 에는 사진을 보내지 않고 판정 숫자만 보내도록 서버를 바꿔 '외부 AI 전송' 줄을 고침
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/phone_format.dart';
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

  /// 비밀번호 규칙 (화면 체크 표시용) — 서버 check_password_rules 와 같은 5가지
  static final List<(String, bool Function(String))> _pwRules = [
    ('8자 이상', (p) => p.length >= 8),
    ('대문자', (p) => RegExp(r'[A-Z]').hasMatch(p)),
    ('소문자', (p) => RegExp(r'[a-z]').hasMatch(p)),
    ('숫자', (p) => RegExp(r'[0-9]').hasMatch(p)),
    ('특수문자', (p) => _specialRule.hasMatch(p)),
  ];

  // (11/16 D) 얼굴 사진 · 위치 · 외부 AI(Gemini) 전송 · 사진 30일 보관을 빼먹고 있던 것을 채움 — 실제 서버 동작 기준:
  //   · 눈 기준 측정 · 졸음 의심 · 반쯤 감은 눈 확인 사진은 서버가 판정한 뒤 바로 삭제 (졸음 확정 사진만 uploads/events 에 남김)
  //   · 졸음 확정 사진은 services/photo_cleanup.py 가 30일 뒤 삭제 (PHOTO_KEEP_DAYS)
  //   · 규칙 1단계(첫 졸음)는 AI 를 안 부르고, 2단계부터 llm_service 가 졸음 판정 숫자만 Gemini 로 보냄 (11/26 — 얼굴 사진은 AI 에 안 보냄)
  //   · 사진 열람은 본인 · 관리자만 (GET /events/{id}/photo)
  static const String _consentText =
      '졸음 가드는 회원가입과 졸음 경고 대응을 위해 아래 정보를 수집 · 이용해요\n\n'
      '• 수집 항목\n'
      '  - 가입할 때: 사번, 이름, 이메일, 비밀번호(암호화해서 저장), 전화번호, 차량번호\n'
      '  - 출발 전 눈 기준 측정과 운행 중 눈 상태를 확인할 때: 얼굴 사진 (졸음이 아니라고 확인되면 바로 삭제해요)\n'
      '  - 졸음이 확인됐을 때: 그 순간의 얼굴 사진, 위치(위도 · 경도), 졸음 기록(단계 · 요약 · 음성 퀴즈에 답한 글자) · 음성은 녹음하지 않아요\n'
      '• 이용 목적: 로그인 등 계정 관리, 졸음 경고 대응, 경고가 났을 때 관리자가 기사님께 연락\n'
      '• 외부 AI 전송: 2단계 이상 졸음이 확인되면 졸음 판정 숫자(눈 감은 시간 · 졸음 횟수 등)만 구글 Gemini(AI)에 보내 상황 요약을 만들어요. 얼굴 사진은 AI에 보내지 않아요\n'
      '• 열람: 졸음 사진과 기록은 기사님 본인과 관리자만 볼 수 있어요\n'
      '• 보관 기간: 졸음 사진은 30일 뒤 자동으로 삭제해요 · 계정과 경고 기록은 서비스를 이용하는 동안 보관해요\n\n'
      '동의하지 않으면 회원가입을 할 수 없어요';

  final _formKey = GlobalKey<FormState>();
  final _empNoInput = TextEditingController();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordConfirm = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();

  // 1단계 — 확인된 사번 (null 이면 아직 사번 확인 화면)
  String? _empNo;
  String? _empError;

  // 이메일 · 전화번호 인증 상태 (시연용 서버는 메일 · 문자 대신 인증번호를 화면에 보여 줌)
  final _emailV = _Verify();
  final _phoneV = _Verify();

  bool _agreed = false;
  bool _agreeError = false; // 동의 안 하고 눌렀을 때 체크박스 아래에 안내
  bool _loading = false;
  String? _error; // 서버가 돌려준 오류 문구

  @override
  void dispose() {
    for (final c in [_empNoInput, _name, _email, _password, _passwordConfirm, _phone, _vehicle, _emailV.code, _phoneV.code]) {
      c.dispose();
    }
    super.dispose();
  }

  // 칸에 글을 칠 때마다 오른쪽 체크 · X 를 다시 그린다
  void _refresh(String _) => setState(() {});

  /// 칸 오른쪽 표시: 아무것도 안 쳤으면 null(표시 없음) · 맞으면 true(체크) · 틀리면 false(X)
  static bool? _tri(String text, bool ok) => text.trim().isEmpty ? null : ok;

  /// 비밀번호가 틀렸을 때만 칸 아래에 보여 주는 규칙
  static const String _pwRuleText = '대문자, 숫자, 특수문자를 포함하여 8자 이상 입력해 주세요';

  // 이름 = 글자(한글 · 영문)와 띄어쓰기만, 숫자 · 기호 없음
  static final RegExp _nameRule = RegExp(r'^[가-힣a-zA-Z ]+$');
  bool get _nameOk => _nameRule.hasMatch(_name.text.trim());

  // ── 칸별 검사 (문제 없으면 null) ─────────────────────────────
  String? _checkName(String? v) {
    final n = (v ?? '').trim();
    if (n.isEmpty) return '이름을 입력하세요';
    return _nameRule.hasMatch(n) ? null : '이름은 한글이나 영문으로 입력하세요';
  }

  String? _checkEmail(String? v) {
    if (!_emailRule.hasMatch((v ?? '').trim())) return '이메일 형식이 올바르지 않아요';
    if (_emailV.token == null) return '이메일 인증을 해 주세요';
    return null;
  }

  String? _checkPassword(String? v) {
    final p = v ?? '';
    final miss = [for (final r in _pwRules) if (!r.$2(p)) r.$1];
    return miss.isEmpty ? null : _pwRuleText;
  }

  String? _checkPasswordConfirm(String? v) => v == _password.text ? null : '비밀번호가 일치하지 않아요';

  bool _phoneFormatOk(String v) {
    final digits = v.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 9 && digits.length <= 11;
  }

  String? _checkPhone(String? v) {
    if (!_phoneFormatOk(v ?? '')) return '전화번호 형식이 올바르지 않아요';
    if (_phoneV.token == null) return '전화번호 인증을 해 주세요';
    return null;
  }

  String? _checkVehicle(String? v) =>
      _vehicleRule.hasMatch((v ?? '').trim()) ? null : '차량번호 형식이 올바르지 않아요';

  // ── 1단계: 사번 확인 ─────────────────────────────────────────
  Future<void> _checkEmpNo() async {
    final raw = _empNoInput.text.trim();
    if (raw.isEmpty) {
      setState(() => _empError = '사번을 입력하세요');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _empError = null;
    });
    try {
      final no = await AuthService.checkEmployee(raw);
      if (mounted) {
        setState(() {
          _empNo = no;
          _empNoInput.text = no; // 2단계 '사번' 칸에 서버가 정리한 사번 그대로
        });
      }
    } on AuthException catch (e) {
      if (mounted) setState(() => _empError = e.message);
    } catch (_) {
      if (mounted) setState(() => _empError = '사번을 확인하지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── 이메일 · 전화번호 인증 (공용) ─────────────────────────────
  Future<void> _sendCode(_Verify v, String value, Future<String?> Function(String) send) async {
    setState(() {
      v.busy = true;
      v.msg = null;
    });
    try {
      final demo = await send(value);
      if (!mounted) return;
      setState(() {
        v.sent = true;
        v.sentTo = value;
        v.demo = demo;
        v.code.clear();
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => v.msg = e.message);
    } catch (_) {
      if (mounted) setState(() => v.msg = '인증번호를 보내지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => v.busy = false);
    }
  }

  Future<void> _verifyCode(_Verify v, String value, Future<String> Function(String, String) verify) async {
    if (v.code.text.trim().length < 4) {
      setState(() => v.msg = '인증번호를 입력하세요');
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      v.busy = true;
      v.msg = null;
    });
    try {
      final token = await verify(value, v.code.text.trim());
      if (!mounted) return;
      setState(() {
        v.token = token;
        v.verifiedValue = value;
        v.sent = false;
        v.demo = null;
      });
    } on AuthException catch (e) {
      if (mounted) setState(() => v.msg = e.message);
    } catch (_) {
      if (mounted) setState(() => v.msg = '인증하지 못했어요\n잠시 뒤 다시 시도해 주세요');
    } finally {
      if (mounted) setState(() => v.busy = false);
    }
  }

  // 번호 · 주소를 고치거나 지우면 처음으로 — 인증번호 칸이 사라지고 버튼은 다시 [인증번호 받기]
  void _onVerifyChanged(_Verify v, String value) {
    setState(() {
      final now = value.trim();
      if ((v.sent && now != v.sentTo) || (v.token != null && now != v.verifiedValue)) v.reset();
    });
  }

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
        empNo: _empNo,
        phoneToken: _phoneV.token,
        emailToken: _emailV.token,
      );
      if (mounted) Navigator.of(context).pop(_email.text.trim());
    } on AuthException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = '가입하지 못했어요\n잠시 뒤 다시 시도해 주세요');
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

  // ── 화면 ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // 2단계에서 뒤로 가기(<) = 1단계 사번 입력으로 (사번을 바꾸는 유일한 길)
    void back() {
      if (_empNo != null && !_loading) {
        setState(() => _empNo = null);
      } else {
        Navigator.of(context).maybePop();
      }
    }

    return PopScope(
      canPop: _empNo == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) back();
      },
      child: Scaffold(
        backgroundColor: AuthUi.page,
        appBar: AppBar(
          backgroundColor: AuthUi.page,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: BackButton(onPressed: back),
          title: const Text('회원가입'),
          centerTitle: true,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: _empNo == null ? _empStep() : _form(),
          ),
        ),
      ),
    );
  }

  // 1단계 — 사번 확인
  Widget _empStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _StepDots(step: 1),
        const SizedBox(height: 24),
        AuthField(
          label: '사번',
          controller: _empNoInput,
          hint: '사번을 입력하세요',
          enabled: !_loading,
          keyboardType: TextInputType.visiblePassword, // 숫자 · 영문 모두
          textInputAction: TextInputAction.done,
          onFieldSubmitted: (_) => _checkEmpNo(),
        ),
        if (_empError != null) AuthNote(_empError!, error: true),
        const SizedBox(height: 20),
        if (_loading)
          const SizedBox(height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
        else
          AuthButton(text: '사번 확인', onPressed: _checkEmpNo),
        const SizedBox(height: 18),
        _loginLink(),
      ],
    );
  }

  // 2단계 — 정보 입력
  Widget _form() {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _StepDots(step: 2),
          const SizedBox(height: 24), // 1단계와 같은 간격 — 넘어갈 때 '사번' 칸이 움직이지 않게
          // 확인된 사번 — 다른 칸과 같은 모양, 바꿀 수 없어서 흐리게 (비활성처럼). 바꾸려면 위 < 로 1단계로
          AuthField(
            label: '사번',
            controller: _empNoInput,
            readOnly: true,
            valid: true,
            height: 53,
          ),
          const SizedBox(height: 13),
          AuthField(
            label: '이름',
            controller: _name,
            hint: '이름을 입력하세요',
            enabled: !_loading,
            height: 53,
            textInputAction: TextInputAction.next,
            onChanged: _refresh,
            valid: _tri(_name.text, _nameOk),
            invalidNote: '이름은 한글이나 영문으로 입력하세요',
            validator: _checkName,
          ),
          const SizedBox(height: 13),
          _verifyBlock(
            label: '이메일',
            controller: _email,
            v: _emailV,
            hint: '이메일을 입력하세요',
            formatOk: (s) => _emailRule.hasMatch(s),
            invalidNote: '이메일 형식이 올바르지 않아요',
            demoWord: '메일',
            send: AuthService.sendEmailCode,
            verify: AuthService.verifyEmailCode,
            validator: _checkEmail,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 13),
          AuthField(
            label: '비밀번호',
            controller: _password,
            hint: '비밀번호를 입력하세요',
            password: true,
            enabled: !_loading,
            height: 53,
            textInputAction: TextInputAction.next,
            onChanged: _refresh,
            valid: _tri(_password.text, _checkPassword(_password.text) == null),
            invalidNote: _pwRuleText, // 틀릴 때만 규칙을 알려 줌
            validator: _checkPassword,
          ),
          const SizedBox(height: 13),
          AuthField(
            label: '비밀번호 확인',
            controller: _passwordConfirm,
            hint: '다시 입력하세요',
            password: true,
            enabled: !_loading,
            height: 53,
            textInputAction: TextInputAction.next,
            onChanged: _refresh,
            valid: _tri(_passwordConfirm.text, _passwordConfirm.text == _password.text),
            invalidNote: '비밀번호가 일치하지 않아요',
            validator: _checkPasswordConfirm,
          ),
          const SizedBox(height: 13),
          _verifyBlock(
            label: '전화번호',
            controller: _phone,
            v: _phoneV,
            hint: '010-1234-5678',
            formatOk: _phoneFormatOk,
            invalidNote: '전화번호 형식이 올바르지 않아요',
            demoWord: '문자',
            send: AuthService.sendPhoneCode,
            verify: AuthService.verifyPhoneCode,
            validator: _checkPhone,
            keyboardType: TextInputType.phone,
            inputFormatters: [PhoneHyphenFormatter()], // 숫자만 쳐도 '-' 자동
          ),
          const SizedBox(height: 13),
          AuthField(
            label: '차량번호',
            controller: _vehicle,
            hint: '12가 3456',
            enabled: !_loading,
            height: 53,
            textInputAction: TextInputAction.done,
            onChanged: _refresh,
            valid: _tri(_vehicle.text, _vehicleRule.hasMatch(_vehicle.text.trim())),
            invalidNote: '차량번호 형식이 올바르지 않아요',
            validator: _checkVehicle,
          ),
          const SizedBox(height: 10),
          _consentRow(),
          if (_error != null) AuthNote(_error!, error: true),
          const SizedBox(height: 14),
          if (_loading)
            const SizedBox(height: AuthUi.controlHeight, child: Center(child: CircularProgressIndicator(color: AppColors.navy)))
          else
            AuthButton(text: '가입하기', onPressed: _submit),
          const SizedBox(height: 18),
          _loginLink(),
        ],
      ),
    );
  }

  // 인증 칸 공용 — [값 칸 + 인증번호 받기 / 재전송] → [인증번호 칸 + 확인]
  //   체크 = 인증까지 끝남 · X = 모양이 틀림 · 표시 없음 = 아직 안 침 / 모양은 맞고 인증 전
  //   [인증번호 받기] 는 모양이 맞을 때만, 값을 고치거나 지우면 처음 상태로 (_onVerifyChanged)
  Widget _verifyBlock({
    required String label,
    required TextEditingController controller,
    required _Verify v,
    required String hint,
    required bool Function(String) formatOk,
    required String invalidNote,
    required String demoWord, // '메일' · '문자'
    required Future<String?> Function(String) send,
    required Future<String> Function(String, String) verify,
    required FormFieldValidator<String> validator,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    final value = controller.text.trim();
    final verified = v.token != null && value == v.verifiedValue;
    final ok = formatOk(value);
    final busy = v.busy || _loading;
    final bool? valid = verified ? true : (value.isNotEmpty && !ok ? false : null);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthField(
          label: label,
          controller: controller,
          hint: hint,
          enabled: !_loading,
          keyboardType: keyboardType,
          textInputAction: TextInputAction.next,
          inputFormatters: inputFormatters,
          onChanged: (s) => _onVerifyChanged(v, s),
          validator: validator,
          valid: valid,
          invalidNote: invalidNote,
          suffix: verified || !ok
              ? null
              : AuthTinyButton(text: v.sent ? '재전송' : '인증번호 받기', onPressed: busy ? null : () => _sendCode(v, value, send)),
        ),
        if (v.sent && !verified) ...[
          const SizedBox(height: 10),
          AuthField(
            label: '인증번호',
            controller: v.code,
            hint: '6자리 숫자',
            enabled: !_loading,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
            onFieldSubmitted: (_) => _verifyCode(v, value, verify),
            suffix: AuthTinyButton(text: '확인', onPressed: busy ? null : () => _verifyCode(v, value, verify)),
          ),
          if (v.demo != null)
            AuthNote('인증번호: ${v.demo}  ($demoWord 대신 보여 드려요 · 5분 안에 입력)', color: AppColors.textSecondary),
        ],
        if (v.msg != null) AuthNote(v.msg!, error: true),
      ],
    );
  }

  Widget _loginLink() => Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        const Text('이미 계정이 있나요? ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        GestureDetector(
          onTap: _loading ? null : () => Navigator.of(context).maybePop(),
          child: const Text('로그인하기',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        ),
      ]);

  // 동의 줄 — 둥근 네모 체크 · 글 · 오른쪽 화살표 = 내용 보기
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
                          color: _agreed ? AppColors.navy : Colors.transparent,
                          border: Border.all(
                              color: _agreed ? AppColors.navy : (_agreeError ? AuthUi.error : AppColors.textMuted),
                              width: 1.5),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: _agreed ? const Icon(Icons.check, size: 17, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 9),
                      const Expanded(
                        child: Text('(필수) 개인정보 수집 및 이용에 동의합니다',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
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
        if (_agreeError) const AuthNote('개인정보 수집 · 이용에 동의해야 가입할 수 있어요', error: true),
      ],
    );
  }
}

/// 위 단계 표시 — ① 사번 확인 ─ ② 정보 입력
class _StepDots extends StatelessWidget {
  final int step;
  const _StepDots({required this.step});

  @override
  Widget build(BuildContext context) {
    Widget dot(int n, String text) {
      final on = step >= n;
      return Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: on ? AppColors.navy : AppColors.fill, shape: BoxShape.circle),
          child: Text('$n',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : AppColors.textMuted)),
        ),
        const SizedBox(width: 6),
        Text(text,
            style: TextStyle(
                fontSize: 13,
                fontWeight: step == n ? FontWeight.w700 : FontWeight.w500,
                color: on ? AppColors.textPrimary : AppColors.textMuted)),
      ]);
    }

    return Row(children: [
      dot(1, '사번 확인'),
      Expanded(
        child: Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          color: AppColors.fill,
        ),
      ),
      dot(2, '정보 입력'),
    ]);
  }
}

/// 이메일 · 전화번호 인증 한 가지의 상태
class _Verify {
  final code = TextEditingController(); // 인증번호 칸
  bool sent = false; // 인증번호를 받았는지 (받았으면 인증번호 칸이 보임)
  String? sentTo; // 인증번호를 받은 값 (고치면 처음으로)
  String? demo; // 시연용 서버가 돌려준 인증번호
  String? token; // 인증 성공 표 — 가입할 때 서버에 같이 보냄
  String? verifiedValue; // 인증한 값
  String? msg; // 칸 아래 오류
  bool busy = false;

  void reset() {
    sent = false;
    sentTo = null;
    demo = null;
    token = null;
    verifiedValue = null;
    msg = null;
    code.clear();
  }
}