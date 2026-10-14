# sleep_detector_app — 기사 앱 (Flutter, 가칭 “졸음 가드”)

Android Studio 로 **이 폴더**를 엽니다. 파일마다 맨 위 주석에 담당 · 하는 일 · 참고할 수업 파일이 있습니다.

| 폴더 | 내용 |
| --- | --- |
| `lib/config.dart` | 앱 기준 숫자 (눈 판정 · ping 간격) — A |
| `lib/services/` | `eye_monitor`(ML Kit 눈 판정, A) · `api_service`(서버 통신, C) · `voice_service`(TTS · STT, C) · `auth_service`(로그인) |
| `lib/utils/` | `camera_image_utils` (영상 → ML Kit 입력 · jpg, A) |
| `lib/models/` | `/detect` · `/drive/ping` 응답, 경고 1건 |
| `lib/screens/` | 화면 15개 (운행 · 경고 · 휴식 · 측정 · 사진 1장 테스트 등) |

```
flutter pub get
flutter run
```
