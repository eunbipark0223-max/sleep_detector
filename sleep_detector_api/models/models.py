# ═══════════════════════════════════════════════════════════════
# models/models.py — DB 테이블 2개 (users · sleep_events)
# ═══════════════════════════════════════════════════════════════
# 담당: 팀장   |   우선: P0
# 수업 원본: road_hazard_api/models/models.py (🟡 수정)
#
# [이 파일이 하는 일]
#   - User — 수업 그대로 (role 값 user / admin 도 그대로)
#   - Hazard → SleepEvent (테이블 sleep_events) — 졸음 경고 1건
#   -   칸: id · user_id · stage · ear · eye_closed_prob · method(ear/cnn/mlkit) · reason(microsleep/perclos/rest_overdue/no_response)
#   -       perclos · summary · guidance · report(JSON 문자열: eye · driving_quiz · rest 포함) · photo_path
#   -       latitude · longitude · status(미확인/확인/조치완료/휴식완료) · created_at
#
# [주의]
#   - 칸을 새로 추가하지 않는다. 새 정보는 report JSON 안에 넣는다 (파일 구조 3장)
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════
