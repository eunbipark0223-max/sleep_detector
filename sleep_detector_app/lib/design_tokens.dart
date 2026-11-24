// ═══════════════════════════════════════════════════════════════
// design_tokens.dart — 디자인 기준값 한 곳 (11/18 C)
// ═══════════════════════════════════════════════════════════════
// [왜 만들었나] 화면마다 글자 크기 · 둥글기 · 간격 · 회색이 조금씩 달라서 '제각각' 이라는 피드백이 계속 나옴.
//   → 애플이 공개한 iOS 기준(Apple Human Interface Guidelines)을 토큰으로 정하고,
//     우리 앱 고유의 색(남색 브랜드 · 단계 색)과 합쳐서 앱 전체가 이 값만 쓰게 한다.
//
// [합친 방법] (11/19 — 영상 '클로드로 디자인하기' 방식: 레퍼런스 → 토큰 추출 → 디자인 시스템 → 적용)
//   - 레퍼런스: Headspace (캐릭터가 있는 따뜻한 명상 앱 — 우리 부엉이 캐릭터와 어울림)
//     headspace.com 의 실제 스타일에서 뽑은 값: 글자 #2D2C2B · #44423F · #63605D / 바탕 크림 #F9F4F2 /
//     선 #E2DED9 · #C6C1B9 / 둥글기 2rem(32) 가장 많음 · 알약 / 그림자 '아래로만 2px 납작하게' (0 0.125rem 0 rgba(65,61,69,.2))
//   - Headspace 에서 가져온 것: 따뜻한 크림 바탕 · 따뜻한 회색 글자 · 선 · 넉넉한 둥글기 · 버튼 아래 납작 그림자
//   - 애플에서 가져온 것: 글자 크기 단계(Large Title 34 … Caption 12) · 간격 4의 배수 · 목록 · 꺾쇠 · 눌렀을 때 물결 없음
//   - 우리 앱에서 유지한 것: 브랜드 남색(버튼 · 강조) · 단계 색 0~3 (관리자 웹과 같은 값 — 팀 약속이라 그대로)
//   - 둥글기는 Headspace 32 와 애플 14 의 사이 20 (목록이 많은 기사 앱이라 32 는 너무 둥긂)
//
// [쓰는 법] AppType.headline · AppSpace.l · AppRadius.card 처럼 이름으로 쓴다 (숫자를 화면에 직접 쓰지 않기)
// ═══════════════════════════════════════════════════════════════
import 'package:flutter/material.dart';

/// 글자 · 선 · 채움 회색 단계 — (11/19) 애플 단계 구조에 Headspace 의 따뜻한 회색 값을 넣음
///   (이름은 그대로 두어 앱 전체가 한 번에 따뜻한 톤으로 바뀜)
class AppleGray {
  AppleGray._();
  static const Color page = Color(0xFFF9F5F1); // (11/23 리디자인_3 · Headspace 토큰) 크림 바탕 #F9F4F2 계열
  static const Color label = Color(0xFF1C2033); // 제목 · 본문 — (11/19 사용자 요청) 남색 한 방울 섞은 검정
  static const Color secondaryLabel = Color(0xFF63605D); // 설명 · 부제 — Headspace
  static const Color softLabel = Color(0xFF363B50); // 큰 제목 · 안내 문장 — 남색 기운 진회색
  static const Color tertiaryLabel = Color(0xFF8E8A84); // 시각 · 힌트 — 따뜻한 회색
  static const Color separator = Color(0xFFE2DED9); // 카드 테두리 · 구분선 — Headspace
  static const Color opaqueSeparator = Color(0xFFECE7E1); // 목록 줄 사이 얇은 선
  static const Color fill = Color(0xFFF2EDE7); // 입력칸 · 연한 칸 (따뜻한 연회색)
  static const Color chevron = Color(0xFFC6C1B9); // 목록 꺾쇠 › — Headspace
  static const Color tabInactive = Color(0xFF9A958E); // 탭바 안 고른 아이콘 · 글자
  static const Color tabBar = Color(0xFFF6F1EC); // 탭바 바탕
  static const Color tabBarTop = Color(0xFFF9F5F1); // 탭바 위 — 화면 바탕과 같은 크림 (선 없이 이어짐)
  static const Color tabBarBottom = Color(0xFFF1EBE4); // 탭바 아래 — 조금 더 짙은 크림
}

/// Headspace 식 납작 그림자 — 버튼이 살짝 떠 있는 느낌 (번지지 않고 아래로만 2px)
class AppShadow {
  AppShadow._();
  static const List<BoxShadow> button = [BoxShadow(color: Color(0x33413D45), offset: Offset(0, 2), blurRadius: 0)]; // Headspace 납작 그림자
  static const List<BoxShadow> card = [BoxShadow(color: Color(0x0F413D45), offset: Offset(0, 2), blurRadius: 0)]; // Headspace 납작 그림자
}

/// 글자 크기 단계 — iOS Dynamic Type 기본(Large) 값 · 굵기
class AppType {
  AppType._();
  // (11/19 Dembrandt · Headspace) 제목 = 굵게 700 · 자간 -3% · 줄 간격 1.15~1.2 / 본문 = 줄 간격 1.5 · 자간 -1%
  //   크기 단계는 애플 그대로 — 한글이라 Headspace 의 영문 글꼴(Apercu) 대신 Pretendard
  static const TextStyle largeTitle = TextStyle(fontSize: 34, height: 1.15, fontWeight: FontWeight.w700, letterSpacing: -1.0);
  static const TextStyle title1 = TextStyle(fontSize: 28, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.84);
  static const TextStyle title2 = TextStyle(fontSize: 22, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.66);
  static const TextStyle title3 = TextStyle(fontSize: 20, height: 1.2, fontWeight: FontWeight.w700, letterSpacing: -0.6);
  static const TextStyle headline = TextStyle(fontSize: 17, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: -0.3);
  static const TextStyle body = TextStyle(fontSize: 17, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: -0.17);
  static const TextStyle callout = TextStyle(fontSize: 16, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: -0.16);
  static const TextStyle subheadline = TextStyle(fontSize: 15, height: 1.5, fontWeight: FontWeight.w400, letterSpacing: -0.15);
  static const TextStyle footnote = TextStyle(fontSize: 13, height: 1.38, fontWeight: FontWeight.w400);
  static const TextStyle caption = TextStyle(fontSize: 12, height: 1.33, fontWeight: FontWeight.w400);
}

/// 애플 탭바 · 목록 줄 크기 (기사 앱이라 누르는 칸은 애플보다 조금 넉넉하게)
class AppSize {
  AppSize._();
  static const double button = 56; // (11/23) 큰 동작 버튼 높이 — 앱 전체 하나 (운행 시작 · 운행 종료 · 측정 시작 · 운행 재개 …)
  static const double rowMin = 50; // 목록 한 줄 최소 높이 (애플 44 → 장갑 · 운전 중 고려해 50)
  static const double tabIcon = 25; // 탭바 아이콘
  static const double tabLabel = 10.5; // 탭바 글자
}

/// 간격 — 4의 배수 (화면 좌우 여백은 l = 20)
class AppSpace {
  AppSpace._();
  static const double xxs = 4;
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 20;
  static const double xl = 24;
  static const double xxl = 32;
}

/// 둥글기 — 앱 전체가 이 값만 씀 ('제각각' 방지)
class AppRadius {
  AppRadius._();
  static const double small = 8; // (v2) 작은 칸
  static const double field = 12; // 입력칸
  static const double card = 16; // (11/23 사용자 요청) 카드 · 칸 · 카메라 · 시트 둥글기 모두 하나로
  static const double sheet = 16; // (v2) 시트 · 카메라 칸
  static const double pill = 999; // 알약 버튼 · 배지
}

/// 움직임 — 애플처럼 짧고 부드럽게
class AppMotion {
  AppMotion._();
  // (11/19 Dembrandt · Headspace) 0.15초 · 0.3초 · 0.4초 · 곡선 cubic-bezier(0.32, 0.94, 0.6, 1) — 빠르게 시작해 부드럽게 멈춤
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration normal = Duration(milliseconds: 300);
  static const Duration slow = Duration(milliseconds: 400);
  static const Curve curve = Cubic(0.32, 0.94, 0.6, 1);
}

/// (11/19) 캐릭터 일러스트 토큰 — Headspace 일러스트 느낌(납작한 색 몸 · 선 하나로 그린 얼굴)을 애플식으로 정리
///   - 몸: 그라데이션 · 빛 번짐 없이 한 가지 색 (네온 느낌 = AI 같다는 피드백)
///   - 얼굴: 진한 따뜻한 갈색 선 하나 · 끝이 둥근 선
///   - 바닥 그림자: 번지지 않는 납작한 타원 (Headspace 납작 그림자와 같은 생각)
///   - 단계 색은 UI 단계 색(초록 · 노랑 · 주황 · 빨강)과 같은 계열에서 조금 더 따뜻하고 부드럽게
class AppIllust {
  AppIllust._();
  static const List<Color> body = [
    Color(0xFF6CC291), // 0 정상 — 초록 (깨어 있고 웃는 얼굴)
    Color(0xFFFFC53D), // 1 주의 — 노랑 (눈이 반쯤 감김)
    Color(0xFFFF8A3D), // 2 휴식 권고 — 주황 (눈 감고 꾸벅 · z)
    Color(0xFFF2665A), // 3 긴급 — 빨강 (깜짝 놀란 눈)
  ];
  static Color bodyOf(int stage) => body[stage.clamp(0, 3)];
  static const Color ink = Color(0xFF1C2033); // 얼굴 선 — (11/23 사용자 요청) 모든 검정은 블랙 네이비
  static const Color cheek = Color(0xB3FF9E94); // 볼 (진한 분홍 · 몸 색과 섞여 탁해지지 않게)
  static const Color belly = Color(0x33FFFFFF); // 배 (몸 색 위 반투명 흰색)
  static const Color shadow = Color(0x14000000); // 바닥 납작 그림자
  static const double stroke = 3.2; // 얼굴 선 굵기 (그림 100 기준)
  static const Duration breath = Duration(milliseconds: 2400); // 숨 쉬듯 아주 살짝 커졌다 작아짐
  static const Duration breathFast = Duration(milliseconds: 900); // 긴급일 때는 빠르게

  // (11/19 · 동그란 해 캐릭터) 우리 단계 색(관리자 웹과 같은 초록 · 노랑 · 주황 · 빨강)에 투명도를 줌
  //   몸 = 85% 진하기 · 뒤 하늘 칸 = 18% · 작은 목록 그림 칸 = 14% → 흰 · 크림 바탕이 살짝 비쳐 부드러움
  static const List<Color> stageSolid = [Color(0xFF2E9E5B), Color(0xFFF2B01E), Color(0xFFF28C28), Color(0xFFD93025)];
  static Color orb(int stage) => stageSolid[stage.clamp(0, 3)].withValues(alpha: 0.85);
  static Color sky(int stage) => stageSolid[stage.clamp(0, 3)].withValues(alpha: 0.18);
  static Color thumb(int stage) => stageSolid[stage.clamp(0, 3)].withValues(alpha: 0.14);
  static const double heroRadius = 28; // 홈 큰 카드 둥글기 (Headspace 오늘 카드)
  static const double heroSky = 172; // 홈 큰 카드 위 하늘 칸 높이

  // (11/19 사용자 요청 · Headspace '오늘의 명상' 카드) 카드 바탕 = 한 단계 밝은 색 그라데이션, 캐릭터 = 단계 색 그라데이션
  //   2단계 = Headspace 카드 그대로 (노란 카드 + 주황 해) · 나머지 단계도 같은 규칙
  static const List<List<Color>> cardGradient = [
    [Color(0xFFE4F5EA), Color(0xFFC6EBD4)], // 0 정상 — 민트
    [Color(0xFFFFF4D2), Color(0xFFFFE6A6)], // 1 주의 — 크림 노랑
    [Color(0xFFFADB6A), Color(0xFFF6C646)], // 2 휴식 권고 — Headspace 노랑
    [Color(0xFFFFD5BC), Color(0xFFFFB896)], // 3 긴급 — 살구
  ];
  // (11/23 리디자인_3) 카드 바탕용 아주 연한 단계 색 — 흰색에서 이 색으로 살짝 물듦 (진한 파스텔 대신)
  static const List<Color> softTint = [Color(0xFFE6F5EC), Color(0xFFFFF6DC), Color(0xFFFFF0CC), Color(0xFFFFE6D9)];
  static const List<List<Color>> orbGradient = [
    [Color(0xFF86D3A3), Color(0xFF2E9E5B)],
    [Color(0xFFFFD866), Color(0xFFF2A81E)],
    [Color(0xFFF8A73E), Color(0xFFEC772E)],
    [Color(0xFFF78A7C), Color(0xFFD93025)],
  ];
}

/// (11/23 C · 기업용 리디자인) 시스템 상태 색 — Samsara 웹(samsara.com) CSS 에서 뽑은 토큰을 참고해 정리
///   Samsara 실제 값: 회색 단계 gray-50 #F5F4F1 · gray-500 #9C9890 · gray-900 #1C1917 / emerald-500 #01B665 /
///     gold-500 #F0BC00 / orange-500 #FF6319 / red #DF2036 / blue-500 #2A75D4 / 둥글기 md 6px · 알약 9999px / 숫자는 고정폭(Mono) 글꼴
///   - 유지: 우리 단계 색 0~3 (관리자 웹과 같은 팀 약속) · 남색 브랜드 · 크림 바탕 (Samsara gray-50 과 거의 같은 따뜻한 회색이라 그대로)
///   - 새로 도입: '연결 끊김 · 확인 중' 회색(Samsara gray-500) · 상태는 색 + 아이콘 + 글을 함께 · 숫자는 고정폭(tabular) 숫자
///   - 적용 안 함: Samsara 노랑 브랜드색 #FEAE0F (우리 '주의' 노랑과 헷갈림) · 각진 6px 둥글기 (우리 카드 20 유지)
class AppStatus {
  AppStatus._();
  static const Color normal = Color(0xFF2E9E5B); // 정상 · 준비 완료 · 감지 중 (단계 0 색)
  static const Color caution = Color(0xFFE0A100); // 주의 · 권한 필요 (단계 1 노랑을 글자로 읽히게 조금 진하게)
  static const Color warning = Color(0xFFF28C28); // 휴식 권고 (단계 2)
  static const Color danger = Color(0xFFD93025); // 위험 · 서버 끊김 (단계 3)
  static const Color info = Color(0xFF1F2A5C); // 연결됨 · 안내 (브랜드 남색)
  static const Color offline = Color(0xFF9C9890); // 확인 중 · 꺼짐 — Samsara gray-500
  static Color ink(Color c) => Color.lerp(c, const Color(0xFF1C2033), 0.25)!; // 알약 글자 — 같은 색을 조금 어둡게
  static const List<FontFeature> figures = [FontFeature.tabularFigures()]; // 숫자 폭 고정 (Samsara Mono 숫자 대신)
}
