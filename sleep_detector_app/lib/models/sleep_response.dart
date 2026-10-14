// ═══════════════════════════════════════════════════════════════
// models/sleep_response.dart — POST /detect 응답 모양
// ═══════════════════════════════════════════════════════════════
// 담당: C   |   우선: P0
// 수업 원본: road_hazard_app/lib/models/detection_response.dart (🟡 이름 변경 + 수정)
//
// [이 파일이 하는 일]
//   - isSleep · stage · status · ear · eyeOpenProb · method · perclos · reason
//   - summary · guidance · driverVoice · sleepCount10min · regulations · eventId · earThreshold
//   - VoiceQuiz 클래스: quizId · type · speak · display · listenSec (정답 없음)
//   -   /quiz/answer 응답의 next_quiz 도 같은 VoiceQuiz 로 읽음
//   - Regulation 클래스는 수업 그대로 (title · source · content)
//
// [주의]
//   - 서버 기획안 9-3 의 칸 이름과 정확히 맞출 것 (snake_case → camelCase)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
