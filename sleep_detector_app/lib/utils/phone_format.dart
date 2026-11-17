// ═══════════════════════════════════════════════════════════════
// utils/phone_format.dart — 전화번호 칸에 숫자만 치면 '-' 가 저절로 들어가게 (11/17 C)
// ═══════════════════════════════════════════════════════════════
//   01012345678 → 010-1234-5678 · 0212345678 → 02-1234-5678 · 0311234567 → 031-123-4567
//   서버 format_phone 과 같은 모양. 회원가입 · 연락처 입력창(contact_dialog)에서 씀
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/services.dart';

/// 숫자 → 하이픈 넣은 전화번호
String formatPhoneDigits(String input) {
  var d = input.replaceAll(RegExp(r'\D'), '');
  if (d.length > 11) d = d.substring(0, 11);
  if (d.startsWith('02')) {
    // 서울 02-XXX(X)-XXXX
    if (d.length <= 2) return d;
    if (d.length <= 5) return '02-${d.substring(2)}';
    if (d.length <= 9) return '02-${d.substring(2, 5)}-${d.substring(5)}'; // 02-123-4567
    return '02-${d.substring(2, 6)}-${d.substring(6, 10)}'; // 02-1234-5678
  }
  if (d.length <= 3) return d;
  if (d.length <= 6) return '${d.substring(0, 3)}-${d.substring(3)}';
  if (d.length <= 10) return '${d.substring(0, 3)}-${d.substring(3, 6)}-${d.substring(6)}'; // 010-123-4567 (10자리)
  return '${d.substring(0, 3)}-${d.substring(3, 7)}-${d.substring(7)}'; // 010-1234-5678
}

/// TextField 의 inputFormatters 에 넣는다 — 지우기 · 붙여넣기도 다시 맞춰 줌
class PhoneHyphenFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = formatPhoneDigits(newValue.text);
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}
