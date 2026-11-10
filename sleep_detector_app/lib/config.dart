// ═══════════════════════════════════════════════════════════════
// config.dart — 앱 기준 숫자 (눈 판정 · ping 간격)
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0
// 수업 원본: (신규) 서버 config.py 모양
//
// [이 파일이 하는 일]
//   - 눈 판정을 앱이 하므로 판정 숫자는 여기 한곳에만 둔다
//   - eyeClosedProb = 0.4      두 눈 평균 눈 뜸 확률이 이보다 작으면 '감김' (개인 기준이 없을 때, 10/27 0.3 → 0.2, 10/28 0.25, 11/02 0.4 확정)
//   - smileOpenProb = 0.8      (🆕 11/04) 웃음 확률이 이 이상이면 감김으로 세지 않음
//   - closedSec = 1.5          감김이 이만큼 이어지면 미세수면 의심
//   - microsleepPhotos = 3 · photoGapSec   (🆕 11/09) 눈 감김 미세수면 때 넘기는 사진 수 · 보관 간격
//   - graceAfterWarningSec = 10   (🆕 11/10) 경고 뒤 눈을 한 번 뜨면 그때부터 미세수면 · 숙임 의심을 안 내는 시간
//   - eyeResendOn              (🆕 11/10) 눈 감김을 서버가 취소했는데 계속 감으면 사진 없이 한 번 더
//   - halfCheckOn (기본 꺼짐) · halfCheckSec = 10   (🆕 11/10) 반쯤 감은 눈 확인 사진 → onHalfCheck → 서버 EAR (출발 전 뜬 눈 × 0.85)
//   - perclosWindowSec = 30    PERCLOS 계산 구간
//   - perclosThreshold = 0.15  감김 비율이 이 이상이면 피로 누적 의심
//   - unknownSec = 3           얼굴 없음 · 모름이 이만큼 이어지면 '카메라를 확인하세요'
//   - minFaceSize = 0.15       ML Kit 최소 얼굴 크기 (조수석 · 뒷좌석 무시)
//   - calibSec = 5 · calibRatio = 0.5 · calibMin = 0.2 · calibMax = 0.4 · calibMinFaces = 3   개인 기준
//   - contourEarOn · useContourEar · earClosed   (🆕 10/27) ML Kit 눈 윤곽 점으로 폰에서 EAR — 반쯤 감은 눈용
//   - headResendSec = 6        (🆕 11/04) 서버 취소 뒤 계속 숙이고 있으면 한 번 더 보내는 시간
//   - headRuleOn · headDownDeg = 6 · headDownSec = 3 · headBaseSec · headBaseMinFrames   (🆕 10/28) 고개 숙임 3초 → 미세수면 의심
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
  //   11/02 0.4 확정: 뜬 눈 확률이 0.99 라 개인 기준이 5명 모두 상한 0.4 → 측정 성공 · 실패와 상관없이 같은 기준으로 통일
  //   KPI ① (0.25 → 0.4): 기본 놓침 0/159 · 오탐 0/160 같음, 반쯤 감음 42 → 49/109, 선글라스 놓침 10 → 8/10, 고개 돌림 오탐 0 → 1/20 (서버가 취소)
  static const double eyeClosedProb = 0.4;

  // 웃음 확률이 이 이상이면 감김으로 세지 않음 — 크게 웃으면 눈이 가늘어져 오판 (11/03 웹캠 확인)
  //   11/05 팀 사진 · 영상 (5명, 밝은 곳, 시연 확인용): 웃는 얼굴 96장 앱 오판 24 → 0 (0.7 · 0.8 · 0.9 모두 같음), 감은 눈 159장 중 규칙으로 빠지는 수 0 → 0.8 유지
  //   웃으면서 눈을 완전히 감는 경우는 시험 안 함
  static const double smileOpenProb = 0.8;

  // 미세수면: 연속 감김 시간 기준 (초)
  static const double closedSec = 1.5;

  // 🆕 (11/09) 미세수면(눈 감김) 의심 때 넘기는 사진 수 — 감김 처음 · 가운데 · 마지막 (팀장 3장 검토, 11/07 1장 vs 3장 시험)
  //   감는 동안 프레임을 photoGapSec 간격으로만 들고 있음 (1.5초 → 최대 약 8장, 의심 뒤 · 눈 뜨면 바로 비움)
  //   고개 숙임 · PERCLOS 는 1장, 재전송은 사진 없음 (11/09 팀장 결정: 숙임은 얼굴 없는 사진이 많고 재전송이 있음, PERCLOS 는 바로 확정 · 사진은 기록용)
  static const int microsleepPhotos = 3;
  static const double photoGapSec = 0.2;

  // 피로 누적(PERCLOS): 최근 30초 창 및 15% 임계값
  static const int perclosWindowSec = 30;
  static const double perclosThreshold = 0.15;

  // 🆕 (11/10 팀장 결정) 경고 화면에서 돌아온 뒤 (reset) 눈을 한 번이라도 뜬 프레임이 나오면 → 그때부터 이만큼은 미세수면 · 고개 숙임 의심을 안 냄
  //   한 번도 안 뜨고 계속 감고 있으면 봐주지 않음 (지금처럼 1.5초 뒤 바로 의심) · PERCLOS 는 30초 창을 다시 채우니까 그대로
  //   전에는 경고를 닫고 눈을 비비기만 해도 바로 다음 의심 → 몇 초 만에 1 → 2 → 3단계 (팀장)
  static const double graceAfterWarningSec = 10;

  // 🆕 (11/10 팀장 결정, 11/05 빈틈) 눈 감김 의심을 서버가 취소했는데 계속 감고 있으면 → 고개 숙임처럼 사진 없이 한 번 더 (headResendSec 기준)
  //   재생 기록 (11/04 ~ 11/09, 평소 운전 · 거치 약 76분): 후보 0번. 후보는 모두 일부러 감기 · 실눈 · 숙이기 구간
  //   (C 실눈 유지 11/05 3.8분: 후보 6번 — 서버가 취소했을 때만 실제로 나감)
  static const bool eyeResendOn = true;

  // 🆕 (11/10 팀장 결정) 반쯤 감은 눈 확인 — 기본 꺼짐, 11/11 시험 기준을 넘으면 켬 (빌드 때 --dart-define=HALF_CHECK=true 로도 켬)
  //   ML Kit 은 반쯤 감은 눈을 0.73 ~ 0.99 (뜸) 로 봐서 의심 자체가 안 감
  //   눈을 뜬 상태 (감김 · 숙임 · 웃음 아님) 면 halfCheckSec 마다 사진 1장 → onHalfCheck → 서버 EAR 을 출발 전 측정 뜬 눈 EAR 과 비교
  //   서버: × 0.85 미만 = 반쯤 (face_service.check_half) · 최근 4번 중 3번이면 피로 확정 (sleep_state.add_half). 사진은 판정 뒤 바로 지움
  //   출발 전 측정 실패 (얼굴 3장 미만) 면 반쯤 판정 안 함
  //   팀 영상 프레임 (눈 폭 약 19px, 5명, 시연 확인용): 평소 × 0.85 미만 → 반쯤 50/59 · 뜬 눈 오탐 0/60. 폰 EAR 은 0 ~ 1/8 이라 못 씀
  //   켜는 기준 (11/11): 팀장 실눈 40초 3번 중 2번 이상 판정 · 평소 운전 2명 × 10분 0번. 1시간에 약 360장 (1장 약 40KB)
  static const bool halfCheckOn = bool.fromEnvironment('HALF_CHECK', defaultValue: false);
  static const double halfCheckSec = 10;

  // 얼굴 없음 / 모름(null) 연속 허용 시간 (초)
  static const double unknownSec = 3.0;

  // ML Kit 얼굴 최소 크기
  static const double minFaceSize = 0.15;

  // 개인 기준 캘리브레이션 설정 (5초, 중간값 * 0.5, 범위 0.2 ~ 0.4)
  static const int calibSec = 5;
  static const double calibRatio = 0.5;
  static const double calibMin = 0.2;
  static const double calibMax = 0.4;
  static const int calibMinFaces = 3; // 눈 확률이 나온 사진이 이 장 수 미만이면 측정 실패 (서버 CALIB_MIN_FACES 와 같게)

  // 🆕 폰 EAR (ML Kit 눈 윤곽 점 16개) — 반쯤 감긴 눈은 뜸 확률이 높게 나와 사진이 안 가는 문제 보완
  //   contourEarOn  : 윤곽 점을 받아 EAR 계산 (측정 · 화면 표시). 켜면 ML Kit 이 느려짐 → 처리 시간(ms) 측정
  //   useContourEar : EAR 을 '감김' 판정에도 씀 (뜸 확률 < 기준 또는 EAR < earClosed)
  //                   🔴 시연 폰에서 ① 처리 속도 ② 반쯤 감은 눈 EAR 이 뜬 눈보다 확실히 낮은지 확인한 뒤에만 true
  //   earClosed     : 출발점. ML Kit 윤곽 EAR 은 서버 MediaPipe EAR 과 숫자 크기가 다를 수 있음 → 측정 후 확정
  //   11/02 끔: useContourEar 를 안 쓰기로 해서 계산만 남아 있었음. 시연 폰 1번씩 비교 86ms · 9.5fps → 76ms · 10.1fps
  //   (폰 EAR 을 다시 재려면 true — tools/eye_measure_main.dart 의 phone_ear 칸이 이 값으로 나옴)
  static const bool contourEarOn = false;
  static const bool useContourEar = false;
  static const double earClosed = 0.2;
  // 눈 폭(눈꼬리 사이)이 이보다 작으면 폰 EAR 을 안 씀 — 윤곽 점이 정수 픽셀이라 작은 눈은 뜸/감음 구분이 안 됨
  //   (모의 시험: 폭 30px 은 뜸 0.33 · 반쯤 0.13 · 감음 0.07, 폭 12px 은 0.41 · 0.37 · 0.33)
  static const double minEyeWidthPx = 20;

  // 🆕 고개 숙임 규칙 (10/28 CNN 채택 회의) — 고개를 푹 숙인 채 headDownSec 이어지면 미세수면 의심
  //   headDownSec   : 숙임이 이만큼 이어져야 의심 (눈 감김 1.5초보다 김). PERCLOS 에는 눈 감김만 넣음
  //                   10/29 시연 폰 시험: 계기판 · 내비 보기 1.0~2.3초 · 졸아서 숙이기 3.8~7.4초
  //                   → 1.5초로는 계기판 볼 때 경고 3번 → 3초 (팀 결정)
  //   headDownDeg   : 평소 고개 각도(ML Kit headEulerAngleX)보다 이만큼 숙이면 숙임. ML Kit 은 숙이면 X 가 내려감
  //                   10/28 KPI ① 측정: 평소 눈 뜬 프레임 최대 3.4° · 고개 돌림 최대 4.1° / 고개 숙임 8.0~20.5° → 가운데 6°
  //   headBaseSec   : 평소 각도 = 최근 이 시간 동안 '눈 뜨고 숙이지 않은' 프레임 각도의 중간값 (폰 위치 · 사람마다 달라서 고정값 못 씀)
  //   headBaseMinFrames : 평소 각도를 낼 최소 프레임 수 (출발 직후 · 자세를 바꾼 직후에는 규칙을 쉼)
  //   웃음 확률 smileOpenProb 이상인 프레임은 숙임 · 평소 각도에 넣지 않음 (11/09 팀장 요청 — 정면에서 웃을 때 숙임 3초로 잡힘, 11/05)
  //   한계 (발표): 내비 등을 3초 넘게 내려다봐도 경고 · 고개는 그대로 두고 눈만 내리깔면 각도로는 못 잡음 (ML Kit 이 '감음' 으로 봄)
  static const bool headRuleOn = true;
  static const double headDownDeg = 6.0;
  static const double headDownSec = 3.0;
  static const double headResendSec = 6.0; // 숙임 시작부터 이만큼 지나도 서버 취소 뒤 얼굴이 정상으로 안 돌아오면 사진 없이 한 번 더 (11/04, 재시험 후 확정)
  static const double headUpResetSec = 0.5; // 이만큼 계속 고개를 들어야 숙임 시간을 처음부터 (흔들림 1~2프레임은 숙임으로 이어 셈)
  static const int headBaseSec = 60;
  static const int headBaseMinFrames = 20;

  // 서버 ping 간격 (초)
  static const int pingSec = 30;

  // 서버 주소 — 에뮬레이터 기본값. 시연 폰은 flutter run --dart-define=API_BASE_URL=http://PC주소:8000
  // (10/27 팀장 추가: 머리말에 약속된 값. 앱의 모든 서비스가 이 값 하나를 쓰도록 맞출 예정)
  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000');
}