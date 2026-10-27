// ═══════════════════════════════════════════════════════════════
// config.dart — 앱 기준 숫자 (눈 판정 · ping 간격)
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0
// 수업 원본: (신규) 서버 config.py 모양
//
// [이 파일이 하는 일]
//   - 눈 판정을 앱이 하므로 판정 숫자는 여기 한곳에만 둔다
//   - eyeClosedProb = 0.2      두 눈 평균 눈 뜸 확률이 이보다 작으면 '감김' (개인 기준이 없을 때, 10/27 팀 결정 0.3 → 0.2)
//   - closedSec = 1.5          감김이 이만큼 이어지면 미세수면 의심
//   - perclosWindowSec = 30    PERCLOS 계산 구간
//   - perclosThreshold = 0.15  감김 비율이 이 이상이면 피로 누적 의심
//   - unknownSec = 3           얼굴 없음 · 모름이 이만큼 이어지면 '카메라를 확인하세요'
//   - minFaceSize = 0.15       ML Kit 최소 얼굴 크기 (조수석 · 뒷좌석 무시)
//   - calibSec = 5 · calibRatio = 0.5 · calibMin = 0.2 · calibMax = 0.4   개인 기준
//   - contourEarOn · useContourEar · earClosed   (🆕 10/27) ML Kit 눈 윤곽 점으로 폰에서 EAR — 반쯤 감은 눈용
//   - pingSec = 30             서버 config.PING_SEC 과 같은 값
//   - baseUrl                  서버 주소 (에뮬레이터는 http://10.0.2.2:8000)
//
// [주의]
//   - 모두 출발점 — 팀 사진 · 시연 폰으로 측정 후 A 가 바꾼다 (KPI ①)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
class AppConfig {
  // 눈 감김 판정 기본 기준 (개인 기준 측정 전/실패 시 기본값)
  //   ML Kit 뜸 확률은 완전히 감음(≈0.01) · 뜸(≈0.99) 양 끝으로 갈려서 0.2 · 0.3 결과가 거의 같음 (ML Kit 동작 확인, 예비 시험)
  static const double eyeClosedProb = 0.2;

  // 미세수면: 연속 감김 시간 기준 (초)
  static const double closedSec = 1.5;

  // 피로 누적(PERCLOS): 최근 30초 창 및 15% 임계값
  static const int perclosWindowSec = 30;
  static const double perclosThreshold = 0.15;

  // 얼굴 없음 / 모름(null) 연속 허용 시간 (초)
  static const double unknownSec = 3.0;

  // ML Kit 얼굴 최소 크기
  static const double minFaceSize = 0.15;

  // 개인 기준 캘리브레이션 설정 (5초, 중간값 * 0.5, 범위 0.2 ~ 0.4)
  static const int calibSec = 5;
  static const double calibRatio = 0.5;
  static const double calibMin = 0.2;
  static const double calibMax = 0.4;

  // 🆕 폰 EAR (ML Kit 눈 윤곽 점 16개) — 반쯤 감긴 눈은 뜸 확률이 높게 나와 사진이 안 가는 문제 보완
  //   contourEarOn  : 윤곽 점을 받아 EAR 계산 (측정 · 화면 표시). 켜면 ML Kit 이 느려짐 → 처리 시간(ms) 측정
  //   useContourEar : EAR 을 '감김' 판정에도 씀 (뜸 확률 < 기준 또는 EAR < earClosed)
  //                   🔴 시연 폰에서 ① 처리 속도 ② 반쯤 감은 눈 EAR 이 뜬 눈보다 확실히 낮은지 확인한 뒤에만 true
  //   earClosed     : 출발점. ML Kit 윤곽 EAR 은 서버 MediaPipe EAR 과 숫자 크기가 다를 수 있음 → 측정 후 확정
  static const bool contourEarOn = true;
  static const bool useContourEar = false;
  static const double earClosed = 0.2;
  // 눈 폭(눈꼬리 사이)이 이보다 작으면 폰 EAR 을 안 씀 — 윤곽 점이 정수 픽셀이라 작은 눈은 뜸/감음 구분이 안 됨
  //   (모의 시험: 폭 30px 은 뜸 0.33 · 반쯤 0.13 · 감음 0.07, 폭 12px 은 0.41 · 0.37 · 0.33)
  static const double minEyeWidthPx = 20;

  // 서버 ping 간격 (초)
  static const int pingSec = 30;

  // 서버 주소 — 에뮬레이터 기본값. 시연 폰은 flutter run --dart-define=API_BASE_URL=http://PC주소:8000
  // (10/27 팀장 추가: 머리말에 약속된 값. 앱의 모든 서비스가 이 값 하나를 쓰도록 맞출 예정)
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
}