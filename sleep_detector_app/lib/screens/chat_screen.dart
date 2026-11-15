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

const String _baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
const Duration _timeout = Duration(seconds: 40); // RAG + Gemini 라 조금 길게
const Color _chipBg = Color(0xFFE6E9F4); // 수업 primaryLight 자리 (남색 연하게)
const Color _chipText = AppColors.navy; // 수업 primaryDark 자리
const List<String> _greetingSuggestions = [
  '연속 운전 기준은?',
  '얼마나 쉬어야 하나요?',
  '졸음운전 사고 처벌은?',
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

  // ── 화면 (11/16 Figma 시안 '졸음운전 감지 앱5' 규정 도우미 — 디자인만. 서버 호출 · 대화 흐름은 위 그대로) ──
  static const Color _bg = Color(0xFFF8F9FC);
  static const String _owl = 'assets/owl/guide_owl.png';

  bool get _started => _messages.any((m) => m.isMine);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // AppBar 는 MainScreen 것 (탭 안)
      backgroundColor: _bg,
      resizeToAvoidBottomInset: true, // 키보드가 올라올 때 화면을 밀어 올린다
      body: Column(
        children: [
          Expanded(
            child: ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              children: [
                _greeting(),
                // 추천 질문 — 처음에는 인사 아래 2 × 2 카드
                if (!_started && _suggestions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _suggestionGrid(),
                ],
                const SizedBox(height: 14),
                for (final m in _messages.skip(1)) _bubble(m),
                if (_isSending) _typingBubble(),
              ],
            ),
          ),
          // 대화가 시작된 뒤 남은 추천 질문 — 입력창 위 한 줄 (답을 가리지 않게)
          if (_started && _suggestions.isNotEmpty && !_isSending) _suggestionRow(),
          _inputBar(),
        ],
      ),
    );
  }

  Widget _avatar() => ClipOval(child: Image.asset(_owl, width: 40, height: 40, fit: BoxFit.cover));

  // 첫 인사 — 부엉이 + 굵은 제목 · 설명 (서버 인사말 대신 시안 문구)
  Widget _greeting() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _avatar(),
        const SizedBox(width: 10),
        Flexible(
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: _botBox,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('무엇이 궁금하세요?',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.textPrimary)),
                SizedBox(height: 4),
                Text('운전 시간과 휴식 규정을 쉬운 말로 알려드릴게요.',
                    style: TextStyle(fontSize: 14, height: 1.45, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static final BoxDecoration _botBox = BoxDecoration(
    color: Colors.white,
    border: Border.all(color: AppColors.cardBorder),
    borderRadius: const BorderRadius.only(
      topLeft: Radius.circular(4),
      topRight: Radius.circular(18),
      bottomLeft: Radius.circular(18),
      bottomRight: Radius.circular(18),
    ),
  );

  Widget _suggestionGrid() {
    return Padding(
      padding: const EdgeInsets.only(left: 50),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 2.6,
        children: [
          for (final q in _suggestions)
            Material(
              color: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.cardBorder)),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _send(q),
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(q,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _suggestionRow() {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        children: [
          for (final q in _suggestions)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(q, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _chipText)),
                backgroundColor: _chipBg,
                side: BorderSide.none,
                shape: const StadiumBorder(),
                onPressed: () => _send(q),
              ),
            ),
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
          _avatar(),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: _botBox,
            child: const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
      ),
    );
  }

  // 말풍선 - 내 말은 오른쪽 남색, 부엉이 답은 왼쪽 흰색 (+ 근거 규정은 한 줄씩 접어서)
  Widget _bubble(ChatMessage m) {
    if (m.isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Align(
          alignment: Alignment.centerRight,
          child: Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.72),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(4),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(m.text, style: const TextStyle(fontSize: 15, height: 1.45, color: Colors.white)),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _avatar(),
          const SizedBox(width: 10),
          Flexible(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: _botBox,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // AI 가 답하지 못해 규정 원문만 보여 줄 때
                  if (!m.isReal)
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: AppColors.rest.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(999)),
                      child: const Text('규정 원문으로 안내해요',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.rest)),
                    ),
                  Text(m.text, style: const TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary)),
                  if (m.sources.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Divider(height: 1, color: AppColors.cardBorder),
                    const SizedBox(height: 6),
                    for (final src in m.sources) _SourceLine(src: src),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 입력창 — 둥근 칸 + 남색 네모 보내기
  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      color: _bg,
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
                style: const TextStyle(fontSize: 15),
                decoration: InputDecoration(
                  hintText: '규정에 대해 물어보세요',
                  counterText: '',
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.cardBorder)),
                  enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.cardBorder)),
                  focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppColors.navy, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Material(
              color: _isSending ? AppColors.textMuted : AppColors.navy,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: _isSending ? null : () => _send(_inputController.text),
                child: const SizedBox(width: 50, height: 50, child: Icon(Icons.chevron_right, size: 30, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 근거 규정 한 줄 — 제목만 보이고 누르면 원문 (주소 · 발행일 같은 글은 숨김)
class _SourceLine extends StatefulWidget {
  final Map<String, dynamic> src;
  const _SourceLine({required this.src});

  @override
  State<_SourceLine> createState() => _SourceLineState();
}

class _SourceLineState extends State<_SourceLine> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final title = '${widget.src['title'] ?? '규정'}'.split(' (').first;
    final content = '${widget.src['content'] ?? ''}'.trim();
    return InkWell(
      onTap: content.isEmpty ? null : () => setState(() => _open = !_open),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description_outlined, size: 18, color: AppColors.navy),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.navy)),
                ),
                if (content.isNotEmpty)
                  Text(_open ? '접기' : '원문 보기',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
              ],
            ),
            if (_open)
              Container(
                margin: const EdgeInsets.only(top: 6),
                padding: const EdgeInsets.all(10),
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(color: const Color(0xFFF3F5FA), borderRadius: BorderRadius.circular(10)),
                child: SingleChildScrollView(
                  child: Text(content, style: const TextStyle(fontSize: 13, height: 1.5, color: AppColors.textSecondary)),
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
