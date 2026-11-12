// ═══════════════════════════════════════════════════════════════
// widgets/contact_dialog.dart — 전화번호 · 차량번호 입력 창 (내 정보 [수정] · 로그인 직후 필수 입력 공통)
// ═══════════════════════════════════════════════════════════════
// 담당: 팀장   |   우선: P0 (11/12 D 요청 — 관리자 웹 [전화 걸기]로 긴급 기사에게 바로 연락)
//
// [이 파일이 하는 일]
//   - ContactRules : 가입 화면(signup_screen)과 같은 검사 규칙 (전화 9 ~ 11자리 · 차량번호 형식)
//   - ContactDialog : 입력 창. required 면 로그인 직후 필수 입력 — [나중에] 없이 저장해야 진행, 막히면 [로그아웃]만
//       · 내 정보 [수정] 에서도 빈 칸 저장을 막는다 (전화번호 미등록이면 긴급 때 관리자가 연락할 수 없음)
//   - 저장은 AuthService.updateProfile → PATCH /users/me (서버 변경 없음)
//
// [돌려주는 값]
//   - 저장 성공: 바뀐 내 정보 Map  ·  [취소]: null  ·  [로그아웃](required 일 때): ContactDialog.logout
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../theme.dart';
import 'owl_says.dart'; // keepWords

class ContactRules {
  ContactRules._();

  // 서버(schema/request.py) · 가입 화면과 같은 규칙
  static final RegExp vehicleRule = RegExp(r'^(?:[가-힣]{2,4}\s*)?\d{2,3}\s*[가-힣]\s*\d{4}$');

  static String? checkPhone(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.length >= 9 && digits.length <= 11 ? null : '전화번호 형식이 올바르지 않아요 (예: 010-1234-5678)';
  }

  static String? checkVehicle(String? v) =>
      vehicleRule.hasMatch((v ?? '').trim()) ? null : '차량번호 형식이 올바르지 않아요 (예: 12가 3456, 서울 12가 3456)';

  /// 기사 계정인데 전화번호나 차량번호가 비어 있는지 (관리자 계정은 묻지 않음)
  static bool missing(Map<String, dynamic>? user) {
    if (user == null || user['role'] == 'admin') return false;
    String text(String k) => (user[k] ?? '').toString().trim();
    return text('phone').isEmpty || text('vehicle_no').isEmpty;
  }
}

class ContactDialog extends StatefulWidget {
  /// required 창에서 [로그아웃]을 누르면 돌려주는 값
  static const String logout = 'logout';

  final String phone;
  final String vehicleNo;
  final bool required; // 로그인 직후 필수 입력 (닫기 · 뒤로 가기 없음)
  final Future<Map<String, dynamic>> Function({String? phone, String? vehicleNo}) save;

  const ContactDialog({
    super.key,
    required this.phone,
    required this.vehicleNo,
    this.required = false,
    this.save = AuthService.updateProfile,
  });

  @override
  State<ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<ContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _phone = TextEditingController(text: widget.phone);
  late final TextEditingController _vehicle = TextEditingController(text: widget.vehicleNo);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return; // 빈 칸 · 형식 틀림은 저장하지 않음 (지우기 막음, 11/12)
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final result = await widget.save(phone: _phone.text.trim(), vehicleNo: _vehicle.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장하지 못했어요. 잠시 뒤 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final req = widget.required;
    return PopScope(
      canPop: !req, // 필수 입력은 뒤로 가기로 닫히지 않음
      child: AlertDialog(
        title: Text(req ? '연락처를 등록해 주세요' : '연락처 · 차량번호'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (req) ...[
                  Text(keepWords('졸음 경고가 나면 관리자가 바로 연락할 수 있게 전화번호와 차량번호를 꼭 적어 주세요.'), // 단어 중간에서 줄이 안 끊기게
                      style: const TextStyle(fontSize: 15, height: 1.45, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: _phone,
                  enabled: !_saving,
                  keyboardType: TextInputType.phone,
                  textInputAction: TextInputAction.next,
                  validator: ContactRules.checkPhone,
                  decoration: const InputDecoration(labelText: '전화번호', hintText: '010-1234-5678', errorMaxLines: 2),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _vehicle,
                  enabled: !_saving,
                  textInputAction: TextInputAction.done,
                  validator: ContactRules.checkVehicle,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: const InputDecoration(labelText: '차량번호', hintText: '12가 3456', errorMaxLines: 2),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          if (req)
            TextButton(
              onPressed: _saving ? null : () => Navigator.of(context).pop(ContactDialog.logout),
              child: const Text('로그아웃', style: TextStyle(color: AppColors.danger)),
            )
          else
            TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('취소')),
          TextButton(
            onPressed: _saving ? null : _submit,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('저장'),
          ),
        ],
      ),
    );
  }
}
