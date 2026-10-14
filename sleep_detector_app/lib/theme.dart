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
// [쓰는 법] AppColors.stage(stage) — 서버 응답의 stage(0~3)를 그대로 넣으면 화면 색이 나온다
//   관리자 웹(sleep_detector_api/static/admin.html)의 단계 색과 같은 값
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  static const Color navy = Color(0xFF1F2A5C); // 브랜드
  static const Color aiPurple = Color(0xFF6A4CC2); // AI 안내 · 기사 음성 보고 카드
  static const Color background = Color(0xFFF3F5FA);

  static const Color normal = Color(0xFF2E9E5B); // 0 정상
  static const Color caution = Color(0xFFF2B01E); // 1 주의
  static const Color rest = Color(0xFFF28C28); // 2 휴식 권고 (주황, 추가)
  static const Color urgent = Color(0xFFD93025); // 3 긴급

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
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.navy,
      foregroundColor: Colors.white,
      centerTitle: true,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.navy,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
