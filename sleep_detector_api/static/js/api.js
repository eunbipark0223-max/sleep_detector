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

  const res = await fetch(path, {
    method: options.method || 'GET',
    headers: headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });
  if (res.status === 401 && !path.startsWith('/users/login')) {
    clearToken();
    location.href = 'admin_login.html';
    throw new Error('로그인이 필요합니다');
  }
  let data = null;
  try { data = await res.json(); } catch (e) { /* 본문이 없는 응답 */ }
  if (!res.ok) {
    const detail = data && data.detail;
    throw new Error(typeof detail === 'string' ? detail : '요청에 실패했습니다 (' + res.status + ')');
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

// ── 처리 상태 변경: 미확인 / 확인 / 조치완료 / 휴식완료. 조치완료면 서버가 3단계를 푼다 ──
function updateEventStatus(eventId, status) {
  return apiFetch('/events/' + eventId + '/status', { method: 'PATCH', body: { status: status } });
}
