// ═══════════════════════════════════════════════════════════════
// services/eye_monitor.dart — ML Kit 눈 판정 (앱의 실시간 1차 판정)  ⭐ 핵심
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0 (개인 기준은 P1)
// 수업 원본: (없음, 🔴 신규) google_mlkit_face_detection 예제
//
// [이 파일이 하는 일]
//   - FaceDetector 옵션: enableClassification 켬 · performanceMode fast · minFaceSize 0.15 (윤곽 · 랜드마크 · 추적은 끔)
//   - 프레임마다: 분석 중이면 그 프레임은 버림(_busy) → 두 눈 평균 눈 뜸 확률
//   -   → 감김 / 뜸 / 모름 (확률 null · 얼굴 없음 = 모름, 감김으로 세지 않음)
//   - 연속 감김 1.5초 이상 → 미세수면 의심 (다시 떠야 다음 졸음을 셈)
//   - 최근 30초 PERCLOS 15% 이상 → 피로 누적 의심 (모름은 빼고 계산, 내려갔다 다시 넘어야 셈)
//   - 감긴 프레임을 잠깐 들고 있다가 의심이 확정되면 그 프레임을 넘김 (이미 눈을 뜬 뒤 찍지 않게)
//   - 모름이 3초 이어지면 카메라 확인 신호
//   - 사진 파일 1장 분석 (사진 1장 테스트 · KPI ① 측정) · 개인 기준 측정 (평소 확률 중간값 × 0.5, 0.2~0.4, 실패 시 0.3)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - processFrame(CameraImage image, CameraDescription camera)
//   - onSuspect(reason, closedSec, perclos, eyeOpenProb, CameraImage frame)  ← drive_screen 이 받는 콜백
//   - onCheckCamera()  ← drive_screen 이 받는 콜백
//   - analyzeFile(String path) → 눈 뜸 확률
//   - calibrate(List<String> paths) → 개인 기준
//   - currentPerclos (ping 에 실어 보낼 값) · close()
//
// [주의]
//   - 눈만 판단 — 고개 각도 · 미소 확률 · 하품은 쓰지 않는다
//   - C 의 drive_screen 과는 위 함수 이름만 약속하고 서로 파일을 고치지 않는다
//   - 실제 fps 는 폰마다 다름 → 시연 폰에서 측정, 판정은 프레임 수가 아니라 시간(초) 기준
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
