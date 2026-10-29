// ═══════════════════════════════════════════════════════════════
// tools/map_preview_main.dart — 졸음쉼터 지도 화면만 따로 실행 (앱과 따로 실행)
// ═══════════════════════════════════════════════════════════════
// 담당: B   |   우선: P2
// 수업 원본: (없음, 🔴 신규) — 홈 · 경고 화면에 지도 버튼이 연결되기 전 확인용. 로그인 · 서버 없이 돈다
//
// [실행]  (sleep_detector_app 폴더, 시연 폰 USB 연결 또는 에뮬레이터)
//   flutter run -t lib/tools/map_preview_main.dart --dart-define=KAKAO_JS_KEY=본인키
//   - 키는 sleep_detector_api/.env 의 KAKAO_JS_KEY (코드 · GitHub · 단톡에 쓰지 않는다)
//   - 에뮬레이터 위치: 확장 컨트롤(…) → Location 에서 바꿀 수 있음
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

import '../screens/map_screen.dart';
import '../theme.dart';

void main() => runApp(MaterialApp(theme: buildAppTheme(), home: const MapScreen(), debugShowCheckedModeBanner: false));
