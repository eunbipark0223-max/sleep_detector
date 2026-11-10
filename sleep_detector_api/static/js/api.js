// ═══════════════════════════════════════════════════════════════
// static/js/api.js — 관리자 웹이 서버를 부르는 함수 모음
// ═══════════════════════════════════════════════════════════════
// 담당: D   |   우선: P0
// 수업 원본: road_hazard_api/static/js/api.js (🟡 수정)
//
// [이 파일이 하는 일]
//   - /admin/hazards → /admin/events 등 주소 변경
//   - 조치완료 상태 변경 호출 (PATCH /events/{id}/status)
//
// [쓰는 곳] admin_login.html · admin.html  (둘 다 <script src="js/api.js"> 로 불러옴, 서버와 같은 주소라 주소 앞부분은 비움)
//
// 자세한 내용: 「파일 구조」 문서 · 「파이널 프로젝트 최종 기획안 10.13」
// ═══════════════════════════════════════════════════════════════
const TOKEN_KEY = 'admin_token';
const API_TIMEOUT_MS = 15000;

function getToken() {
  try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; }
}
function setToken(token) {
  try { localStorage.setItem(TOKEN_KEY, token); } catch (e) { /* 저장이 막힌 브라우저면 이번 탭에서만 */ }
}
function clearToken() {
  try { localStorage.removeItem(TOKEN_KEY); } catch (e) { /* 무시 */ }
}

// 모든 요청에 로그인 토큰을 붙인다. 401(토큰 없음 · 만료)이면 로그인 화면으로 보냄.
async function apiFetch(path, options = {}) {
  const headers = Object.assign({}, options.headers || {});
  const token = getToken();
  if (token) headers['Authorization'] = 'Bearer ' + token;
  if (options.body !== undefined) headers['Content-Type'] = 'application/json';

  // 서버가 꺼졌거나 응답 없이 멈추면 사람이 읽을 수 있는 말로 (fetch 는 멈춘 요청을 혼자 끝내지 않음 → 관제 화면이 끊김을 모름)
  const timeout = new AbortController();
  const timer = setTimeout(() => timeout.abort(), API_TIMEOUT_MS);
  let res;
  try {
    res = await fetch(path, {
      method: options.method || 'GET',
      headers: headers,
      body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
      signal: timeout.signal,
    });
  } catch (e) {
    throw new Error(e.name === 'AbortError' ? '서버 응답이 없어요' : '서버에 연결할 수 없어요');
  } finally {
    clearTimeout(timer);
  }
  if (res.status === 401 && !path.startsWith('/users/login')) {
    clearToken();
    location.href = 'admin_login.html';
    throw new Error('로그인이 필요합니다');
  }
  if (res.status === 403 && !path.startsWith('/users/login')) {    // 이 서버의 403 은 '관리자만' (require_admin) — 기사 계정 토큰이거나 관리자 권한이 빠진 경우
    clearToken();
    location.href = 'admin_login.html?denied=1';                   // 로그인 화면이 이유를 안내 (연결 끊김 안내와 헷갈리지 않게)
    throw new Error('관리자만 사용할 수 있습니다');
  }
  let data = null;
  try { data = await res.json(); } catch (e) { /* 본문이 없는 응답 */ }
  if (!res.ok) {
    const detail = data && data.detail;
    if (typeof detail === 'string') throw new Error(detail);
    if (Array.isArray(detail)) {                                   // 422: 칸마다 틀린 이유 목록 → 한국어 문구만 이어서 보여 줌
      const lines = detail.map((d) => String((d && d.msg) || '').replace('Value error, ', '')).filter(Boolean);
      if (lines.length) throw new Error(lines.join(' '));
    }
    throw new Error('요청에 실패했습니다 (' + res.status + ')');
  }
  return data;
}

// ── 로그인 (관리자만 통과) ────────────────────────────────────
async function adminLogin(email, password) {
  const data = await apiFetch('/users/login', { method: 'POST', body: { email: email, password: password } });
  if (!data.user || data.user.role !== 'admin') throw new Error('관리자 계정이 아닙니다');
  setToken(data.access_token);
  return data.user;
}

// ── 졸음 경고 · 기사 · 통계 ───────────────────────────────────
function fetchAdminEvents(filters = {}) {
  const params = new URLSearchParams();
  if (filters.stage !== undefined && filters.stage !== '') params.set('stage', filters.stage);
  if (filters.status) params.set('status', filters.status);
  const query = params.toString();
  return apiFetch('/admin/events' + (query ? '?' + query : ''));
}
function fetchAdminUsers() { return apiFetch('/admin/users'); }
function fetchStageStats() { return apiFetch('/admin/stats/stage'); }
function fetchHourlyStats() { return apiFetch('/admin/stats/hourly'); }

// ── 졸음 사진: 로그인이 필요한 API 라서 <img src> 로는 못 열고, 토큰을 붙여 받아 브라우저 안 임시 주소(blob:)로 만든다 ──
// 같은 사진은 한 번만 받고(10초마다 화면을 다시 그려도 깜빡이지 않게), 오래된 것부터 버려 메모리를 아낀다.
const PHOTO_CACHE_MAX = 30;
const photoCache = new Map();                       // 사진 주소 → Promise<blob: 주소>
function fetchPhotoUrl(path) {
  if (photoCache.has(path)) return photoCache.get(path);
  const job = (async () => {
    const token = getToken();
    const res = await fetch(path, { headers: token ? { Authorization: 'Bearer ' + token } : {} });
    if (res.status === 401) { clearToken(); location.href = 'admin_login.html'; throw new Error('로그인이 필요합니다'); }
    if (!res.ok) throw new Error('사진을 불러올 수 없어요 (' + res.status + ')');
    return URL.createObjectURL(await res.blob());
  })();
  photoCache.set(path, job);
  job.catch(() => { if (photoCache.get(path) === job) photoCache.delete(path); });   // 실패는 기억하지 않음 (다음에 다시 시도)
  while (photoCache.size > PHOTO_CACHE_MAX) {
    const oldest = photoCache.keys().next().value;
    photoCache.get(oldest).then((u) => URL.revokeObjectURL(u), () => {});
    photoCache.delete(oldest);
  }
  return job;
}

// ── 내 정보 · 설정 (관리자 설정 화면) ─────────────────────────
function fetchMe() { return apiFetch('/users/me'); }
function updateMe(fields) { return apiFetch('/users/me', { method: 'PATCH', body: fields }); }        // {name?, phone?}
function changeMyPassword(currentPassword, newPassword) {
  return apiFetch('/users/me/password', { method: 'PUT', body: { current_password: currentPassword, new_password: newPassword } });
}

// ── 처리 상태 변경: 미확인 / 확인 / 조치완료 / 휴식완료. 조치완료면 서버가 3단계를 푼다 ──
function updateEventStatus(eventId, status) {
  return apiFetch('/events/' + eventId + '/status', { method: 'PATCH', body: { status: status } });
}
