# ml_models/ — 서버가 쓰는 모델 파일

| 파일 | 담당 | 내용 |
| --- | --- | --- |
| `face_landmarker.task` | A | MediaPipe 1.1.0 Face Landmarker 모델. **1주차에 A가 받아서 넣기** (MediaPipe 공식 모델 페이지) |
| `eye_cnn.pt` | B | CNN 학습 결과 (`notebooks/eye_cnn.ipynb`). CNN 채택 시에만 (`config.USE_CNN = True`) |
| `eye_cnn_aihub.pt` | B | AI-Hub 미세조정 모델 (`eye_cnn.ipynb` 3번). 웹캠 도구 비교용 · 11/4 채택 결정 전까지 |

- `.pt` 두 개는 **A · B · 팀장 PC에만** 둡니다 (torch 설치: `tools/requirements-cnn.txt`). C · D는 없어도 서버가 EAR만으로 돌아갑니다.
- `.pt` · `.task` 는 `.gitignore` 에 들어 있어 GitHub에 안 올라갑니다 → 구글 드라이브로만 주고받기.

- 50MB 넘는 파일은 GitHub에 올리지 않고 Google Drive로 공유합니다.
- 앱 쪽 ML Kit 모델은 여기 없습니다 (`google_mlkit_face_detection` 패키지 안에 들어 있음).
