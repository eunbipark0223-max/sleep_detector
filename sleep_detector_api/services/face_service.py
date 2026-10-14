# ═══════════════════════════════════════════════════════════════
# services/face_service.py — 서버 확인 판정 (MediaPipe EAR · CNN)  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: A   |   우선: P0
# 수업 원본: road_hazard_api/services/yolo_service.py (🟡 이름 변경 + 수정, _mock / _real / _normalize 뼈대 그대로)
#
# [이 파일이 하는 일]
#   - 앱이 보낸 의심 사진에서 MediaPipe Face Landmarker 로 눈 점 12개 → EAR 계산 (항상)
#   -   왼눈 33·160·158·133·153·144  /  오른눈 362·385·387·263·373·380
#   - USE_CNN 이면 눈만 잘라 흑백 64×64 → eye_cnn.pt → 감았을 확률
#       (자르기 · 흑백 · 크기는 services/eye_preprocess.py 의 crop_eye → prep_eye 사용, 학습과 같은 함수)
#   - 결과: 감음 / 뜸 / 얼굴 없음 + ear · eye_closed_prob · method
#   - 확인 규칙: microsleep → 서버도 감음이면 확정 / 확실히 뜸이면 취소 / 얼굴 없음이면 앱 판단대로(method mlkit)
#   -           perclos → 앱 숫자로 확정 (method mlkit, 사진은 기록용)
#   - 개인 기준 EAR: /drive/calibrate 사진 5장 중간값 × 0.7 (0.15~0.25)
#
# [만들 것 (이름 약속 — 다른 파일이 이 이름으로 부름)]
#   - check_eyes(image_path, user_id) → 판정 결과 dict
#   - calibrate(image_paths) → 개인 기준 EAR
#
# [주의]
#   - mediapipe 1.1.0 에는 예전 mp.solutions.face_mesh 가 없음 → ml_models/face_landmarker.task 로 Face Landmarker 사용
#   - 가짜(_mock): 파일 이름에 closed → 감음, noface → 얼굴 없음
#   - 먼저 사진 위에 점을 그려서 눈에 찍히는지 확인
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
