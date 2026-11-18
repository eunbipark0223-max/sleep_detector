// ═══════════════════════════════════════════════════════════════
// screens/profile_screen.dart — 내 정보
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/profile_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 신고 건수 → 경고 건수 (fetchMyEvents 로 센다, 못 받으면 '—'), 내 기준 표시만 추가
//   - AuthService.me() 로 내 정보(이름 · 이메일 · 전화번호 · 차량번호)를 보여 주고, 줄을 누르면 그 칸 바꾸기 화면 (11/18)
//   - 프로필 사진: 아바타를 누르면 [갤러리에서 선택 · 사진 찍기 · 사진 삭제] (서버 /users/me/photo)
//   - 연락처 · 차량: 전화번호 · 차량번호를 보여 주고 [수정] 으로 적는다 (서버 PATCH /users/me). 관리자 웹의 '기사에게 연락' 창에 나온다
//     (생성자의 saveContact 는 테스트 · 미리보기에서 저장을 바꿔 끼우는 입구, 비우면 AuthService.updateProfile)
//   - main_screen 의 ≡ 메뉴 → 내 정보 에서 Navigator.push 로 열리므로 Scaffold · AppBar 를 직접 가진다
//
// [프로필 사진 메모]
//   - 사진은 로그인 토큰이 있어야 받을 수 있어서(서버가 파일 이름만 주고, 사진 주소는 인증이 필요) 바이트로 받아 그린다
//   - 올릴 때는 image_picker 가 가로 · 세로 1024 이하 · 품질 85 로 줄여 준다 (서버 제한 5MB 안에 들어오게)
//   - 생성자의 pickPhoto 는 테스트 · 미리보기에서 사진 고르기를 바꿔 끼우는 입구다 (비우면 image_picker)
//
// [연결 대기]
//   - 내 눈 기준: A 의 eye_monitor 개인 기준을 저장하는 곳이 정해지면 보여 준다 (지금은 '측정 전')
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/phone_format.dart';
import '../widgets/contact_dialog.dart';
import 'account_edit_screens.dart';
import 'login_screen.dart';

/// 고른 사진 한 장 (바이트 + 파일 이름 — 서버는 이름의 확장자를 검사한다)
class PickedPhoto {
  final Uint8List bytes;
  final String name;
  const PickedPhoto(this.bytes, this.name);
}

class ProfileScreen extends StatefulWidget {
  /// 사진 고르기 (갤러리 · 카메라). 취소하면 null. 비워 두면 image_picker.
  final Future<PickedPhoto?> Function(ImageSource source)? pickPhoto;

  /// 전화번호 · 차량번호 저장. 비워 두면 AuthService.updateProfile. 바뀐 내 정보(Map)를 돌려준다.
  final Future<Map<String, dynamic>> Function({String? phone, String? vehicleNo})? saveContact;

  const ProfileScreen({super.key, this.pickPhoto, this.saveContact});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late Future<Map<String, dynamic>?> _future = _load();

  // 화면(FutureBuilder)이 받기 전에 요청이 먼저 실패해도 '처리 안 된 오류'로 새지 않게 ignore() 를 붙인다
  // (오류는 FutureBuilder 가 받아서 화면에 안내로 보여 준다)
  Future<Map<String, dynamic>?> _load() {
    final future = AuthService.me();
    future.ignore();
    return future;
  }

  // setState 안에서는 값을 돌려주면 안 된다 (Future 를 돌려주면 오류) → 중괄호로 대입만 한다
  void _retry() {
    setState(() {
      _future = _load();
    });
  }

  void _goLogin() {
    Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.card,
      appBar: AppBar(title: const Text('내 정보'), centerTitle: true),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _Message(
              text: error is AuthException ? error.message : '내 정보를 불러오지 못했어요',
              buttonText: '다시 시도',
              onPressed: _retry,
            );
          }
          final user = snapshot.data;
          if (user == null) {
            return _Message(text: '로그인이 만료됐어요\n다시 로그인해 주세요', buttonText: '로그인 화면으로', onPressed: _goLogin);
          }
          return _Body(user: user, pickPhoto: widget.pickPhoto, saveContact: widget.saveContact);
        },
      ),
    );
  }
}

enum _PhotoAction { gallery, camera, delete }

class _Body extends StatefulWidget {
  final Map<String, dynamic> user;
  final Future<PickedPhoto?> Function(ImageSource source)? pickPhoto;
  final Future<Map<String, dynamic>> Function({String? phone, String? vehicleNo})? saveContact;
  const _Body({required this.user, this.pickPhoto, this.saveContact});

  @override
  State<_Body> createState() => _BodyState();
}

class _BodyState extends State<_Body> {
  Uint8List? _photo; // 내 프로필 사진 (없으면 이름 첫 글자)
  bool _busy = false; // 올리거나 지우는 중
  late Map<String, dynamic> _user = Map<String, dynamic>.of(widget.user); // 저장하면 이 복사본의 전화번호 · 차량번호를 바꾼다

  int? _eventCount; // 내 경고 건수 (못 받으면 null → '—')

  Map<String, dynamic> get user => _user;

  @override
  void initState() {
    super.initState();
    final url = user['photo_url'];
    if (url is String && url.isNotEmpty) _loadPhoto();
    _loadEventCount();
  }

  // 홈 · 운행 기록과 같은 fetchMyEvents 로 센다. 못 받아도 오류 안내 없이 '—' 로 둔다
  Future<void> _loadEventCount() async {
    try {
      final events = await ApiService.fetchMyEvents();
      if (!mounted) return;
      setState(() => _eventCount = events.length);
    } catch (_) {/* '—' 그대로 */}
  }

  // 사진을 못 받아도(404 · 연결 오류) 화면은 이름 첫 글자로 보여 주면 되므로 오류 안내는 띄우지 않는다
  Future<void> _loadPhoto() async {
    try {
      final bytes = await AuthService.fetchPhoto();
      if (!mounted) return;
      setState(() => _photo = bytes);
    } catch (_) {}
  }

  static Future<PickedPhoto?> _defaultPick(ImageSource source) async {
    final file = await ImagePicker().pickImage(source: source, maxWidth: 1024, maxHeight: 1024, imageQuality: 85);
    if (file == null) return null;
    final name = file.name.contains('.') ? file.name : '${file.name}.jpg';
    return PickedPhoto(await file.readAsBytes(), name);
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _choose() async {
    if (_busy) return;
    final action = await showModalBottomSheet<_PhotoAction>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.photo_library_outlined), title: const Text('갤러리에서 선택'), onTap: () => Navigator.pop(ctx, _PhotoAction.gallery)),
          ListTile(leading: const Icon(Icons.photo_camera_outlined), title: const Text('사진 찍기'), onTap: () => Navigator.pop(ctx, _PhotoAction.camera)),
          if (_photo != null)
            ListTile(
              leading: const Icon(Icons.delete_outline, color: AppColors.danger),
              title: const Text('사진 삭제', style: TextStyle(color: AppColors.danger)),
              onTap: () => Navigator.pop(ctx, _PhotoAction.delete),
            ),
        ]),
      ),
    );
    switch (action) {
      case _PhotoAction.gallery:
        await _upload(ImageSource.gallery);
      case _PhotoAction.camera:
        await _upload(ImageSource.camera);
      case _PhotoAction.delete:
        await _delete();
      case null:
        break;
    }
  }

  Future<void> _upload(ImageSource source) async {
    final PickedPhoto? picked;
    try {
      picked = await (widget.pickPhoto ?? _defaultPick)(source);
    } catch (_) {
      _toast('사진을 가져오지 못했어요');
      return;
    }
    if (picked == null) return; // 고르다가 취소
    setState(() => _busy = true);
    try {
      await AuthService.uploadPhoto(picked.bytes, picked.name);
      if (!mounted) return;
      setState(() => _photo = picked!.bytes);
      _toast('프로필 사진을 바꿨어요');
    } on AuthException catch (e) {
      _toast(e.message); // 서버 문구 그대로 (확장자 · 5MB 초과 등)
    } catch (_) {
      _toast('사진을 올리지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('사진 삭제'),
        content: const Text('프로필 사진을 삭제할까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('삭제', style: TextStyle(color: AppColors.danger))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await AuthService.deletePhoto();
      if (!mounted) return;
      setState(() => _photo = null);
      _toast('사진을 삭제했어요');
    } on AuthException catch (e) {
      _toast(e.message);
    } catch (_) {
      _toast('사진을 삭제하지 못했어요');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _text(String key) {
    final value = user[key];
    return value is String ? value.trim() : '';
  }

  // 전화번호 · 차량번호: 안 적었으면 '미등록'
  String _contactValue(String key) {
    final value = _text(key);
    return value.isEmpty ? '미등록' : value;
  }

  static final RegExp _nameRule = RegExp(r'^[가-힣a-zA-Z ]+$');

  // (11/18 사용자 요청) 이름 · 전화번호 · 차량번호를 한 칸씩 바꾸는 화면 (애플 설정처럼)
  Future<void> _edit(String key) async {
    final saveContact = widget.saveContact ?? AuthService.updateProfile;
    final Widget page = switch (key) {
      'name' => EditFieldScreen(
          title: '이름 변경',
          label: '이름',
          initial: _text('name'),
          hint: '이름을 입력하세요',
          isValid: (s) => _nameRule.hasMatch(s),
          invalidNote: '이름은 한글이나 영문으로 입력하세요',
          save: (v) => AuthService.updateProfile(name: v),
        ),
      'phone' => EditFieldScreen(
          title: '전화번호 변경',
          label: '전화번호',
          initial: _text('phone'),
          hint: '010-1234-5678',
          keyboardType: TextInputType.phone,
          inputFormatters: [PhoneHyphenFormatter()],
          isValid: (s) => ContactRules.checkPhone(s) == null,
          invalidNote: '전화번호 형식이 올바르지 않아요',
          save: (v) => saveContact(phone: v),
        ),
      _ => EditFieldScreen(
          title: '차량번호 변경',
          label: '차량번호',
          initial: _text('vehicle_no'),
          hint: '12가 3456',
          isValid: (s) => ContactRules.checkVehicle(s) == null,
          invalidNote: '차량번호 형식이 올바르지 않아요',
          save: (v) => saveContact(vehicleNo: v),
        ),
    };
    final result = await Navigator.of(context).push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => page));
    if (result == null || !mounted) return; // 뒤로 가기
    setState(() => _user = {..._user, ...result});
    _toast('저장했어요');
  }

  Future<void> _changePassword() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PasswordScreen()));
    if (done == true) _toast('비밀번호를 바꿨어요');
  }

  Future<void> _changeEmail() async {
    final result = await Navigator.of(context)
        .push<Map<String, dynamic>>(MaterialPageRoute(builder: (_) => EmailChangeScreen(current: _text('email'))));
    if (result == null || !mounted) return;
    setState(() => _user = {..._user, ...result});
    _toast('이메일을 바꿨어요');
  }

  @override
  Widget build(BuildContext context) {
    final name = _text('name');
    final email = _text('email');
    final initial = (name.isNotEmpty ? name : email).characters.firstOrNull ?? '?';
    final isGoogle = _text('provider') == 'google';

    // (11/18 사용자 요청 · 애플 설정 화면) 흰 바탕 · 회색 테두리 카드 묶음 · 묶음 위 작은 제목 · 아래 작은 설명
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      children: [
        // 프로필 — 사진(누르면 바꾸기) + 이름만 ('기사' 표시 · 이메일은 아래 '내 정보' 묶음으로)
        Center(child: _Avatar(initial: initial, photo: _photo, busy: _busy, onTap: _choose)),
        const SizedBox(height: 12),
        Text(name.isEmpty ? '이름 없음' : name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 24),
        // (11/18 사용자 요청) 애플 설정처럼 줄을 누르면 바로 그 칸 바꾸기 화면 · 안내 글 없음 · 가입일 없음
        //   구글 계정은 이메일을 구글에서 관리해서 이메일 줄만 누를 수 없음
        _Section(
          title: '내 정보',
          rows: [
            _Row(label: '이름', value: name.isEmpty ? '미등록' : name, onTap: () => _edit('name')),
            _Row(label: '이메일', value: email, onTap: isGoogle ? null : _changeEmail),
            _Row(label: '전화번호', value: _contactValue('phone'), onTap: () => _edit('phone')),
            _Row(label: '차량번호', value: _contactValue('vehicle_no'), onTap: () => _edit('vehicle_no')),
          ],
        ),
        // 비밀번호 변경은 그대로 따로 한 줄 (구글 계정은 비밀번호가 없어서 숨김)
        if (!isGoogle) ...[
          const SizedBox(height: 24),
          _Section(title: '로그인 및 보안', rows: [_Row(label: '비밀번호 변경', value: '', onTap: _changePassword)]),
        ],
        const SizedBox(height: 24),
        _Section(title: '운전 기록', rows: [
          _Row(label: '경고 건수', value: _eventCount == null ? '—' : '$_eventCount건'),
        ]),
      ],
    );
  }
}

/// 프로필 사진(없으면 이름 첫 글자) + 오른쪽 아래 카메라 표시. 누르면 사진 바꾸기 메뉴
class _Avatar extends StatelessWidget {
  static const double _size = 88;
  final String initial;
  final Uint8List? photo;
  final bool busy;
  final VoidCallback onTap;
  const _Avatar({required this.initial, required this.photo, required this.busy, required this.onTap});

  Widget get _letter => Text(initial, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, color: AppColors.navy));

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '프로필 사진 바꾸기',
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: _size,
          height: _size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: _size / 2,
                backgroundColor: AppColors.navy.withValues(alpha: 0.08),
                child: photo == null
                    ? _letter
                    : ClipOval(
                        child: Image.memory(photo!,
                            width: _size, height: _size, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _letter),
                      ),
              ),
              if (busy)
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x88000000)),
                    child: Padding(padding: EdgeInsets.all(28), child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white)),
                  ),
                ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(color: AppColors.navy, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.photo_camera, size: 14, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 묶음 — 위 작은 회색 제목 · 흰 카드(회색 테두리) 안 줄 목록 (애플 설정 그룹)
class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  const _Section({required this.title, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 6, bottom: 8),
          child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textMuted)),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.cardBorder),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1, thickness: 1, indent: 16, color: AppColors.line),
              rows[i],
            ],
          ]),
        ),
      ],
    );
  }
}

/// 한 줄 — 왼쪽 이름 · 오른쪽 값 · (누를 수 있으면) 꺾쇠
class _Row extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback? onTap;
  const _Row({required this.label, required this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: EdgeInsets.fromLTRB(16, 12, onTap == null ? 16 : 10, 12),
        child: Row(
          children: [
            Text(label, style: const TextStyle(fontSize: 15.5, color: AppColors.textPrimary)),
            const SizedBox(width: 16),
            Expanded(
              child: Text(value,
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15.5, color: AppColors.textSecondary)),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded, size: 22, color: AppColors.textMuted),
            ],
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final String buttonText;
  final VoidCallback onPressed;
  const _Message({required this.text, required this.buttonText, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(buttonText)),
          ],
        ),
      ),
    );
  }
}
