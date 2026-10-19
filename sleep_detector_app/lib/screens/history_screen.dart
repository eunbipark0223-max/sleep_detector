// ═══════════════════════════════════════════════════════════════
// screens/history_screen.dart — 운행 기록 (내 경고 목록)
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/my_reports_screen.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - GET /events/my 목록 · 단계 필터 칩 · 상태 배지 (미확인 · 확인 · 조치완료 · 휴식완료)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

// ── 임시 화면 (10/15 팀장) — main_screen 이 이 이름을 불러서 앱이 켜지도록 넣어 둠.
//    담당(D)이 작업할 때 이 아래를 지우고 진짜 화면으로 바꾸면 됩니다 (클래스 이름 HistoryScreen 은 유지).
import 'package:flutter/material.dart';

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('운행 기록 — 준비 중'));
  }
}