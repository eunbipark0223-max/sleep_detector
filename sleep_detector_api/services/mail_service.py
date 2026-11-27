# ═══════════════════════════════════════════════════════════════
# services/mail_service.py — 구글 SMTP 메일 발송 (11/19)
# ═══════════════════════════════════════════════════════════════
# [구조] 앱(Flutter) → 우리 서버 API → 이 파일 → 구글 SMTP
#   - 앱은 서버 API 만 부른다. SMTP 연결 · 계정 · 앱 비밀번호는 서버 안에서만 쓴다
#     (앱 파일은 디컴파일로 다 뜯어볼 수 있어서, 앱에 계정을 넣으면 털리고 → 스팸에 악용 → 구글이 계정을 정지한다)
#   - 계정 · 앱 비밀번호는 .env (SMTP_USER · SMTP_PASSWORD) → config.py 로만 읽는다. 코드 · GitHub · 로그에 남기지 않는다
#
# [이 파일이 하는 일]
#   - is_enabled()                       : SMTP_USER · SMTP_PASSWORD 가 .env 에 있는지 (없으면 시연용으로 동작)
#   - reserve(email) / release(ticket)   : 보내기 전에 횟수 확인 (같은 이메일 1분 간격 · 1시간 5번 · 서버 하루 100통). 보내기 실패하면 release 로 돌려 줌
#   - send_verification_code(email, ...) : 인증번호 메일 (글자판 + HTML)
#   - send_mail(to, subject, text, html) : 구글 SMTP 로 한 통 보냄 (STARTTLS 필수 — 암호화 안 되면 로그인도 안 함)
#
# [주의]
#   - 표준 라이브러리(smtplib)만 써서 requirements.txt 추가 없음
#   - 횟수 기록은 메모리에만 있어서 서버를 다시 켜면 0 (employee_service 의 인증 기록과 같은 방식)
#   - 개인 구글 계정은 하루 500통까지 → 넘으면 구글이 막는다. MAIL_DAILY_LIMIT(기본 100)으로 그 앞에서 먼저 멈춤
#   - 🔴 Railway 는 Free · Trial · Hobby 요금제에서 SMTP 포트(465 · 587)를 막는다고 함 → 배포 서버에서 메일이 안 가면 요금제부터 확인
#     (메일 서비스를 바꿔야 하면 send_mail 한 함수만 고치면 된다. 호출하는 쪽은 그대로)
# ═══════════════════════════════════════════════════════════════
import html
import smtplib
import ssl
import threading
import time
from email.message import EmailMessage
from email.utils import formataddr, formatdate, make_msgid

import config


# ── 오류 ────────────────────────────────────────────────────────
class MailError(Exception):
    """메일 쪽 오류의 뿌리. message 는 앱 화면에 그대로 보여 줘도 되는 문구 (계정 · 서버 내부 정보는 담지 않음)"""
    def __init__(self, message: str):
        super().__init__(message)
        self.message = message


class MailRateLimited(MailError):
    def __init__(self, message: str, retry_after: int):
        super().__init__(message)
        self.retry_after = retry_after   # 다시 시도해도 되는 때까지 초


class MailSendError(MailError):
    pass


def is_enabled() -> bool:
    return config.MAIL_ENABLED


def mask_email(email: str) -> str:
    """로그에 개인정보가 그대로 남지 않게: 'abcdef@gmail.com' → 'a***@gmail.com'"""
    name, _, domain = (email or "").partition("@")
    return f"{name[:1]}***@{domain}" if domain else "***"


# ── 횟수 제한 ───────────────────────────────────────────────────
_HOUR = 3600
_DAY = 24 * 3600
_lock = threading.Lock()
_by_email: dict[str, list[float]] = {}   # 이메일(소문자) → 보낸 시각들 (최근 1시간)
_all_sent: list[float] = []              # 서버 전체 보낸 시각들 (최근 24시간)
_last_cap_log = 0.0                      # 하루 한도 경고를 마지막으로 찍은 시각
CAP_LOG_EVERY_SEC = 600                  # 한도에 걸린 요청마다 찍으면 공격 때 서버 로그가 끝없이 불어남 (11/19 동시성 시험에서 발견) → 10분에 한 번만


def reserve(email: str) -> tuple[str, float]:
    """보내기 전에 부른다. 한도를 넘으면 MailRateLimited, 아니면 release 에 넘길 표(ticket)를 준다.

    키는 '보낸 일'이 기록될 때만 만들어진다 → 하루 총량(MAIL_DAILY_LIMIT)이 곧 이 표의 크기 상한 (아무 주소나 보내도 메모리가 무한히 늘지 않음)
    """
    key = (email or "").strip().lower()
    now = time.time()
    with _lock:
        _all_sent[:] = [t for t in _all_sent if t > now - _DAY]
        recent = [t for t in _by_email.get(key, []) if t > now - _HOUR]
        if recent:
            _by_email[key] = recent
        else:
            _by_email.pop(key, None)

        if len(_all_sent) >= config.MAIL_DAILY_LIMIT:
            wait = int(_all_sent[0] + _DAY - now) + 1 if _all_sent else _DAY
            global _last_cap_log
            if now - _last_cap_log >= CAP_LOG_EVERY_SEC:
                _last_cap_log = now
                print(f"⚠️ [mail] 하루 발송 한도({config.MAIL_DAILY_LIMIT}통) 도달 — 새 메일을 막는 중 (이 안내는 10분에 한 번만)")
            raise MailRateLimited("오늘 보낼 수 있는 인증 메일이 모두 쓰였어요. 내일 다시 시도해 주세요", wait)
        if recent and now - recent[-1] < config.MAIL_COOLDOWN_SEC:
            wait = int(recent[-1] + config.MAIL_COOLDOWN_SEC - now) + 1
            raise MailRateLimited(f"인증 메일을 방금 보냈어요. {wait}초 뒤에 다시 받아 주세요", wait)
        if len(recent) >= config.MAIL_PER_EMAIL_HOURLY:
            wait = int(recent[0] + _HOUR - now) + 1
            raise MailRateLimited("이 이메일로 보낸 인증 메일이 너무 많아요. 잠시 뒤에 다시 시도해 주세요", wait)

        _by_email.setdefault(key, []).append(now)
        _all_sent.append(now)
        return key, now


def release(ticket: tuple[str, float]) -> None:
    """보내기가 실패했을 때: 횟수를 돌려 줘서, 우리 쪽 문제로 사용자가 1분씩 기다리지 않게 한다."""
    key, ts = ticket
    with _lock:
        for lst in (_by_email.get(key, []), _all_sent):
            if ts in lst:
                lst.remove(ts)


# ── 발송 ────────────────────────────────────────────────────────
def send_mail(to: str, subject: str, text: str, html_body: str | None = None) -> None:
    """구글 SMTP 로 메일 한 통. 실패하면 MailSendError (계정 · 비밀번호가 문구에 들어가지 않음)."""
    if not config.MAIL_ENABLED:
        raise MailSendError("메일 발송이 설정되지 않았어요")
    # 헤더 주입 방어 (받는 사람 · 제목에 줄바꿈을 넣어 헤더를 꾸미는 공격) — 요청 단계의 EmailStr 검사와 별개로 한 번 더
    for value in (to, subject):
        if "\r" in value or "\n" in value:
            raise MailSendError("메일 주소 또는 제목이 올바르지 않아요")

    msg = EmailMessage()
    msg["Subject"] = subject
    msg["From"] = formataddr((config.SMTP_FROM_NAME, config.SMTP_USER))
    msg["To"] = to
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=config.SMTP_USER.partition("@")[2] or None)
    msg.set_content(text)
    if html_body:
        msg.add_alternative(html_body, subtype="html")

    ctx = ssl.create_default_context()   # 인증서 · 호스트 이름 검사 켜짐
    try:
        if config.SMTP_PORT == 465:
            smtp = smtplib.SMTP_SSL(config.SMTP_HOST, config.SMTP_PORT, timeout=config.SMTP_TIMEOUT_SEC, context=ctx)
        else:
            smtp = smtplib.SMTP(config.SMTP_HOST, config.SMTP_PORT, timeout=config.SMTP_TIMEOUT_SEC)
        with smtp:
            if config.SMTP_PORT != 465:
                smtp.starttls(context=ctx)   # 암호화가 안 되면 여기서 예외 → 로그인(비밀번호 전송)까지 가지 않음
            # 로그인 방법은 PLAIN 하나만 시도 (11/19 실제 구글 시험에서 발견): smtplib 는 PLAIN → LOGIN 순서로 차례로 시도하는데,
            #   구글은 앱 비밀번호가 틀리면 첫 실패(535) 뒤에 연결을 끊어서 두 번째 시도가 SMTPServerDisconnected 로 바뀌어 버림
            #   → '앱 비밀번호를 확인하라'는 안내 로그가 안 찍힘. 한 번만 시도하면 깔끔한 535 가 나온다.
            smtp.ehlo()                                   # starttls 뒤 서버가 알려 주는 로그인 방법을 먼저 받음 (login 이 다시 묻지 않도록)
            if "PLAIN" in smtp.esmtp_features.get("auth", "").split():
                smtp.esmtp_features["auth"] = "PLAIN"
            smtp.login(config.SMTP_USER, config.SMTP_PASSWORD)
            smtp.send_message(msg)
    except smtplib.SMTPAuthenticationError as e:
        # 앱 비밀번호가 틀렸거나 · 취소됐거나 · 2단계 인증이 꺼진 경우. 로그에는 구글이 준 코드만 (비밀번호는 안 찍음)
        print(f"⚠️ [mail] 구글 로그인 거절 (SMTP {e.smtp_code}) — SMTP_USER · SMTP_PASSWORD(앱 비밀번호) 확인")
        raise MailSendError("메일을 보내지 못했어요. 잠시 뒤에 다시 시도해 주세요") from None
    except (smtplib.SMTPException, OSError, ssl.SSLError) as e:
        print(f"⚠️ [mail] 발송 실패 → {mask_email(to)}: {type(e).__name__}")
        raise MailSendError("메일을 보내지 못했어요. 잠시 뒤에 다시 시도해 주세요") from None
    print(f"✉️ [mail] 발송 완료 → {mask_email(to)}")


def send_verification_code(email: str, code: str, ttl_min: int,
                           title: str = "이메일 인증", where: str = "앱") -> None:
    """인증번호 메일 (글자판 + HTML). 가입 = 기본값('이메일 인증' · 앱), 관리자 웹 이메일 변경 = ('이메일 변경 인증' · 관리자 웹)."""
    text = (
        f"[졸음 가드] {title}번호\n\n"
        f"인증번호: {code}\n\n"
        f"{ttl_min}분 안에 {where}에 입력해 주세요.\n"
        f"본인이 요청하지 않았다면 이 메일은 무시하셔도 됩니다.\n"
    )
    safe, safe_title, safe_where = html.escape(code), html.escape(title), html.escape(where)
    page = (
        '<div style="font-family:-apple-system,\'Malgun Gothic\',sans-serif;max-width:420px;margin:0 auto;padding:24px;color:#1f2937">'
        f'<h2 style="margin:0 0 8px">졸음 가드 {safe_title}</h2>'
        f'<p style="margin:0 0 16px;color:#4b5563">아래 인증번호를 {safe_where}에 입력해 주세요.</p>'
        f'<div style="font-size:32px;font-weight:700;letter-spacing:8px;padding:16px;background:#f3f4f6;border-radius:8px;text-align:center">{safe}</div>'
        f'<p style="margin:16px 0 0;color:#6b7280;font-size:13px">{ttl_min}분 안에 입력해 주세요.<br>'
        '본인이 요청하지 않았다면 이 메일은 무시하셔도 됩니다.</p>'
        '</div>'
    )
    send_mail(email, f"[졸음 가드] {title}번호", text, page)
