// ═══════════════════════════════════════════════════════════════
// screens/regulation_screen.dart — 규정 보기 (RAG 근거 규정 카드)
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/regulation_screen.dart (🟡 수정 — 따로 된 화면 대신 공용 카드 · 아래 창)
//
// [이 파일이 하는 일]
//   - RegulationCard : 근거 규정 1건 카드 (제목 · 출처 배지 · 내용)
//       · 기본       : 늘 펼친 카드 — 경고 화면 [규정 듣기]
//       · collapsible : 눌러야 내용이 펼쳐지는 작은 카드 — 규정 도우미(chat) 답 아래 근거
//   - showRegulationSheet(context, regulations) : 아래에서 올라오는 '관련 규정' 창 (경고 화면 [규정 듣기] — 읽기는 경고 화면이)
//
// [왜 화면이 아니라 카드인가] (11/03)
//   규정은 경고 화면 [규정 보기] 창과 규정 도우미 답 아래에서 보여서 따로 넘어가는 화면이 필요 없음.
//   두 곳이 같은 카드 코드를 각자 갖고 있던 것을 여기 하나로 모음
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';

import '../models/sleep_response.dart';
import '../theme.dart';

const Color _accent = Color(0xFF0891B2); // 출처 배지 글자 · 아이콘 (청록)
const Color _badgeBg = Color(0xFFCFFAFE);

/// 근거 규정 1건 카드
class RegulationCard extends StatelessWidget {
  final String title;
  final String source;
  final String content;
  final bool collapsible; // true = 눌러야 내용이 펼쳐짐 (규정 도우미 말풍선 안)

  const RegulationCard({
    super.key,
    required this.title,
    required this.source,
    required this.content,
    this.collapsible = false,
  });

  /// 경고 응답의 regulations 한 건
  factory RegulationCard.fromRegulation(Regulation r, {bool collapsible = false}) =>
      RegulationCard(title: r.title, source: r.source, content: r.content, collapsible: collapsible);

  /// 규정 도우미(/chat) 응답의 sources 한 건 ({title, source, content})
  factory RegulationCard.fromJson(Map<String, dynamic> s, {bool collapsible = false}) => RegulationCard(
        title: (s['title'] as String?) ?? '',
        source: (s['source'] as String?) ?? '',
        content: (s['content'] as String?) ?? '',
        collapsible: collapsible,
      );

  @override
  Widget build(BuildContext context) => collapsible ? _collapsible(context) : _card();

  // 늘 펼친 카드 — 경고 화면 [규정 보기]
  Widget _card() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          if (source.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(source, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ),
          const SizedBox(height: 8),
          Text(content, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // 눌러야 펼쳐지는 작은 카드 — 규정 도우미 말풍선 안
  Widget _collapsible(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent), // 펼칠 때 위아래 선 없애기
      child: Material(
        // 말풍선 흰 배경 위에서도 누를 때 물결이 보이게 (없으면 ListTile 오류)
        type: MaterialType.transparency,
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          dense: true,
          leading: const Icon(Icons.article, color: _accent, size: 20),
          title: Text(
            title.isNotEmpty ? title : source,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          subtitle: source.isEmpty
              ? null
              : Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    margin: const EdgeInsets.only(top: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _badgeBg, borderRadius: BorderRadius.circular(8)),
                    child: Text(source, // 출처 뒤 긴 주소는 한 줄로 줄임 (폰에서 규정 4건이 화면을 다 차지하지 않게)
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _accent, fontSize: 11)),
                  ),
                ),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(content, style: TextStyle(color: Colors.grey[700], height: 1.4)),
            ),
          ],
        ),
      ),
    );
  }
}

/// [규정 듣기] — 아래에서 올라오는 '관련 규정' 창 (경고 화면). 창이 닫히면 끝나는 Future
Future<void> showRegulationSheet(BuildContext context, List<Regulation> regulations) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          const Text('관련 규정',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          if (regulations.isEmpty)
            const Text('표시할 규정이 없어요.', style: TextStyle(color: AppColors.textMuted)),
          for (final r in regulations) RegulationCard.fromRegulation(r),
        ],
      ),
    ),
  );
}
