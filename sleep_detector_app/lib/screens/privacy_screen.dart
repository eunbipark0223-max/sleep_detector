// screens/privacy_screen.dart — (11/25 사용자 요청) 개인정보 처리방침 (내 정보 맨 아래에서 열림)
//   회원가입 때 동의한 내용과 같은 글 (signup_screen 의 동의 문구)
import 'package:flutter/material.dart';

import '../design_tokens.dart';
import 'guide_screen.dart';
import '../widgets/owl_says.dart' show keepWords;
import '../theme.dart';

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});

  static const List<(String, List<String>)> _sections = [
    ('수집 항목', [
      '가입할 때: 사번, 이름, 이메일, 비밀번호(암호화해서 저장), 전화번호, 차량번호',
      '출발 전 눈 기준 측정과 운행 중 눈 상태를 확인할 때: 얼굴 사진 (졸음이 아니라고 확인되면 바로 삭제해요)',
      '졸음이 확인됐을 때: 그 순간의 얼굴 사진, 위치(위도 · 경도), 졸음 기록(단계 · 요약 · 음성 퀴즈에 답한 글자) · 음성은 녹음하지 않아요',
    ]),
    ('이용 목적', ['로그인 등 계정 관리, 졸음 경고 대응, 경고가 났을 때 관리자가 기사님께 연락']),
    ('외부 AI 전송', ['2단계 이상 졸음이 확인되면 그 사진과 눈 상태 숫자를 구글 Gemini(AI)에 보내 상황 요약을 만들어요']),
    ('열람', ['졸음 사진과 기록은 기사님 본인과 관리자만 볼 수 있어요']),
    ('보관 기간', ['졸음 사진은 30일 뒤 자동으로 삭제해요', '계정과 경고 기록은 서비스를 이용하는 동안 보관해요']),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('개인정보 처리방침'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // (11/25 사용자 요청) 위 안내 글은 뺌
          for (final (title, items) in _sections) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
              decoration: BoxDecoration(
                color: AppColors.card,
                borderRadius: BorderRadius.circular(AppRadius.card),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                for (final item in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(keepWords(item), style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary)), // (11/25 사용자 요청) 앞 점 빼고 제목과 같은 시작점
                  ),
              ]),
            ),
          ],
        ],
      ),
    );
  }
}


/// (11/25 사용자 요청 · 슈퍼SOL 화면 맨 아래처럼) 홈 · 내 정보 맨 아래 묶음
///   방패 + '졸음가드' / 작은 회색 설명 / 선으로 나뉜 줄 — 개인정보 처리방침 › · 사용 가이드 ›
class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  Widget _row(BuildContext context, String label, Widget page) => InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
        child: SizedBox(
          height: 52,
          child: Row(children: [
            Expanded(child: Text(label, style: const TextStyle(fontSize: 13.5, color: AppColors.textMuted))), // (11/25 사용자 요청) '› 를 누르면 …' 안내 글과 같은 크기 · 굵기 · 색
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textMuted),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        // (11/25 사용자 요청) 위 기록 카드(네모) 왼쪽 끝선과 같은 시작점 — 아이콘 안쪽 여백만큼 당김
        Transform.translate(offset: const Offset(-2, 0), child: const Icon(Icons.verified_user_rounded, size: 22, color: AppColors.textMuted)),
        const SizedBox(width: 6),
        Text('졸음가드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.4, color: AppColors.textMuted)),
      ]),
      const SizedBox(height: 12),
      // (11/25) 단어 중간에서 안 끊김 · '› 를 누르면 …' 안내와 같은 회색
      Text(
        keepWords('졸음가드는 운전자 졸음 안전관리 솔루션이에요\n'
            '운행 중 졸음을 살펴 단계별로 안내하고, 졸음 사진과 기록은 기사님 본인과 관리자만 볼 수 있어요'),
        style: const TextStyle(fontSize: 13.5, height: 1.5, color: AppColors.textMuted), // 안내 글과 같은 글씨
      ),
      const SizedBox(height: 10),
      _row(context, '개인정보 처리방침', const PrivacyScreen()),
      const Divider(height: 1, thickness: 1, color: AppColors.line),
      _row(context, '사용 가이드', const GuideScreen()),
      const Divider(height: 1, thickness: 1, color: AppColors.line),
    ]);
  }
}
