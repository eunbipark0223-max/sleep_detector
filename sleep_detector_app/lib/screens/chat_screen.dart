// ═══════════════════════════════════════════════════════════════
// screens/chat_screen.dart — 규정 도우미 채팅
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: road_hazard_app/lib/screens/chat_screen.dart (🟡 인사말 · 예시 질문 + 아래 '수업과 다른 점')
//
// [이 파일이 하는 일]
//   - 졸음운전 · 휴게 규정 Q&A — 첫 인사, 추천 질문, 질문 → 답 + 근거 규정
//
// [서버 약속 — sleep_detector_api/routers/chat.py]
//   - GET  /chat/hello → {"message"}
//   - POST /chat (로그인 필요) {message, history: [{role: 'user'|'bot', text}]}
//       → {"success", "answer", "sources": [{title, source, content, is_real}], "is_real"}
//
// [수업과 다른 점]
//   - 응답 키: 수업 reply · suggestions → 우리 서버 message / answer · sources · is_real
//     추천 질문은 서버가 주지 않아서 _greetingSuggestions — 답이 올 때마다 아직 안 물어본 것만 다시 보여 줌
//   - 답 아래에 근거 규정(sources) — regulation_screen.dart 의 RegulationCard (collapsible), 누르면 원문
//   - is_real == false → "AI 답변 아님 — 규정 원문" 표시
//   - MainScreen(D) 의 '규정 도우미' 탭 안에 들어가므로 AppBar 없음 (제목은 MainScreen 이 보여 줌)
//   - 서버 호출: 수업은 ApiService.chatHello · sendChat 인데 api_service.dart(C) 에 아직 없어서 이 파일 아래 _chatHello · _sendChat.
//     C 가 api_service.dart 에 만들면 그쪽으로 바꾼다. 토큰은 AuthService.authHeaders() (D)
//   - 색: 수업 primaryLight · primaryDark 가 팀 theme.dart 에 없어서 _chipBg · _chipText
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../theme.dart';
import 'regulation_screen.dart';

const String _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
const Duration _timeout = Duration(seconds: 40); // RAG + Gemini 라 조금 길게
const Color _chipBg = Color(0xFFE6E9F4); // 수업 primaryLight 자리 (남색 연하게)
const Color _chipText = AppColors.navy; // 수업 primaryDark 자리
const List<String> _greetingSuggestions = [
  '화물차는 몇 시간 운전하면 쉬어야 해?',
  '휴게시간은 최소 몇 분이야?',
  '졸음운전으로 사고 나면 처벌은?',
  '운전 중 휴대전화 써도 돼?',
];

// 메시지 한 줄
class ChatMessage {
  final String text;
  final bool isMine;
  final List<Map<String, dynamic>> sources; // 근거 규정 (봇 답만)
  final bool isReal; // false 면 AI 답변 아님 — 규정 원문만

  ChatMessage(this.text, {required this.isMine, this.sources = const [], this.isReal = true});

  Map<String, String> toJson() => {'role': isMine ? 'user' : 'bot', 'text': text};
}

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  List<String> _suggestions = [];
  final _asked = <String>{}; // 답을 받은 질문 (추천 질문에서 뺄 것)
  bool _isSending = false;

  @override
  void initState() {
    super.initState();
    _loadGreeting();
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // 첫 인사 불러오기
  Future<void> _loadGreeting() async {
    try {
      final res = await _chatHello();
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage(res['message'] as String, isMine: false));
        _suggestions = List<String>.from(_greetingSuggestions);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.add(ChatMessage('안녕하세요, 졸음 가드 규정 도우미예요. 졸음운전 · 연속 운전 휴게시간 규정을 물어보세요.', isMine: false));
        _suggestions = List<String>.from(_greetingSuggestions);
      });
    }
    _scrollToBottom();
  }

  // 메시지 보내기 - 이전 대화를 함께
  Future<void> _send(String text) async {
    final message = text.trim();
    if (message.isEmpty || _isSending) return;

    final history = _messages.length > 6
        ? _messages.sublist(_messages.length - 6) // 이전 대화(최근 6개만)를 서버에 함께 보낸다 (맥락 유지)
        : List<ChatMessage>.from(_messages);

    setState(() {
      _messages.add(ChatMessage(message, isMine: true));
      _suggestions = [];
      _isSending = true;
    });
    _inputController.clear();
    _scrollToBottom();

    try {
      final res = await _sendChat(message: message, history: history.map((m) => m.toJson()).toList());
      if (!mounted) return;
      setState(() {
        _asked.add(message);
        _messages.add(
          ChatMessage(
            res['answer'] as String,
            isMine: false,
            sources: [for (final s in (res['sources'] as List? ?? const [])) Map<String, dynamic>.from(s as Map)],
            isReal: res['is_real'] == true,
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      final msg = e is TimeoutException
          ? '응답이 너무 늦습니다. 잠시 후 다시 시도해 주세요.'
          : e is _LoginRequired
          ? '로그인이 필요합니다. 다시 로그인해 주세요.'
          : '연결에 문제가 있습니다. 네트워크를 확인해 주세요.';
      setState(() {
        _messages.add(ChatMessage('⚠️ $msg', isMine: false));
      });
    } finally {
      // 답이 오면(실패해도) 추천 질문을 다시 — 이미 답을 받은 질문은 빼고
      if (mounted) {
        setState(() {
          _isSending = false;
          _suggestions = _greetingSuggestions.where((q) => !_asked.contains(q)).toList();
        });
      }
      _scrollToBottom();
    }
  }

  // 자동 스크롤 - 맨 아래로 스크롤
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 는 MainScreen 것 (탭 안)
      resizeToAvoidBottomInset: true, // 키보드가 올라올 때 화면을 밀어 올린다
      body: Column(
        children: [
          // 대화 목록
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + (_isSending ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == _messages.length) return _typingBubble();
                return _bubble(_messages[i]);
              },
            ),
          ),
          // 추천 질문
          if (_suggestions.isNotEmpty && !_isSending) _suggestionBar(),
          // 입력창
          _inputBar(),
        ],
      ),
    );
  }

  // '입력 중...' 표시
  Widget _typingBubble() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary,
            child: Text('🤖', style: TextStyle(fontSize: 13)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: AppColors.cardBorder),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      ),
    );
  }

  // 말풍선 - 내 말은 오른쪽, AI는 왼쪽 (+ 근거 규정)
  Widget _bubble(ChatMessage m) {
    final isMine = m.isMine;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isMine) ...[
            const CircleAvatar(
              radius: 14,
              backgroundColor: AppColors.primary,
              child: Text('🤖', style: TextStyle(fontSize: 13)),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isMine ? AppColors.primary : Colors.white,
                border: isMine ? null : Border.all(color: AppColors.cardBorder),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(14),
                  topRight: const Radius.circular(14),
                  bottomLeft: Radius.circular(isMine ? 14 : 4),
                  bottomRight: Radius.circular(isMine ? 4 : 14),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI 가 답하지 못해 규정 원문만 보여 줄 때
                  if (!isMine && !m.isReal)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 6),
                      child: Text(
                        'AI 답변 아님 — 규정 원문',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.rest),
                      ),
                    ),
                  Text(
                    m.text,
                    style: TextStyle(fontSize: 13, height: 1.5, color: isMine ? Colors.white : AppColors.textPrimary),
                  ),
                  // 근거 규정
                  if (m.sources.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '관련 규정 ${m.sources.length}건',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary),
                    ),
                    ...m.sources.map((src) => RegulationCard.fromJson(src, collapsible: true)), // 근거 규정 (눌러서 원문)
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 추천 질문 - 타이핑 없이 질문
  Widget _suggestionBar() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: _suggestions.map((q) {
          return InkWell(
            onTap: () => _send(q),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(color: _chipBg, borderRadius: BorderRadius.circular(20)),
              child: Text(q, style: const TextStyle(fontSize: 12, color: _chipText)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // 입력창
  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.cardBorder, width: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                enabled: !_isSending,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                maxLength: 500, // 서버 ChatRequest.message 최대 500자
                decoration: const InputDecoration(
                  hintText: '규정을 물어보세요',
                  counterText: '',
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _isSending ? AppColors.textMuted : AppColors.primary,
              borderRadius: BorderRadius.circular(22),
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: _isSending ? null : () => _send(_inputController.text),
                child: const SizedBox(width: 44, height: 44, child: Icon(Icons.send, size: 20, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── 서버 호출 (수업 api_service.dart 모양 — C 가 api_service 에 chatHello · sendChat 을 만들면 그쪽으로) ──
class _LoginRequired implements Exception {}

// 첫 인사 (GET /chat/hello)
Future<Map<String, dynamic>> _chatHello() async {
  final url = Uri.parse('$_baseUrl/chat/hello');
  final response = await http.get(url).timeout(const Duration(seconds: 10));
  if (response.statusCode == 200) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }
  throw Exception('서버 오류: ${response.statusCode}');
}

// 질문 (POST /chat) — 로그인 필요
Future<Map<String, dynamic>> _sendChat({required String message, required List<Map<String, String>> history}) async {
  final url = Uri.parse('$_baseUrl/chat');
  final response = await http
      .post(url, headers: await AuthService.authHeaders(), body: jsonEncode({'message': message, 'history': history}))
      .timeout(_timeout);
  if (response.statusCode == 200) {
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  } else if (response.statusCode == 401) {
    throw _LoginRequired();
  }
  throw Exception('서버 오류: ${response.statusCode}');
}
