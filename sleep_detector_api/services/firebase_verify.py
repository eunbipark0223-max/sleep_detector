# ═══════════════════════════════════════════════════════════════
# services/firebase_verify.py — 구글(Firebase) 로그인 토큰 검증
# ═══════════════════════════════════════════════════════════════
# 담당: D   |   우선: P0 (관리자 웹 구글 로그인)
#
# [이 파일이 하는 일]
#   - 관리자 웹이 구글 로그인 뒤 보내는 Firebase ID 토큰(id_token)이 진짜인지 확인한다
#     · 서명: 구글이 공개한 인증서(securetoken@system.gserviceaccount.com)로 RS256 서명 확인
#     · 발급 대상(aud) = 우리 Firebase 프로젝트 · 발급처(iss) · 만료 시간
#     · 토큰 안의 이메일 · uid 가 요청의 이메일 · firebase_uid 와 같은지
#   - 새 패키지 없이 이미 있는 PyJWT · cryptography · requests 만 쓴다
#
# [왜 필요한가]
#   - POST /users/google 은 앱이 보내는 email · name · firebase_uid 를 그대로 믿는다. 그대로 두면 관리자 이메일만 알면
#     관리자 토큰을 받을 수 있다 → 관리자 계정(role = admin)의 구글 로그인은 이 검증을 반드시 통과해야 한다.
#   - .env 의 FIREBASE_VERIFY=true 로 두면 일반 기사의 구글 로그인에도 같은 검증을 요구한다 (그때는 앱도 id_token 을 보내야 함)
#
# [설정] .env
#   FIREBASE_PROJECT_ID=...   Firebase 콘솔 → 프로젝트 설정의 '프로젝트 ID'
#   FIREBASE_API_KEY=...      같은 곳의 '웹 API 키' (관리자 웹 로그인 화면이 구글 창을 띄울 때 씀. 공개용 키라 비밀은 아님)
#   FIREBASE_APP_ID=...       (선택) 웹 앱 ID. 없어도 구글 로그인은 됨
#   → Firebase 콘솔 → Authentication → 설정 → 승인된 도메인에 관리자 웹 주소(발표 서버 주소)를 추가해야 구글 창이 열린다 (localhost 는 기본 허용)
# ═══════════════════════════════════════════════════════════════
import re
import time

import jwt
import requests
from cryptography import x509

import config

CERT_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com"
_certs = {"keys": {}, "until": 0.0}      # kid → 인증서(PEM). 구글이 알려 준 시간(max-age)만큼 기억


class FirebaseVerifyError(Exception):
    """토큰을 믿을 수 없을 때 (서명 · 대상 · 만료 · 이메일 불일치)"""


class FirebaseNotConfigured(Exception):
    """서버 .env 에 FIREBASE_PROJECT_ID 가 없음"""


def _load_certs(force: bool = False) -> dict:
    now = time.time()
    if not force and _certs["keys"] and now < _certs["until"]:
        return _certs["keys"]
    res = requests.get(CERT_URL, timeout=5)
    res.raise_for_status()
    m = re.search(r"max-age=(\d+)", res.headers.get("Cache-Control", ""))
    _certs["keys"] = res.json()
    _certs["until"] = now + (int(m.group(1)) if m else 3600)
    return _certs["keys"]


def verify_id_token(id_token: str, email: str, firebase_uid: str) -> dict:
    """맞으면 토큰 안의 정보(claims)를, 아니면 FirebaseVerifyError. 설정이 없으면 FirebaseNotConfigured."""
    project = config.FIREBASE_PROJECT_ID
    if not project:
        raise FirebaseNotConfigured("FIREBASE_PROJECT_ID 가 비어 있습니다")
    if not id_token:
        raise FirebaseVerifyError("id_token 이 없습니다")
    try:
        kid = jwt.get_unverified_header(id_token).get("kid")
        keys = _load_certs()
        if kid not in keys:                                   # 구글이 인증서를 바꿨을 수 있음 → 한 번 더 받아서 확인
            keys = _load_certs(force=True)
        if kid not in keys:
            raise FirebaseVerifyError("알 수 없는 서명 키")
        public_key = x509.load_pem_x509_certificate(keys[kid].encode()).public_key()
        claims = jwt.decode(id_token, public_key, algorithms=["RS256"], audience=project,
                            issuer=f"https://securetoken.google.com/{project}", options={"require": ["exp", "iat", "sub"]})
    except FirebaseVerifyError:
        raise
    except (jwt.PyJWTError, ValueError, requests.RequestException) as e:
        raise FirebaseVerifyError(f"{type(e).__name__}: {e}")
    if str(claims.get("email", "")).lower() != str(email).lower():
        raise FirebaseVerifyError("토큰의 이메일이 요청과 다릅니다")
    if claims.get("sub") != firebase_uid:
        raise FirebaseVerifyError("토큰의 uid 가 요청과 다릅니다")
    return claims
