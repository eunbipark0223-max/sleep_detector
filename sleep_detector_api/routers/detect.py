# ═══════════════════════════════════════════════════════════════
# routers/detect.py — 졸음 의심 사진 확인 + 운행 API  ⭐ 핵심
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0 (퀴즈 연결은 P1)
# 수업 원본: road_hazard_api/routers/detect.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - POST /detect — 앱이 '졸음 의심' 때만 보냄 (사진 1장 + reason · closed_sec · perclos · eye_open_prob · 위도 · 경도, JWT 필수)
#   -   ① 로그인 · 사진 확인 (uploads/tmp/ 에 잠깐)
#   -   ② 확인 판정 face_service → 취소면 사진 삭제 후 바로 응답 (is_sleep false, AI 안 부름)
#   -   ③ sleep_state 에 졸음 1회 → 규칙 단계   ④ LLM 요약   ⑤ RAG 규정
#   -   ⑥ Agent 단계 · 안내문 · 보고서 · driver_voice → 바닥 · 천장 검사 + 음성 보고 숫자 검사
#   -   ⑦ 저장 (사진 uploads/events/ + DB 1줄)   ⑧ 음성 퀴즈 1문제 (경고 저장 뒤, quiz_id ↔ event_id 기억)
#   -   reason 이 비어 있으면 '사진 1장 테스트' → 서버 EAR 만으로 판정
#   - POST /drive/start — 운행 시작: 졸음 기록 · 단계 0, 연속 운전 시간 시작
#   - POST /drive/calibrate — 개인 기준 측정 사진 1장씩, 5장 모이면 서버 개인 기준 EAR 완성
#   - POST /drive/ping — 30초마다 (사진 없음). 응답: stage · status · drive_min · rest_due · rest_message
#   - POST /drive/rest — [정차했어요] → 휴식 시작 시각 기록
#   - POST /drive/resume — [운행 재개] → 15분 지났는지 서버 시각으로 검사 → 2단계면 1단계, 상태 '휴식완료'
#
# [주의]
#   - 응답 모양은 기획안 9-3 (졸음) · 9-5 (ping) 그대로 — 앱 sleep_response.dart · drive_status.dart 와 맞춰야 함
#   - 숫자는 _normalize 로 int / float 확정해서 보냄 (수업에서 배운 '5' 문자열 사고 방지)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
