// ═══════════════════════════════════════════════════════════════
// utils/camera_image_utils.dart — 카메라 영상 변환 도우미
// ═══════════════════════════════════════════════════════════════
// 담당: A   |   우선: P0
// 수업 원본: (없음, 🔴 신규) google_mlkit_commons 공식 예제
//
// [이 파일이 하는 일]
//   - CameraImage → InputImage (ML Kit 에 넣는 모양). Android(nv21) 먼저, iOS(bgra8888) 는 나중
//   - CameraImage → jpg (image 패키지) — 졸음 의심 때만 호출 (매 프레임 변환하면 느림)
//
// [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
//   - toInputImage(CameraImage image, CameraDescription camera) → InputImage?
//   - toJpg(CameraImage image) → Uint8List
//
// [주의]
//   - 학생들이 가장 많이 막히는 곳 — 공식 예제 코드를 그대로 가져다 쓴다
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
