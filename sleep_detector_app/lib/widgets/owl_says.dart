// ═══════════════════════════════════════════════════════════════
// widgets/owl_says.dart — 한국어 줄바꿈 도우미 (keepWords · balancedLines, 여러 화면 공용)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   11/11 초안
//   (11/25 팀장) 부엉이 그림을 쓰지 않기로 해서 그림 말풍선(OwlSays · OwlAbove)은 뺌 — 줄바꿈 함수만 남김
// ═══════════════════════════════════════════════════════════════
/// 한국어 줄바꿈을 단어 단위로 — Flutter 는 글자 중간에서도 줄을 바꿔서 "자 / 주", "고정 / 하고" 처럼 끊김.
///   단어 안의 글자 사이에 '줄 바꾸지 마' 표시(U+2060 WORD JOINER)를 넣어 띄어쓰기에서만 줄이 바뀌게 한다 (11/11)
String keepWords(String text) => text
    .split('\n')
    .map((line) => line.split(' ').map((w) => w.split('').join('⁠')).join(' '))
    .join('\n');

/// (11/24 사용자 요청 · 3단계 경고 카드처럼) 줄 나누기 — 줄바꿈(\n) · 마침표 뒤에서 먼저 나누고,
///   그래도 한 줄이 길면(maxChars 넘으면) 가운데에 가까운 띄어쓰기에서 두 줄로. 각 줄은 한 줄로 그려서 단어 중간에서 안 끊김
List<String> balancedLines(String text, {int maxChars = 11}) {
  final out = <String>[];
  for (final raw in text.replaceAll('. ', '.\n').split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    if (line.length <= maxChars || !line.contains(' ')) {
      out.add(line);
      continue;
    }
    final mid = line.length / 2;
    var best = -1;
    for (var i = 0; i < line.length; i++) {
      if (line[i] == ' ' && (best < 0 || (i - mid).abs() < (best - mid).abs())) best = i;
    }
    out
      ..add(line.substring(0, best).trim())
      ..add(line.substring(best + 1).trim());
  }
  return out;
}
