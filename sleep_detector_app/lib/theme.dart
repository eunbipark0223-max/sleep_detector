// ═══════════════════════════════════════════════════════════════
// theme.dart — 앱 색 · 글꼴
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
//
// [이 파일이 하는 일]
//   - 단계 색: 0 정상 초록 · 1 주의 노랑 · 2 휴식 권고 주황(추가) · 3 긴급 빨강
//   - 브랜드 남색 · AI 카드 보라 (앱 화면 구상 PPT 기준)
//
//   - 별명: primary = navy · danger = urgent
//   - 글자 · 테두리: textPrimary · textSecondary · textMuted · cardBorder
//
// [쓰는 법] AppColors.stage(stage) — 서버 응답의 stage(0~3)를 그대로 넣으면 화면 색이 나온다
//   관리자 웹(sleep_detector_api/static/admin.html)의 단계 색과 같은 값
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'design_tokens.dart';

class AppColors {
  AppColors._();

  // (11/17 C · 관리자 웹 느낌) 차분한 남색 · 아주 연한 회색 바탕 · 흰 카드 — 팀 관리자 웹(졸음가드 관리자)과 같은 값
  static const Color navy = Color(0xFF1F2A5C); // 브랜드 · 알약 버튼 · AI 분석 카드 (관리자 웹 남색)
  static const Color navyDeep = Color(0xFF151D42); // 더 진한 남색 (눌림 · 강조)
  static const Color aiPurple = Color(0xFF6A4CC2); // AI 안내 · 기사 음성 보고 카드
  static const Color background = AppleGray.page; // (11/19 디자인 시스템) Headspace 크림 바탕 · 흰 카드가 그 위에 // 화면 바탕 — (11/18 사용자 요청) 전체 흰색, 카드는 회색 테두리로 구분
  static const Color card = Color(0xFFFFFFFF); // 흰 카드
  // (11/18 디자인 토큰) 회색 · 선은 애플 회색 단계 (design_tokens.dart AppleGray)
  static const Color fill = AppleGray.separator; // 회색 칸 · 구분선
  static const Color field = AppleGray.fill; // 입력칸 바탕
  static const Color line = AppleGray.opaqueSeparator; // 목록 줄 사이 얇은 선
  static const Color live = Color(0xFF1E8E3E); // LIVE 초록 점 · 조치완료 버튼

  static const Color normal = Color(0xFF2E9E5B); // 0 정상
  static const Color caution = Color(0xFFF2B01E); // 1 주의
  static const Color rest = Color(0xFFF28C28); // 2 휴식 권고 (주황, 추가)
  static const Color urgent = Color(0xFFD93025); // 3 긴급

  // 글자 · 테두리 색 (관리자 웹 admin.html 의 글자 · 선 색과 같은 계열)
  static const Color textPrimary = AppleGray.label; // 제목 · 본문
  static const Color textSecondary = AppleGray.secondaryLabel; // 설명 · 부제
  static const Color textMuted = AppleGray.tertiaryLabel; // 시각 · 힌트 · 비활성
  static const Color cardBorder = AppleGray.separator; // 카드 · 입력창 테두리

  /// 단계 바탕 (부엉이가 잘 보이는 연한 단계 색 — 사용자 지정 11/16): 정상 · 주의 · 휴식 권고 · 긴급
  static const List<Color> _stagePastel = [Color(0xFFB8DBCA), Color(0xFFF3D9A2), Color(0xFFF2BB86), Color(0xFFE9A6A5)];
  static Color stagePastel(int stage) => _stagePastel[stage.clamp(0, 3)];

  // 다른 화면이 쓰는 이름 (우리 색에 연결한 별명)
  static const Color primary = navy;
  static const Color danger = urgent;

  static const List<Color> _stageColors = [normal, caution, rest, urgent];

  /// 단계 알약 배지 바탕 (관리자 웹 '● 3단계 | 위험' 배지): 아주 연한 단계 색
  static const List<Color> _stageTint = [Color(0xFFE6F4EC), Color(0xFFFDF3DC), Color(0xFFFDEBDD), Color(0xFFFCE8E6)];
  static Color stageTint(int stage) => _stageTint[stage.clamp(0, 3)];

  /// 단계 알약 배지 글자 (바탕 위에서 잘 읽히는 진한 단계 색)
  static const List<Color> _stageInk = [Color(0xFF1E7A45), Color(0xFF8A5A00), Color(0xFFB4530F), Color(0xFFB3261E)];
  static Color stageInk(int stage) => _stageInk[stage.clamp(0, 3)];

  /// 단계(0~3) → 화면 색. 범위를 벗어나면 가까운 끝 단계 색.
  static Color stage(int stage) => _stageColors[stage.clamp(0, 3)];

  /// 단계 색 위에 올리는 글자색 (노랑 바탕은 어두운 글자여야 읽힌다)
  static Color onStage(int stage) => stage == 1 ? AppleGray.label : Colors.white; // 노랑 위 글자도 진회색
}

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Pretendard', // (11/17) 애플 글꼴 느낌의 무료 글꼴 (pubspec.yaml fonts)
    // (11/17 사용자 요청) 뒤로 가기 = 애플처럼 '<' 꺾쇠 (안드로이드 기본 ← 화살표 대신) — 앱 전체
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (context) => const Icon(Icons.arrow_back_ios_new_rounded, size: 22),
    ),
    colorScheme: ColorScheme.fromSeed(seedColor: AppColors.navy, primary: AppColors.navy),
    // (11/18 피드백) 화면이 바뀔 때 아이폰처럼 오른쪽에서 부드럽게 밀려 들어옴 (앱 전체)
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    }),
    scaffoldBackgroundColor: AppColors.background,
    // (11/18 디자인 토큰) 눌렀을 때 안드로이드 물결 대신 애플처럼 살짝 어두워지기만
    splashFactory: NoSplash.splashFactory,
    highlightColor: const Color(0x0F000000),
    // 글자 크기 단계 = 애플 Dynamic Type (design_tokens.dart AppType)
    textTheme: const TextTheme(
      displaySmall: AppType.largeTitle,
      headlineMedium: AppType.title1,
      headlineSmall: AppType.title2,
      titleLarge: AppType.title3,
      titleMedium: AppType.headline,
      titleSmall: AppType.subheadline,
      bodyLarge: AppType.body,
      bodyMedium: AppType.subheadline,
      bodySmall: AppType.footnote,
      labelLarge: AppType.headline,
      labelMedium: AppType.footnote,
      labelSmall: AppType.caption,
    ).apply(bodyColor: AppColors.textPrimary, displayColor: AppColors.textPrimary),
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
        animationDuration: AppMotion.normal, // (11/18) 버튼 색 · 모양이 바뀔 때 부드럽게
        backgroundColor: AppColors.navy,
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(), // 관리자 웹처럼 양 끝이 완전히 둥근 알약 버튼
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        animationDuration: AppMotion.normal,
        foregroundColor: AppColors.textPrimary,
        backgroundColor: AppColors.card,
        side: const BorderSide(color: AppColors.fill),
        minimumSize: const Size.fromHeight(52),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1, space: 1),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.navy, textStyle: AppType.headline, animationDuration: AppMotion.normal),
    ),
    // 입력칸 — 연한 회색 바탕 · 둥글기 12 · 테두리 없음, 누르면 남색 얇은 테두리
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      hintStyle: const TextStyle(color: AppColors.textMuted),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.field), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.field), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field), borderSide: const BorderSide(color: AppColors.navy, width: 1.5)),
    ),
    // 알림 창 · 아래 시트 · 하단 안내 — 애플처럼 둥글고 그림자 없이
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.sheet)),
      titleTextStyle: AppType.headline.copyWith(color: AppColors.textPrimary),
      contentTextStyle: AppType.subheadline.copyWith(color: AppColors.textSecondary, height: 1.45),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.sheet))),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textPrimary,
      contentTextStyle: AppType.subheadline.copyWith(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.card)),
    ),
  );
}
