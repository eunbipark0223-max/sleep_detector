// ═══════════════════════════════════════════════════════════════
// screens/profile_screen.dart — 내 정보
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/profile_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 신고 건수 → 경고 건수, 내 기준 표시만 추가
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

// ── 임시 화면 (10/15 팀장) — main_screen 이 이 이름을 불러서 앱이 켜지도록 넣어 둠.
//    담당(D)이 작업할 때 이 아래를 지우고 진짜 화면으로 바꾸면 됩니다 (클래스 이름 ProfileScreen 은 유지).
import 'package:flutter/material.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('내 정보 — 준비 중'));
  }
}