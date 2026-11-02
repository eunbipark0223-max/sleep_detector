// ═══════════════════════════════════════════════════════════════
// screens/profile_screen.dart — 내 정보
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/screens/profile_screen.dart (🟢 그대로)
//
// [이 파일이 하는 일]
//   - 신고 건수 → 경고 건수 (fetchMyEvents 로 센다, 못 받으면 '—'), 내 기준 표시만 추가
//   - AuthService.me() 로 내 정보(이름 · 이메일 · 역할 · 가입 방식 · 가입일)를 보여 준다
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
      appBar: AppBar(title: const Text('내 정보')),
      body: FutureBuilder<Map<String, dynamic>?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            final error = snapshot.error;
            return _Message(
              text: error is AuthException ? error.message : '내 정보를 불러오지 못했습니다',
              buttonText: '다시 시도',
              onPressed: _retry,
            );
          }
          final user = snapshot.data;
          if (user == null) {
            return _Message(text: '로그인 정보가 만료되었습니다. 다시 로그인해 주세요', buttonText: '로그인 화면으로', onPressed: _goLogin);
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

  Future<void> _editContact() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _ContactDialog(
        phone: _text('phone'),
        vehicleNo: _text('vehicle_no'),
        save: widget.saveContact ?? AuthService.updateProfile,
      ),
    );
    if (result == null || !mounted) return; // 취소
    setState(() {
      _user = {..._user, 'phone': result['phone'], 'vehicle_no': result['vehicle_no']};
    });
    _toast('연락처를 저장했어요');
  }

  String get _roleLabel => _text('role') == 'admin' ? '관리자' : '기사';

  String get _providerLabel => _text('provider') == 'google' ? '구글 로그인' : '이메일';

  // created_at 은 2026-10-14T09:30:00 같은 글자 — 앞 10자(날짜)만 보여 준다
  String get _joined {
    final raw = _text('created_at');
    return raw.length >= 10 ? raw.substring(0, 10) : '—';
  }

  @override
  Widget build(BuildContext context) {
    final name = _text('name');
    final email = _text('email');
    final initial = (name.isNotEmpty ? name : email).characters.firstOrNull ?? '?';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            child: Column(
              children: [
                _Avatar(initial: initial, photo: _photo, busy: _busy, onTap: _choose),
                const SizedBox(height: 12),
                Text(name.isEmpty ? '이름 없음' : name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 4),
                Text(email, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 10),
                Chip(
                  label: Text(_roleLabel),
                  backgroundColor: AppColors.background,
                  side: const BorderSide(color: AppColors.cardBorder),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Section(title: '계정', rows: [
          _Row(label: '가입 방식', value: _providerLabel),
          _Row(label: '가입일', value: _joined),
        ]),
        const SizedBox(height: 12),
        _Section(
          title: '연락처 · 차량',
          action: TextButton(onPressed: _editContact, child: const Text('수정')),
          rows: [
            _Row(label: '전화번호', value: _contactValue('phone')),
            _Row(label: '차량번호', value: _contactValue('vehicle_no')),
          ],
          note: '졸음 경고가 났을 때 관리자가 바로 연락하는 데만 써요.',
        ),
        const SizedBox(height: 12),
        _Section(title: '운전 기록', rows: [
          _Row(label: '경고 건수', value: _eventCount == null ? '—' : '$_eventCount건'),
          const _Row(label: '내 눈 기준', value: '측정 전'),
        ]),
      ],
    );
  }
}

/// 프로필 사진(없으면 이름 첫 글자) + 오른쪽 아래 카메라 표시. 누르면 사진 바꾸기 메뉴.
class _Avatar extends StatelessWidget {
  static const double _size = 80;
  final String initial;
  final Uint8List? photo;
  final bool busy;
  final VoidCallback onTap;
  const _Avatar({required this.initial, required this.photo, required this.busy, required this.onTap});

  Widget get _letter => Text(initial, style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: Colors.white));

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
                backgroundColor: AppColors.primary,
                child: photo == null
                    ? _letter
                    : ClipOval(
                        child: Image.memory(photo!, width: _size, height: _size, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, _, _) => _letter),
                      ),
              ),
              if (busy)
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x88000000)),
                    child: const Padding(
                      padding: EdgeInsets.all(26),
                      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
                    ),
                  ),
                ),
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(color: AppColors.primary, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 2)),
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

class _Section extends StatelessWidget {
  final String title;
  final List<_Row> rows;
  final Widget? action; // 제목 오른쪽 버튼 (예: [수정])
  final String? note; // 맨 아래 작은 안내 글
  const _Section({required this.title, required this.rows, this.action, this.note});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textMuted)),
                ?action,
              ],
            ),
            const SizedBox(height: 4),
            ...rows,
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note!, style: const TextStyle(fontSize: 12, color: AppColors.textMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// 전화번호 · 차량번호 입력 창. 저장에 성공하면 바뀐 내 정보(Map)를 돌려주고, 취소하면 null.
/// 서버가 형식을 검사해서 틀리면 그 문구를 창 안에 그대로 보여 준다 (창은 닫지 않음).
class _ContactDialog extends StatefulWidget {
  final String phone;
  final String vehicleNo;
  final Future<Map<String, dynamic>> Function({String? phone, String? vehicleNo}) save;
  const _ContactDialog({required this.phone, required this.vehicleNo, required this.save});

  @override
  State<_ContactDialog> createState() => _ContactDialogState();
}

class _ContactDialogState extends State<_ContactDialog> {
  late final TextEditingController _phone = TextEditingController(text: widget.phone);
  late final TextEditingController _vehicle = TextEditingController(text: widget.vehicleNo);
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // 칸을 비웠으면 ''(빈 글자)를 보내 서버가 지우게 한다
      final result = await widget.save(phone: _phone.text.trim(), vehicleNo: _vehicle.text.trim());
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on AuthException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '저장하지 못했어요. 잠시 뒤 다시 시도해 주세요';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('연락처 · 차량번호'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _phone,
              enabled: !_saving,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: '전화번호', hintText: '010-1234-5678'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _vehicle,
              enabled: !_saving,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: const InputDecoration(labelText: '차량번호', hintText: '12가 3456'),
            ),
            const SizedBox(height: 8),
            const Text('비워 두고 저장하면 지워져요.', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(fontSize: 13, color: AppColors.danger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('취소')),
        TextButton(
          onPressed: _saving ? null : _submit,
          child: _saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('저장'),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  const _Row({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 15, color: AppColors.textSecondary)),
          Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        ],
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
