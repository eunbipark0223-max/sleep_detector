// ═══════════════════════════════════════════════════════════════
// screens/chat_screen.dart — 규정 도우미 채팅
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/chat_screen.dart (🟡 인사말 · 예시 질문만)
//
// [이 파일이 하는 일]
//   - 졸음운전 · 휴게 규정 Q&A (sendChat)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════

// ── 임시 화면 (10/15 팀장) — main_screen 이 이 이름을 불러서 앱이 켜지도록 넣어 둠.
//    담당(B)이 작업할 때 이 아래를 지우고 진짜 화면으로 바꾸면 됩니다 (클래스 이름 ChatScreen 은 유지).
import 'package:flutter/material.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('규정 도우미 — 준비 중'));
  }
}