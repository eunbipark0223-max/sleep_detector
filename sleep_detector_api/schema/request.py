# ═══════════════════════════════════════════════════════════════
# schema/request.py — 앱이 보내는 JSON 모양 (Pydantic)
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0
# 수업 원본: road_hazard_api/schema/request.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - 로그인 · 회원가입 · 채팅 · StatusUpdate — 수업 그대로 (StatusUpdate 설명만 졸음용 상태로)
#   - VoiceQuizAnswer — quiz_id · answer_text(STT 글자, 무응답이면 '') · answer_sec(무응답이면 null)
#   - DrivePing — perclos (기록용)
#
# [주의]
#   - 수업용 DirectReport · ReportSubmit 은 지운다
#   - /detect 는 사진 업로드라 JSON 이 아니라 Form 으로 받음 (detect.py)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
