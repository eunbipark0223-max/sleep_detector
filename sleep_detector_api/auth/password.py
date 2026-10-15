# ═══════════════════════════════════════════════════════════════
# auth/password.py — 비밀번호 암호화 · 확인 (argon2)
# ═══════════════════════════════════════════════════════════════
# 담당: -   |   우선: P0
# 수업 원본: road_hazard_api/auth/password.py (🟢 그대로 복사)
#
# [이 파일이 하는 일]
#   - hash_password(평문) → 암호문 / verify_password(평문, 암호문) → 맞는지
#
# 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
# ═══════════════════════════════════════════════════════════════

from pwdlib import PasswordHash

password_hasher = PasswordHash.recommended()

def hash_password(plain_password: str) -> str:
    return password_hasher.hash(plain_password)

def verify_password(plain_password: str, hashed_password: str) -> bool:
    return password_hasher.verify(plain_password, hashed_password)
