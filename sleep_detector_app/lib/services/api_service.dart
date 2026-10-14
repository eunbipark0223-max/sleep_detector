// ═══════════════════════════════════════════════════════════════
// services/api_service.dart — 서버 통신 함수 모음
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/services/api_service.dart (🟡 수정, 사진 전송은 uploadProfilePhoto 방식)
//
// [이 파일이 하는 일]
//   - 모든 요청에 로그인 토큰(JWT) 붙이기 (수업 그대로)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - sendDetect(jpgBytes, reason, closedSec, perclos, eyeOpenProb, lat, lng) → SleepResponse   POST /detect
//   - sendPing(perclos) → DriveStatus   POST /drive/ping
//   - startDrive()   POST /drive/start
//   - sendCalibration(사진 파일)   POST /drive/calibrate
//   - startRest() · resumeDrive()   POST /drive/rest · /drive/resume
//   - submitAnswer(quizId, answerText, answerSec) → passed · nextQuiz · stage · message   POST /quiz/answer
//   - fetchMyEvents() → List<SleepEvent>   GET /events/my
//   - sendChat(message)   POST /chat  (수업 앱에서 빠져 있던 함수)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
