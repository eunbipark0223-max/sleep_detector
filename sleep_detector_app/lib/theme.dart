// ═══════════════════════════════════════════════════════════════
// theme.dart — 앱 색 · 글꼴
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_app/lib/theme.dart (🟢 그대로 + 색 추가)
//
// [이 파일이 하는 일]
//   - 단계 색: 0 정상 초록 · 1 주의 노랑 · 2 휴식 권고 주황(추가) · 3 긴급 빨강
//   - 브랜드 남색 · AI 카드 보라 (앱 화면 구상 PPT 기준)
//
//   - 별명: primary = navy · danger = urgent (수업 코드 이름)
//   - 글자 · 테두리: textPrimary · textSecondary · textMuted · cardBorder
//
// [쓰는 법] AppColors.stage(stage) — 서버 응답의 stage(0~3)를 그대로 넣으면 화면 색이 나온다
//   관리자 웹(sleep_detector_api/static/admin.html)의 단계 색과 같은 값
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // (11/16 C · R안 = 우리 readdy 디자인, 애플 느낌) 남색 · 바탕 · 글자 색을 readdy 값으로
  static const Color navy = Color(0xFF1E346B); // 브랜드 (readdy primary-500)
  static const Color navyDeep = Color(0xFF10214A); // 로그인 · 메뉴 머리 (readdy primary-700)
  static const Color aiPurple = Color(0xFF6A4CC2); // AI 안내 · 기사 음성 보고 카드
  static const Color background = Color(0xFFEBEEF3); // 화면 바탕 (readdy background-100)
  static const Color card = Color(0xFFFCFCFE); // 흰 카드 (readdy background-50)
  static const Color fill = Color(0xFFDFE2E8); // 회색 버튼 · 구분선 (readdy background-200)

  static const Color normal = Color(0xFF2E9E5B); // 0 정상
  static const Color caution = Color(0xFFF2B01E); // 1 주의
  static const Color rest = Color(0xFFF28C28); // 2 휴식 권고 (주황, 추가)
  static const Color urgent = Color(0xFFD93025); // 3 긴급

  // 글자 · 테두리 색 (관리자 웹 admin.html 의 글자 · 선 색과 같은 계열)
  static const Color textPrimary = Color(0xFF0D111B); // 제목 · 본문 (readdy foreground-950)
  static const Color textSecondary = Color(0xFF595E67); // 설명 · 부제 (foreground-600)
  static const Color textMuted = Color(0xFF8F929A); // 시각 · 힌트 · 비활성 (foreground-400)
  static const Color cardBorder = Color(0xFFDFE2E8); // 카드 · 입력창 테두리 (background-200)

  /// 단계 바탕 (부엉이가 잘 보이는 연한 단계 색 — 사용자 지정 11/16): 정상 · 주의 · 휴식 권고 · 긴급
  static const List<Color> _stagePastel = [Color(0xFFB8DBCA), Color(0xFFF3D9A2), Color(0xFFF2BB86), Color(0xFFE9A6A5)];
  static Color stagePastel(int stage) => _stagePastel[stage.clamp(0, 3)];

  // 수업 코드가 쓰는 이름 (수업 화면을 그대로 가져와도 컴파일되게 우리 색에 연결한 별명)
  static const Color primary = navy;
  static const Color danger = urgent;

  static const List<Color> _stageColors = [normal, caution, rest, urgent];

  /// 단계(0~3) → 화면 색. 범위를 벗어나면 가까운 끝 단계 색.
  static Color stage(int stage) => _stageColors[stage.clamp(0, 3)];

  /// 단계 색 위에 올리는 글자색 (노랑 바탕은 어두운 글자여야 읽힌다)
  static Color onStage(int stage) => stage == 1 ? const Color(0xFF222222) : Colors.white;
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.navy, primary: AppColors.navy),
    scaffoldBackgroundColor: AppColors.background,
    // (11/16 R안) 제목줄은 바탕과 같은 연회색 · 진한 글자 (애플 느낌), 그림자 없음
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.fill, thickness: 1, space: 1),
  );
}
