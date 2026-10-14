# ml_models/ — 서버가 쓰는 모델 파일

| 파일 | 담당 | 내용 |
| --- | --- | --- |
| `face_landmarker.task` | A | MediaPipe 1.1.0 Face Landmarker 모델. **1주차에 A가 받아서 넣기** (MediaPipe 공식 모델 페이지) |
| `eye_cnn.pt` | B | CNN 학습 결과 (`notebooks/eye_cnn.ipynb`). CNN 채택 시에만 (`config.USE_CNN = True`) |

- 50MB 넘는 파일은 GitHub에 올리지 않고 Google Drive로 공유합니다.
- 앱 쪽 ML Kit 모델은 여기 없습니다 (`google_mlkit_face_detection` 패키지 안에 들어 있음).
