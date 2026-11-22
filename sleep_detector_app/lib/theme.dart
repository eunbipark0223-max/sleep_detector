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
import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // (11/17 C · 관리자 웹 느낌) 차분한 남색 · 아주 연한 회색 바탕 · 흰 카드 — 팀 관리자 웹(졸음가드 관리자)과 같은 값
  static const Color navy = Color(0xFF1F2A5C); // 브랜드 · 알약 버튼 · AI 분석 카드 (관리자 웹 남색)
  static const Color navyDeep = Color(0xFF151D42); // 더 진한 남색 (눌림 · 강조)
  static const Color aiPurple = Color(0xFF6A4CC2); // AI 안내 · 기사 음성 보고 카드
  static const Color background = Color(0xFFF3F4F8); // 화면 바탕 (관리자 웹 바탕)
  static const Color card = Color(0xFFFFFFFF); // 흰 카드
  static const Color fill = Color(0xFFE6E8EF); // 회색 칸 · 구분선
  static const Color field = Color(0xFFF3F4F8); // 입력칸 바탕 (관리자 웹 로그인 입력칸)
  static const Color line = Color(0xFFECEEF3); // 목록 줄 사이 얇은 선
  static const Color live = Color(0xFF1E8E3E); // LIVE 초록 점 · 조치완료 버튼

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
  static Color onStage(int stage) => stage == 1 ? const Color(0xFF222222) : Colors.white;
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
        shape: const StadiumBorder(), // 관리자 웹처럼 양 끝이 완전히 둥근 알약 버튼
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.fill, thickness: 1, space: 1),
  );
}
