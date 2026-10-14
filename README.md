# sleep_detector — AI 졸음 감지 · 능동형 안전 알림 앱 (가칭 “졸음 가드”)

KWU 부트캠프 파이널 프로젝트 (5인). 기획 · 역할 · 파일 구조는 노션 문서를 봅니다.
(「파이널 프로젝트 최종 기획안 10.13」 · 「파일 구조」 · 「역할 분담 일정」)

> 🔴 **지금 저장소는 파일 구조(틀)만 있습니다.** 각 파일 맨 위 주석에 **담당 · 우선순위 · 참고할 수업 파일 · 하는 일**이 적혀 있으니,
> 자기 파일을 열고 주석을 읽은 뒤 수업 파일을 복사해 시작하세요. 주석에 적힌 **함수 이름 · JSON 칸 이름은 약속**이라 바꾸지 않습니다.

```
sleep_detector/
├── sleep_detector_api/   서버 (FastAPI + MySQL)  — PyCharm 으로 이 폴더를 연다
├── sleep_detector_app/   기사 앱 (Flutter)       — Android Studio 로 이 폴더를 연다
└── notebooks/            Colab 노트북 (CNN 학습, KPI 측정)
```

## 한눈에 — 어디서 무엇을 하나

```
[앱]  카메라 영상 → eye_monitor.dart (ML Kit 눈 뜸 확률 → 연속 감김 1.5초 / PERCLOS 30초)
        → 졸음 의심이면 그 순간 사진 1장 → POST /detect
        → 30초마다 POST /drive/ping (사진 없음)
[서버] /detect → face_service (EAR / CNN 확인) → sleep_state (단계) → LLM → RAG → Agent → DB → 음성 퀴즈
```

## 서버 실행
```
cd sleep_detector_api
py -3.11 -m venv venv
venv\Scripts\activate
pip install -r requirements.txt
copy .env.example .env      ← 본인 값 입력 (DB 비밀번호, SECRET_KEY, GEMINI_API_KEY)
python main.py              → http://127.0.0.1:8000/docs   (main.py 를 작성한 뒤부터 실행됨)
```
MySQL 에 빈 DB `sleep_detector` (utf8mb4) 가 있어야 합니다. 테이블은 서버가 자동으로 만듭니다.

## 앱 실행
```
cd sleep_detector_app
flutter pub get
flutter run                 (에뮬레이터 Pixel_7_API_34 또는 안드로이드 실기기 — main.dart 를 작성한 뒤부터 실행됨)
```
- `android/app/google-services.json` 은 GitHub 에 없습니다. 팀장에게 따로 받으세요.
- 안드로이드 패키지 이름은 구글 로그인(Firebase) 설정 때문에 `com.example.road_hazard_app` 그대로 둡니다. 화면에 보이는 앱 이름만 “졸음 가드”.
- ML Kit · STT 는 **실기기(시연용 안드로이드 폰)** 에서 꼭 다시 시험합니다.

## 🔐 절대 올리지 않는 것
`.env` · `kaggle.json` · `google-services.json` · `uploads/`(얼굴 사진) · 팀 촬영 사진 · MRL 데이터 · 50MB 넘는 모델 파일
