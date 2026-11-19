# ═══════════════════════════════════════════════════════════════
# tools/send_test_mail.py — 구글 SMTP 설정이 맞는지 시험 메일 한 통 보내기 (11/19)
# ═══════════════════════════════════════════════════════════════
# 서버 코드가 아니라 PC 에서 돌리는 도구. 서버와 같은 .env(SMTP_USER · SMTP_PASSWORD)를 읽는다.
#
# [실행] (sleep_detector_api 폴더)
#   venv\Scripts\python tools/send_test_mail.py 받을이메일@gmail.com
#
# [주의]
#   - 진짜로 메일이 한 통 나간다 (받는 사람에게 인증번호 모양의 시험 메일). 내 이메일로 보내서 확인할 것
#   - 계정 · 앱 비밀번호는 화면에 찍지 않는다 (어느 칸이 비었는지만 알려 줌)
#   - 서버의 하루 발송 한도(횟수 기록)는 서버 메모리에만 있어서 이 도구는 거기에 세지 않는다
# ═══════════════════════════════════════════════════════════════
import os
import sys

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, BASE)
os.chdir(BASE)

import config  # noqa: E402
from services import mail_service  # noqa: E402


def main() -> int:
    if len(sys.argv) != 2 or "@" not in sys.argv[1]:
        print("사용법: python tools/send_test_mail.py 받을이메일@gmail.com")
        return 2
    to = sys.argv[1].strip()

    missing = [n for n, v in (("SMTP_USER", config.SMTP_USER), ("SMTP_PASSWORD", config.SMTP_PASSWORD)) if not v]
    if missing:
        print(f"❌ .env 에 {', '.join(missing)} 가 비어 있어요 (.env.example 의 '메일 발송' 칸 참고)")
        return 1

    print(f"보내는 곳: {config.SMTP_HOST}:{config.SMTP_PORT}  ·  받는 사람: {mail_service.mask_email(to)}")
    try:
        mail_service.send_verification_code(to, "123456", 5)
    except mail_service.MailError as e:
        print(f"❌ 실패: {e.message}\n   (위의 ⚠️ [mail] 줄에 이유가 있어요. 앱 비밀번호 · 2단계 인증 · 포트 · 방화벽 확인)")
        return 1
    print("✅ 보냈어요. 받은편지함(스팸함도)에서 '[졸음 가드] 이메일 인증번호' 를 확인하세요")
    return 0


if __name__ == "__main__":
    sys.exit(main())
