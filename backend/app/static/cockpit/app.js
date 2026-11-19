/* ApplyPilot Command Center — live cockpit over /api/v1.
   No build step, no framework: state + render functions + event delegation. */
(() => {
  'use strict';

  // ───────────────────────── Auth ─────────────────────────
  // Opening /app/?token=… makes the server set an HttpOnly session cookie, which
  // authenticates every later API call. The token is used as a Bearer header for this
  // page load only, then removed from the address bar so it isn't left in history.
  const TOKEN = (() => {
    const url = new URL(location.href);
    const p = url.searchParams.get('token');
    if (!p) return '';
    url.searchParams.delete('token');
    history.replaceState(null, '', url.pathname + url.search + url.hash);
    return p;
  })();

  async function api(path, { method = 'GET', body, query } = {}) {
    let url = '/api/v1' + path;
    if (query) {
      const q = new URLSearchParams();
      Object.entries(query).forEach(([k, v]) => { if (v !== undefined && v !== null && v !== '') q.set(k, v); });
      const s = q.toString(); if (s) url += '?' + s;
    }
    const headers = {};
    if (TOKEN) headers.Authorization = `Bearer ${TOKEN}`;
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const r = await fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined });
    if (r.status === 204) return null;
    let data = null;
    try { data = await r.json(); } catch (e) { /* non-JSON */ }
    if (!r.ok) {
      const d = data && data.detail;
      throw new Error(typeof d === 'string' ? d : (Array.isArray(d) ? d.map(x => x.msg).join('; ') : `Request failed (${r.status})`));
    }
    return data;
  }

  // Running inside the ApplyPilot Android app? (it injects this JavaScript channel)
  const IN_SHELL = typeof window.ApplyPilotShell !== 'undefined' && !!window.ApplyPilotShell.postMessage;

  // ───────────────────────── Helpers ─────────────────────────
  const $ = (s, el = document) => el.querySelector(s);
  const $$ = (s, el = document) => Array.from(el.querySelectorAll(s));
  const esc = (v) => String(v ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const fmt = (n) => (n ?? 0).toLocaleString('en-IN');
  const icon = (name, cls = '') => `<span class="ms ${cls}">${name}</span>`;
  const initials = (s) => (String(s || '?').replace(/[^A-Za-z0-9 ]/g, ' ').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('') || '?').toUpperCase();
  const toDate = (iso) => { if (!iso) return null; const s = /[zZ]|[+-]\d\d:?\d\d$/.test(iso) ? iso : iso + 'Z'; const d = new Date(s); return isNaN(d) ? null : d; };
  function rel(iso) {
    const d = toDate(iso); if (!d) return '';
    const s = (Date.now() - d.getTime()) / 1000;
    if (s < 60) return 'just now';
    if (s < 3600) return `${Math.floor(s / 60)}m ago`;
    if (s < 86400) return `${Math.floor(s / 3600)}h ago`;
    if (s < 86400 * 7) return `${Math.floor(s / 86400)}d ago`;
    return d.toLocaleDateString('en-IN', { day: 'numeric', month: 'short' });
  }
  const stamp = (iso) => { const d = toDate(iso); return d ? d.toLocaleString('en-IN', { day: 'numeric', month: 'short', hour: '2-digit', minute: '2-digit' }) : ''; };
  const shortLogTime = (s) => String(s || '').replace(/:(\d\d) •/, ' ·').replace('•', '·');
  const debounce = (fn, ms = 200) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
  const isTyping = () => { const a = document.activeElement; return a && (a.tagName === 'INPUT' || a.tagName === 'TEXTAREA' || a.tagName === 'SELECT' || a.isContentEditable); };

  function toast(msg, err = false) {
    const el = document.createElement('div');
    el.className = 'toast' + (err ? ' err' : '');
    el.innerHTML = icon(err ? 'error' : 'check_circle') + `<span>${esc(msg)}</span>`;
    $('#toasts').appendChild(el);
    setTimeout(() => el.remove(), err ? 5200 : 3000);
  }

  async function run(btn, fn, okMsg) {
    if (btn) { btn.classList.add('busy'); btn.disabled = true; }
    try {
      const r = await fn();
      if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg);
      return r;
    } catch (e) { toast(e.message || 'Something went wrong', true); return undefined; }
    finally { if (btn && btn.isConnected) { btn.classList.remove('busy'); btn.disabled = false; } }
  }

  function confirmModal({ title, body, ok = 'Confirm', danger = false }) {
    return new Promise(resolve => {
      const ov = $('#overlay');
      ov.innerHTML = `<div class="modal-wrap" data-close><div class="modal" role="dialog" aria-modal="true">
        <h3>${esc(title)}</h3><p>${body}</p>
        <div class="acts"><button class="btn ghost" data-x="0">Cancel</button><button class="btn ${danger ? 'danger' : 'primary'}" data-x="1">${esc(ok)}</button></div>
      </div></div>`;
      const done = (v) => { ov.innerHTML = ''; document.removeEventListener('keydown', onKey, true); resolve(v); };
      const onKey = (e) => { if (e.key === 'Escape') { e.stopPropagation(); done(false); } if (e.key === 'Enter') { e.preventDefault(); done(true); } };
      document.addEventListener('keydown', onKey, true);
      ov.querySelector('.modal-wrap').addEventListener('click', (e) => {
        const x = e.target.closest('[data-x]');
        if (x) return done(x.dataset.x === '1');
        if (e.target.hasAttribute('data-close')) done(false);
      });
      ov.querySelector('[data-x="1"]').focus();
    });
  }

  function ring(pct, size = 64, stroke = 7, color = 'var(--indigo)') {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r, off = c * (1 - Math.max(0, Math.min(1, pct)));
    return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}">
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="var(--track)" stroke-width="${stroke}"/>
      <circle cx="${size / 2}" cy="${size / 2}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round"
        stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}" style="transition:stroke-dashoffset .8s var(--ease)"/></svg>`;
  }

  // ───────────────────────── Domain mapping ─────────────────────────
  const STAGES = [
    { id: 'triage', label: 'Triage', color: 'amber', statuses: ['maybe', 'evaluated', 'needs_verification'] },
    { id: 'queued', label: 'Queued', color: 'indigo', statuses: ['queued', 'approved'] },
    { id: 'active', label: 'In flight', color: 'violet', statuses: ['applying', 'needs_review', 'needs_attention', 'needs_input'] },
    { id: 'submitted', label: 'Submitted', color: 'teal', statuses: ['dry_run', 'applied', 'submitted'] },
    { id: 'interview', label: 'Interview', color: 'teal', statuses: ['interview', 'offer'] },
    { id: 'new', label: 'Discovered', color: 'slate', statuses: ['discovered'] },
    { id: 'closed', label: 'Closed', color: 'coral', statuses: ['skipped', 'rejected', 'failed', 'dismissed', 'blocked', 'expired'] },
  ];
  const stageOf = (status) => STAGES.find(s => s.statuses.includes(status)) || STAGES.find(s => s.id === 'new');
  const STATUS_LABEL = {
    maybe: 'Maybe', evaluated: 'Evaluated', needs_verification: 'Verify', queued: 'Queued', approved: 'Queued',
    applying: 'Applying', needs_review: 'Needs review', needs_attention: 'Attention', needs_input: 'Needs you',
    dry_run: 'Dry run', applied: 'Applied', submitted: 'Submitted', interview: 'Interview', offer: 'Offer',
    discovered: 'Discovered', skipped: 'Skipped', rejected: 'Rejected', failed: 'Failed', dismissed: 'Dismissed', blocked: 'Blocked', expired: 'Expired',
  };
  const statusColor = (s) => ({ needs_review: 'violet', needs_attention: 'amber', needs_input: 'amber', failed: 'coral', rejected: 'coral', blocked: 'coral', skipped: 'slate', dismissed: 'slate', dry_run: 'indigo', offer: 'teal' }[s] || stageOf(s).color);
  const statusChip = (s) => `<span class="chip ${statusColor(s)}">${esc(STATUS_LABEL[s] || s)}</span>`;
  const scoreColor = (s) => s >= 4 ? 'var(--teal)' : s >= 3 ? 'var(--indigo)' : s >= 2 ? 'var(--amber)' : 'var(--coral)';
  const scoreTag = (s) => s > 0 ? `<span class="score"><span class="dot" style="background:${scoreColor(s)}"></span>${Number(s).toFixed(1)}</span>` : `<span class="faint">—</span>`;
  const logColor = (l) => {
    if (l.level === 'error' || l.outcome === 'failure' || l.outcome === 'error') return 'coral';
    if (l.level === 'warn' || l.level === 'warning' || l.outcome === 'warning') return 'amber';
    if (l.outcome === 'success') return 'teal';
    if (/needs_you|review/.test(l.event_type)) return 'violet';
    if (/apply|submit/.test(l.event_type)) return 'indigo';
    return '';
  };
  const ENGINE_STATE = {
    running: ['Running', 'teal'], paused_by_user: ['Paused', 'amber'], paused_by_daily_cap: ['Paused · daily cap', 'amber'],
    circuit_broken: ['Circuit breaker', 'coral'], paused_by_circuit_breaker: ['Circuit breaker', 'coral'], outside_active_hours: ['Sleeping', 'slate'],
  };
  const engineLabel = (st) => {
    if (!st) return ['Connecting…', ''];
    const s = st.is_circuit_broken ? 'circuit_broken' : st.automation_state;
    return ENGINE_STATE[s] || [st.is_paused ? 'Paused' : String(s || 'running').replace(/_/g, ' '), st.is_paused ? 'amber' : 'teal'];
  };

  // ───────────────────────── State ─────────────────────────
  const S = {
    view: 'today',
    stats: null, analytics: null, logs: [], automation: null, profile: null, gemini: null, resumes: [],
    jobs: null, needs: [], aiAnswers: [], triage: [], answers: null,
    inbox: { tab: 'questions', sel: 0, picks: {}, remember: true },
    pipe: { stage: 'all', q: '', source: '', min: '', mode: 'table', sort: 'score', dir: -1, limit: 100, laneLimit: {} },
    ans: { cat: 'all', q: '', editing: null, adding: false },
    act: { level: 'all', q: '' },
    jobId: null, job: null,
    online: true,
  };

  const VIEWS = [
    { id: 'today', label: 'Today', icon: 'space_dashboard', mobile: 'today', sub: () => new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' }) },
    { id: 'inbox', label: 'Needs you', icon: 'inbox', mobile: 'notifications', sub: () => 'Every decision that needs a human, in one place' },
    { id: 'pipeline', label: 'Pipeline', icon: 'view_kanban', mobile: 'work', sub: () => S.jobs ? `${fmt(S.jobs.length)} tracked roles` : 'Tracked roles' },
    { id: 'answers', label: 'Answers', icon: 'forum', mobile: 'forum', sub: () => 'Verified facts the agent reuses on forms' },
    { id: 'activity', label: 'Activity', icon: 'receipt_long', sub: () => 'Engine run log' },
    { id: 'settings', label: 'Profile & rules', icon: 'tune', mobile: 'person', sub: () => 'Who you are and how the agent behaves' },
  ];
  const MOBILE_TABS = ['today', 'inbox', 'pipeline', 'answers', 'settings'];
  const MOBILE_LABEL = { today: 'Today', inbox: 'Needs You', pipeline: 'Jobs', answers: 'Answers', settings: 'Profile' };

  const inboxCount = () => (S.stats ? S.stats.needs_you_count : S.needs.length) + S.aiAnswers.length + (S.stats ? S.stats.maybe_count : S.triage.length);

  // ───────────────────────── Chrome (nav, engine, tabbar) ─────────────────────────
  function renderNav() {
    const counts = { inbox: inboxCount(), pipeline: S.stats ? S.stats.queue_count : 0 };
    $('#nav').innerHTML = `<div class="nav-label">Workspace</div>` + VIEWS.map((v, i) => {
      const n = counts[v.id];
      const badge = v.id === 'inbox' ? `<span class="nav-count ${n ? '' : 'zero'}">${n || 0}</span>` : `<span class="kbd">${i + 1}</span>`;
      return `<button class="nav-item ${S.view === v.id ? 'active' : ''}" data-nav="${v.id}" title="${esc(v.label)}">${icon(v.icon)}<span class="lbl">${esc(v.label)}</span>${badge}</button>`;
    }).join('');
    $('#tabbar').innerHTML = MOBILE_TABS.map(id => {
      const v = VIEWS.find(x => x.id === id);
      const n = id === 'inbox' ? inboxCount() : 0;
      return `<button class="${S.view === id ? 'active' : ''}" data-nav="${id}">${icon(v.mobile)}<span>${MOBILE_LABEL[id]}</span>${n ? `<span class="badge">${n > 99 ? '99+' : n}</span>` : ''}</button>`;
    }).join('');
  }

  function renderEngine() {
    const st = S.stats;
    const [label, color] = engineLabel(st);
    const live = st && st.go_live;
    const paused = st && st.is_paused;
    const applied = st ? st.daily_applied : 0, cap = st ? st.daily_cap : 0;
    $('#engine').innerHTML = `
      <div class="engine-row"><span class="engine-title">Engine</span><span class="engine-state"><span class="dot ${color} ${color === 'teal' ? 'pulse' : ''}"></span>${esc(label)}</span></div>
      <div class="mode-switch" role="group" aria-label="Submission mode">
        <button class="${!live ? 'on' : ''}" data-act="mode-dry">Dry run</button>
        <button class="${live ? 'on live' : ''}" data-act="mode-live">Live</button>
      </div>
      <div>
        <div class="engine-row" style="font-size:12px;margin-bottom:6px"><span class="muted">Today</span><span class="tnum">${fmt(applied)} / ${fmt(cap)}</span></div>
        <div class="bar"><i style="width:${cap ? Math.min(100, applied / cap * 100) : 0}%"></i></div>
      </div>
      <button class="btn ${paused ? 'primary' : ''}" data-act="${paused ? 'resume' : 'pause'}" ${st ? '' : 'disabled'}>${icon(paused ? 'play_arrow' : 'pause')}${paused ? 'Resume engine' : 'Pause engine'}</button>`;
    $('#top-actions').innerHTML = `
      <button class="btn" data-act="discover" title="Scan ATS boards for new roles">${icon('travel_explore')}Discover</button>
      <button class="btn primary" data-act="apply-next" title="Process the top queued job" ${paused ? 'disabled' : ''}>${icon('bolt')}Apply next</button>`;
  }

  function renderChrome() {
    renderNav(); renderEngine();
    const v = VIEWS.find(x => x.id === S.view);
    $('#page-title').textContent = v.label;
    $('#page-sub').textContent = v.sub();
    document.title = `${v.label} · ApplyPilot`;
  }

  const mobileHead = (title, right = '') => `<div class="view-head"><div><div class="date">${esc(new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' }))}</div><h1>${esc(title)}</h1></div>${right}</div>`;

  // ───────────────────────── Loaders ─────────────────────────
  async function loadStats() {
    try { S.stats = await api('/stats'); S.online = true; }
    catch (e) { S.online = false; }
    renderChrome();
  }
  const loaders = {
    async today() {
      const [a, l, au] = await Promise.allSettled([api('/analytics'), api('/logs', { query: { limit: 14 } }), api('/automation/status')]);
      if (a.status === 'fulfilled') S.analytics = a.value;
      if (l.status === 'fulfilled') S.logs = l.value;
      if (au.status === 'fulfilled') S.automation = au.value;
    },
    async inbox() {
      const [n, g, t] = await Promise.allSettled([api('/needs-you'), api('/needs-you/gemini-answers'), api('/jobs', { query: { status: 'maybe' } })]);
      if (n.status === 'fulfilled') S.needs = n.value;
      if (g.status === 'fulfilled') S.aiAnswers = g.value;
      if (t.status === 'fulfilled') S.triage = t.value;
    },
    async pipeline() { S.jobs = await api('/jobs'); },
    async answers() { S.answers = await api('/answer-bank'); },
    async activity() { S.logs = await api('/logs', { query: { limit: 250 } }); },
    async settings() {
      const [p, g, r, au] = await Promise.allSettled([api('/profile'), api('/profile/gemini-settings'), api('/resumes'), api('/automation/status')]);
      if (p.status === 'fulfilled') S.profile = p.value;
      if (g.status === 'fulfilled') S.gemini = g.value;
      if (r.status === 'fulfilled') S.resumes = r.value;
      if (au.status === 'fulfilled') S.automation = au.value;
    },
  };

  // ───────────────────────── Router ─────────────────────────
  let viewToken = 0;
  async function go(view, { silent = false } = {}) {
    if (!VIEWS.some(v => v.id === view)) view = 'today';
    const changed = S.view !== view;
    S.view = view;
    if (location.hash !== '#/' + view) history.replaceState(null, '', '#/' + view);
    renderChrome();
    const my = ++viewToken;
    if (changed) S.anim = true;
    if (changed || !silent) { $('#content').innerHTML = skeleton(); $('#content').scrollTop = 0; }
    try { await loaders[view](); }
    catch (e) { if (my === viewToken) $('#content').innerHTML = errorView(e); return; }
    if (my !== viewToken) return;
    render();
  }
  function render() {
    const html = renderers[S.view]();
    const anim = S.anim; S.anim = false;
    $('#content').innerHTML = `<div class="view ${anim ? 'enter' : ''}">${html}</div>`;
    renderChrome();
    afterRender[S.view] && afterRender[S.view]();
  }
  const skeleton = () => `<div class="view"><div class="kpis">${'<div class="card kpi"><div class="skel" style="height:14px;width:50%"></div><div class="skel" style="height:28px;width:40%"></div></div>'.repeat(4)}</div>
    <div class="grid-today"><div class="card span-8" style="height:240px;padding:16px"><div class="skel" style="height:100%"></div></div><div class="card span-4" style="height:240px;padding:16px"><div class="skel" style="height:100%"></div></div></div></div>`;
  const errorView = (e) => `<div class="view"><div class="card"><div class="empty">${icon('cloud_off')}<b>Couldn't reach the ApplyPilot backend</b><span>${esc(e.message)}</span><button class="btn" data-act="reload">${icon('refresh')}Try again</button></div></div></div>`;

  // ───────────────────────── View: Today ─────────────────────────
  const renderers = {};
  const afterRender = {};

  renderers.today = () => {
    const st = S.stats || {}, an = S.analytics || {}, au = S.automation || {};
    const goal = an.goal || {};
    const cap = st.daily_cap || goal.daily_target || 0;
    const applied = st.daily_applied || 0;
    let alert = '';
    if (st.is_circuit_broken) {
      alert = `<div class="alert coral">${icon('report')}<div><div class="alert-t">Circuit breaker tripped</div><div class="alert-d">${esc(st.recovery_instruction || 'Repeated failures paused the queue for safety.')}</div></div>
        <div class="actions"><button class="btn" data-nav="activity">View log</button><button class="btn primary" data-act="resume">Run pre-flight & resume</button></div></div>`;
    } else if (st.is_paused) {
      alert = `<div class="alert">${icon('pause_circle')}<div><div class="alert-t">Engine paused${st.paused_at ? ` since ${esc(st.paused_at)}` : ''}</div><div class="alert-d">${esc(st.recovery_instruction || st.pause_reason || 'Automation is paused.')}</div></div>
        <div class="actions"><button class="btn primary" data-act="resume" ${st.can_resume === false ? 'disabled' : ''}>${icon('play_arrow')}Resume</button></div></div>`;
    }
    const nyCount = (st.needs_you_count || 0) + S.aiAnswers.length;
    const kpis = `<div class="kpis">
      <div class="card kpi quota"><div class="ring">${ring(cap ? applied / cap : 0, 64, 7)}<div class="c">${fmt(applied)}</div></div>
        <div><div class="kpi-l">Applied today</div><div class="kpi-s tnum">of ${fmt(cap)} cap · target ${fmt(st.daily_target || 0)}</div>
        <div class="kpi-s tnum">${fmt(st.real_applied_today || 0)} live · ${fmt(st.dry_run_today || 0)} dry run</div></div></div>
      <div class="card kpi link" data-nav="pipeline" data-stage="queued"><div class="kpi-l"><span class="dot indigo"></span>Queued</div><div class="kpi-v">${fmt(st.queue_count)}</div><div class="kpi-s">ready to apply</div></div>
      <div class="card kpi link" data-nav="inbox"><div class="kpi-l"><span class="dot amber"></span>Needs you</div><div class="kpi-v" style="color:${nyCount ? 'var(--amber)' : 'inherit'}">${fmt(nyCount)}</div><div class="kpi-s">${fmt(st.needs_you_count || 0)} questions · ${fmt(S.aiAnswers.length)} AI drafts</div></div>
      <div class="card kpi link" data-nav="inbox" data-tab="triage"><div class="kpi-l"><span class="dot violet"></span>To triage</div><div class="kpi-v">${fmt(st.maybe_count)}</div><div class="kpi-s">borderline fits</div></div>
      <div class="card kpi link" data-nav="pipeline" data-stage="submitted"><div class="kpi-l"><span class="dot teal"></span>Submitted</div><div class="kpi-v">${fmt((st.total_submitted_real || 0) + (st.total_dry_run || 0))}</div><div class="kpi-s">${fmt(st.total_submitted_real || 0)} live · ${fmt(st.total_dry_run || 0)} dry run</div></div>
      <div class="card kpi link" data-nav="pipeline" data-stage="interview"><div class="kpi-l"><span class="dot teal"></span>Interviews</div><div class="kpi-v">${fmt(st.interview_count)}</div><div class="kpi-s">${an.offers_count ? `${fmt(an.offers_count)} offers` : 'no offers yet'}</div></div>
    </div>`;

    const week = an.weekly_trend || [];
    const max = Math.max(1, ...week.map(w => w.count), goal.daily_target ? 0 : 1);
    const todayIdx = week.length - 1;
    const bars = week.length ? `<div class="bars">${week.map((w, i) => `<div class="col ${i === todayIdx ? 'today' : ''}" title="${esc(w.date)}: ${w.count}">
        <span class="v">${w.count}</span><div class="b" style="height:${Math.max(2, w.count / max * 100)}%"></div><span class="d">${esc(w.day)}</span></div>`).join('')}</div>`
      : `<div class="empty">No submissions this week yet</div>`;

    const funnel = (an.funnel || []).filter(f => f.stage);
    const fMax = Math.max(1, ...funnel.map(f => f.count));
    const fColor = { blue: 'var(--indigo)', amber: 'var(--amber)', violet: 'var(--violet)', emerald: 'var(--teal)', green: 'var(--teal)', gold: 'var(--amber)', rose: 'var(--coral)', red: 'var(--coral)' };
    const funnelHtml = funnel.map(f => `<div class="funnel-row"><span class="lab">${esc(f.stage)}</span>
      <div class="bar"><i style="width:${Math.max(f.count ? 1.5 : 0, f.count / fMax * 100)}%;background:${fColor[f.color] || 'var(--slate)'}"></i></div>
      <span class="val">${fmt(f.count)}</span></div>`).join('');

    const matches = (an.top_matches || []).slice(0, 6).map(m => `<button class="row" data-job="${m.id}">
      <div class="mono-av">${esc(initials(m.company))}</div>
      <div class="grow"><div class="main-t">${esc(m.title)}</div><div class="sub-t">${esc(m.company)} · ${esc(m.location || '')}</div></div>
      <div class="end">${m.match_percent ? `<span class="chip teal">${m.match_percent}%</span>` : ''}${scoreTag(m.score)}</div></button>`).join('')
      || `<div class="empty">No scored matches yet</div>`;

    const feed = (S.logs || []).slice(0, 10).map(l => `<div class="feed-item"><span class="dot ${logColor(l)}"></span>
      <span class="msg"><span class="ty">${esc(l.event_type)}</span>${esc(l.message)}</span><span class="t">${esc(shortLogTime(l.created_at))}</span></div>`).join('')
      || `<div class="empty">No activity yet</div>`;

    const checks = au.checks || {};
    const checkNames = { daily_cap_available: 'Daily cap available', circuit_breaker_clear: 'Circuit breaker clear', backend_healthy: 'Backend healthy', auth_valid: 'Auth valid', no_blocking_captcha: 'No blocking CAPTCHA' };
    const checkHtml = Object.keys(checkNames).filter(k => k in checks).map(k => `<div>${icon(checks[k] ? 'check_circle' : 'cancel', checks[k] ? 'ok' : 'bad')}${checkNames[k]}</div>`).join('');
    const na = an.needs_attention || {};

    const src = Object.entries(an.source_breakdown || {}).sort((a, b) => b[1] - a[1]);
    const sMax = Math.max(1, ...src.map(s => s[1]));
    const srcHtml = src.map(([k, v]) => `<div class="src-row"><span>${esc(k)}</span><div class="bar"><i style="width:${v / sMax * 100}%;background:var(--slate)"></i></div><span>${fmt(v)}</span></div>`).join('');

    const dist = an.match_score_distribution || {};
    const tiers = [['4–5', dist.tier_4_5, 'var(--teal)'], ['3–4', dist.tier_3_4, 'var(--indigo)'], ['2–3', dist.tier_2_3, 'var(--amber)'], ['1–2', dist.tier_1_2, 'var(--coral)']];
    const tTotal = Math.max(1, tiers.reduce((a, t) => a + (t[1] || 0), 0));
    const tierBar = `<div style="display:flex;height:8px;border-radius:4px;overflow:hidden;gap:2px;margin:4px 0 10px">${tiers.map(t => t[1] ? `<i style="flex:${t[1]};background:${t[2]}" title="${t[0]}: ${t[1]}"></i>` : '').join('')}</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:6px 12px;font-size:12px">${tiers.map(t => `<div style="display:flex;align-items:center;gap:6px"><span class="dot" style="background:${t[2]}"></span><span class="muted">Score ${t[0]}</span><span class="tnum" style="margin-left:auto">${fmt(t[1] || 0)} <span class="faint">${Math.round((t[1] || 0) / tTotal * 100)}%</span></span></div>`).join('')}</div>`;

    return `${mobileHead('Today', `<span class="chip ${st.go_live ? 'coral' : ''}">${st.go_live ? 'Live' : 'Dry run'}</span>`)}${alert}${kpis}
    <div class="grid-today">
      <div class="card span-8"><div class="card-h"><span class="card-t">Submissions this week</span><span class="aside tnum">${fmt(goal.weekly_applied || 0)} of ${fmt(goal.weekly_target || 0)} weekly goal</span></div><div class="card-b">${bars}</div></div>
      <div class="card span-4"><div class="card-h"><span class="card-t">Funnel</span><span class="aside tnum">${fmt(an.total_tracked || 0)} tracked</span></div><div class="card-b funnel">${funnelHtml || '<div class="empty">No data</div>'}</div></div>
      <div class="card span-7"><div class="card-h"><span class="card-t">Best matches</span><span class="aside"><button class="btn sm ghost" data-nav="pipeline">Open pipeline ${icon('arrow_forward')}</button></span></div><div class="list" style="padding-top:6px">${matches}</div></div>
      <div class="card span-5"><div class="card-h"><span class="card-t">Live activity</span><span class="aside"><button class="btn sm ghost" data-nav="activity">Full log ${icon('arrow_forward')}</button></span></div><div style="padding-top:6px">${feed}</div></div>
      <div class="card span-4"><div class="card-h"><span class="card-t">Pre-flight</span><span class="aside">${au.can_resume === false ? '<span class="chip coral">Blocked</span>' : '<span class="chip teal">Clear</span>'}</span></div>
        <div class="card-b"><div class="checklist">${checkHtml || '<span class="faint">No checks reported</span>'}</div>
        ${na.failed_tasks ? `<div style="margin-top:12px" class="alert-d">${icon('error', 'bad')} ${fmt(na.failed_tasks)} failed tasks in the log</div>` : ''}</div></div>
      <div class="card span-4"><div class="card-h"><span class="card-t">Fit distribution</span><span class="aside tnum">${fmt(tTotal)} scored</span></div><div class="card-b">${tierBar}</div></div>
      <div class="card span-4"><div class="card-h"><span class="card-t">Sources</span><span class="aside">${src.length} boards</span></div><div class="card-b">${srcHtml || '<div class="empty">No sources yet</div>'}</div></div>
    </div>`;
  };

  // ───────────────────────── View: Needs you (inbox) ─────────────────────────
  renderers.inbox = () => {
    const I = S.inbox;
    const tabs = [['questions', 'Questions', S.needs.length], ['ai', 'AI drafts', S.aiAnswers.length], ['triage', 'Triage', S.triage.length]];
    const seg = `<div class="seg" role="tablist">${tabs.map(([id, l, n]) => `<button role="tab" class="${I.tab === id ? 'on' : ''}" data-inbox-tab="${id}">${l} <span class="n">${n}</span></button>`).join('')}</div>`;
    let body = '';
    if (I.tab === 'questions') body = inboxQuestions();
    else if (I.tab === 'ai') body = inboxAI();
    else body = inboxTriage();
    return `${mobileHead('Needs You')}<div class="toolbar">${seg}<div class="spacer"></div><span class="faint" style="font-size:12px">${I.tab === 'triage' ? 'Q queue · X dismiss the first card' : I.tab === 'questions' ? 'J / K to move between questions' : ''}</span></div>${body}`;
  };

  function inboxQuestions() {
    const I = S.inbox;
    if (!S.needs.length) return `<div class="card"><div class="empty">${icon('task_alt')}<b>Nothing is waiting on you</b><span>When an application form asks something the Answer Bank can't answer, it lands here.</span>${S.aiAnswers.length ? `<button class="btn" data-inbox-tab="ai">Review ${S.aiAnswers.length} AI drafts</button>` : ''}</div></div>`;
    I.sel = Math.min(I.sel, S.needs.length - 1);
    const q = S.needs[I.sel];
    const list = S.needs.map((n, i) => `<button class="inbox-item ${i === I.sel ? 'sel' : ''}" data-q="${i}">
      <div class="mono-av" style="width:30px;height:30px;font-size:11px">${esc(initials(n.company))}</div>
      <div style="min-width:0"><div class="q">${esc(n.question_text)}</div><div class="meta">${esc(n.company)} · ${esc(n.role)} · ${rel(n.created_at)}</div></div></button>`).join('');
    const pick = I.picks[q.id] ?? q.suggested_answer ?? '';
    const opts = (q.options || []).filter(Boolean);
    const input = opts.length
      ? `<div class="opts">${opts.map(o => `<button class="opt ${pick === o ? 'on' : ''}" data-pick="${esc(o)}"><span>${esc(o)}</span>${icon('check_circle')}</button>`).join('')}</div>`
      : `<textarea class="textarea" id="q-answer" placeholder="Type the answer exactly as it should appear on the form">${esc(pick)}</textarea>`;
    return `<div class="inbox">
      <div class="card inbox-list">${list}</div>
      <div class="card qcard">
        <div class="who"><div class="mono-av lg">${esc(initials(q.company))}</div><div><div style="font-weight:600;font-size:15px">${esc(q.company)}</div><div class="muted" style="font-size:13px">${esc(q.role)}</div></div>
          <span class="chip" style="margin-left:auto">Question ${I.sel + 1} of ${S.needs.length}</span></div>
        <h2>${esc(q.question_text)}</h2>
        ${q.suggested_answer ? `<div class="faint" style="font-size:12px;margin:-8px 0 12px">${icon('auto_awesome')} Suggested: ${esc(q.suggested_answer)}</div>` : ''}
        ${input}
        <label class="remember"><div class="grow">Remember for future applications<small>Saves to the Answer Bank so similar fields are filled automatically</small></div>
          <span class="toggle"><input type="checkbox" id="q-remember" ${I.remember ? 'checked' : ''}><i></i></span></label>
        <div class="qactions">
          <button class="btn primary" data-act="q-resolve" data-id="${q.id}">Save & continue ${icon('arrow_forward')}</button>
          <button class="btn" data-act="q-dismiss" data-id="${q.id}" title="Skip this question and the job">Skip job</button>
          <button class="btn ghost danger" data-act="q-reject" data-id="${q.id}" data-company="${esc(q.company)}">Reject & block company</button>
          <button class="btn ghost" data-job="${q.job_id}" style="margin-left:auto">View job ${icon('open_in_new')}</button>
        </div>
      </div></div>`;
  }

  function inboxAI() {
    if (!S.aiAnswers.length) return `<div class="card"><div class="empty">${icon('verified')}<b>No AI drafts to review</b><span>Answers Gemini writes on the fly appear here until you approve them.</span></div></div>`;
    return `<div style="display:flex;flex-direction:column;gap:12px">${S.aiAnswers.map(a => `<div class="card" data-ai="${a.id}"><div class="card-b">
      <div style="display:flex;gap:10px;align-items:center;margin-bottom:8px"><span class="chip violet">${icon('auto_awesome')}AI draft</span><span class="muted" style="font-size:12px">${esc(a.company)}${a.role ? ' · ' + esc(a.role) : ''}</span>
        <span class="conf" style="margin-left:auto">Confidence <span class="bar"><i style="width:${Math.round((a.confidence || 0) * 100)}%;background:${a.confidence >= .85 ? 'var(--teal)' : 'var(--amber)'}"></i></span><span class="tnum">${Math.round((a.confidence || 0) * 100)}%</span></span></div>
      <div style="font-weight:600;font-size:15px;letter-spacing:-.01em">${esc(a.question)}</div>
      <div class="ai-answer" style="color:var(--ink-2);margin-top:6px;white-space:pre-wrap">${esc(a.answer)}</div>
      ${(a.facts_used || []).length ? `<div class="facts">${a.facts_used.slice(0, 6).map(f => `<span class="chip" title="${esc(f)}">${esc(String(f).slice(0, 48))}${String(f).length > 48 ? '…' : ''}</span>`).join('')}</div>` : ''}
      <div class="qactions" style="margin-top:14px">
        <button class="btn primary sm" data-act="ai-approve" data-id="${a.id}">${icon('check')}Approve</button>
        <button class="btn sm" data-act="ai-edit" data-id="${a.id}">${icon('edit')}Edit</button>
        <button class="btn sm ghost danger" data-act="ai-reject" data-id="${a.id}">Reject</button>
        <span class="faint" style="margin-left:auto;font-size:11px">${rel(a.created_at)}</span>
      </div></div></div>`).join('')}</div>`;
  }

  function inboxTriage() {
    if (!S.triage.length) return `<div class="card"><div class="empty">${icon('done_all')}<b>Triage is clear</b><span>Borderline matches (between your maybe and minimum fit scores) show up here for a quick yes / no.</span></div></div>`;
    return `<div class="triage">${S.triage.map(j => `<div class="card tcard" data-tcard="${j.id}">
      <div class="top"><div class="mono-av">${esc(initials(j.company))}</div>
        <div style="min-width:0;flex:1"><div style="font-weight:600">${esc(j.company)}</div><div class="muted" style="font-size:13px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${esc(j.title)}</div></div>${scoreTag(j.score)}</div>
      <div style="display:flex;gap:6px;flex-wrap:wrap"><span class="chip">${esc(j.location)}</span><span class="chip">${esc(j.source)}</span>${j.salary_raw ? `<span class="chip">${esc(j.salary_raw)}</span>` : ''}${j.is_assist_only ? '<span class="chip violet">Assist only</span>' : ''}</div>
      <div class="reason">${esc(j.score_reason || j.eligibility_reason || 'No scoring notes')}</div>
      <div class="acts"><button class="btn" data-act="swipe" data-action="dismiss" data-id="${j.id}">${icon('close')}Dismiss</button>
        <button class="btn primary" data-act="swipe" data-action="queue" data-id="${j.id}">${icon('playlist_add')}Queue</button>
        <button class="btn icon" data-job="${j.id}" title="Details">${icon('open_in_full')}</button></div></div>`).join('')}</div>`;
  }

  // ───────────────────────── View: Pipeline ─────────────────────────
  function filteredJobs() {
    const P = S.pipe, q = P.q.trim().toLowerCase();
    let list = (S.jobs || []).filter(j => {
      if (P.stage !== 'all' && stageOf(j.status).id !== P.stage) return false;
      if (P.source && j.source !== P.source) return false;
      if (P.min && j.score < Number(P.min)) return false;
      if (q && !`${j.company} ${j.title} ${j.location}`.toLowerCase().includes(q)) return false;
      return true;
    });
    const key = { score: j => j.score, company: j => j.company.toLowerCase(), updated: j => j.updated_at || '', title: j => j.title.toLowerCase() }[P.sort];
    list.sort((a, b) => { const x = key(a), y = key(b); return (x > y ? 1 : x < y ? -1 : 0) * P.dir; });
    return list;
  }

  renderers.pipeline = () => {
    const P = S.pipe, jobs = S.jobs || [];
    const counts = {}; jobs.forEach(j => { const s = stageOf(j.status).id; counts[s] = (counts[s] || 0) + 1; });
    const sources = [...new Set(jobs.map(j => j.source))].sort();
    const chips = `<div class="chips-scroll"><button class="filter-chip ${P.stage === 'all' ? 'on' : ''}" data-stage-f="all">All <span class="n">${fmt(jobs.length)}</span></button>${STAGES.map(s => `<button class="filter-chip ${P.stage === s.id ? 'on' : ''}" data-stage-f="${s.id}"><span class="dot ${s.color}"></span>${s.label} <span class="n">${fmt(counts[s.id] || 0)}</span></button>`).join('')}</div>`;
    const toolbar = `<div class="toolbar">
      <div class="search">${icon('search')}<input class="input" id="pipe-q" placeholder="Filter company, role, location" value="${esc(P.q)}"></div>
      <select class="select" id="pipe-src" style="width:140px"><option value="">All sources</option>${sources.map(s => `<option ${P.source === s ? 'selected' : ''} value="${esc(s)}">${esc(s)}</option>`).join('')}</select>
      <select class="select" id="pipe-min" style="width:130px"><option value="">Any score</option>${[4.5, 4, 3.5, 3].map(v => `<option ${String(P.min) === String(v) ? 'selected' : ''} value="${v}">Score ≥ ${v}</option>`).join('')}</select>
      <div class="spacer"></div>
      <button class="btn" data-act="evaluate" title="Score newly discovered jobs">${icon('analytics')}Score new</button>
      <div class="seg"><button class="${P.mode === 'table' ? 'on' : ''}" data-pipe-mode="table">${icon('table_rows')}Table</button><button class="${P.mode === 'board' ? 'on' : ''}" data-pipe-mode="board">${icon('view_kanban')}Board</button></div>
    </div>${chips}<div style="height:12px"></div>`;
    return `${mobileHead('Jobs', `<span class="faint tnum">${fmt(jobs.length)} tracked</span>`)}${toolbar}<div id="pipe-body">${P.mode === 'table' ? pipeTable() : pipeBoard()}</div>`;
  };

  function pipeTable() {
    const P = S.pipe, list = filteredJobs();
    if (!list.length) return `<div class="card"><div class="empty">${icon('search_off')}<b>No roles match these filters</b><button class="btn" data-act="pipe-reset">Reset filters</button></div></div>`;
    const th = (key, label, cls = '') => `<th class="sortable ${cls}" data-sort="${key}">${label}${P.sort === key ? icon(P.dir > 0 ? 'arrow_upward' : 'arrow_downward') : ''}</th>`;
    const rows = list.slice(0, P.limit).map(j => `<tr data-job="${j.id}" class="${S.jobId === j.id ? 'sel' : ''}">
      <td><div class="co"><div class="mono-av">${esc(initials(j.company))}</div><div style="min-width:0"><div style="font-weight:600;overflow:hidden;text-overflow:ellipsis">${esc(j.title)}</div><div class="muted" style="font-size:12px">${esc(j.company)}</div></div></div></td>
      <td>${statusChip(j.status)}</td>
      <td class="r">${scoreTag(j.score)}</td>
      <td class="hide-m muted" style="text-transform:capitalize">${esc(j.source)}</td>
      <td class="hide-m muted loc" title="${esc(j.location)}">${esc(j.location)}</td>
      <td class="hide-m muted">${esc(j.salary_raw || (j.stipend_raw ? j.stipend_raw + ' stipend' : '—'))}</td>
      <td class="hide-m faint tnum">${rel(j.updated_at)}</td></tr>`).join('');
    return `<div class="card"><div class="table-wrap"><table class="tbl"><thead><tr>${th('title', 'Role')}<th>Stage</th>${th('score', 'Score', 'r')}<th class="hide-m">Source</th><th class="hide-m">Location</th><th class="hide-m">Pay</th>${th('updated', 'Updated', 'hide-m')}</tr></thead><tbody>${rows}</tbody></table></div>
      <div class="table-foot"><span class="tnum">Showing ${fmt(Math.min(P.limit, list.length))} of ${fmt(list.length)}</span>${list.length > P.limit ? `<button class="btn sm" data-act="pipe-more">Show more</button>` : ''}</div></div>`;
  }

  function pipeBoard() {
    const P = S.pipe, list = filteredJobs();
    const lanes = STAGES.filter(s => P.stage === 'all' || s.id === P.stage);
    return `<div class="board">${lanes.map(s => {
      const items = list.filter(j => stageOf(j.status).id === s.id);
      const lim = P.laneLimit[s.id] || 25;
      return `<div class="lane"><div class="lane-h"><span class="dot ${s.color}"></span>${s.label}<span class="n">${fmt(items.length)}</span></div>
        <div class="lane-b">${items.slice(0, lim).map(j => `<button class="jcard ${S.jobId === j.id ? 'sel' : ''}" data-job="${j.id}">
          <div class="t1"><span>${esc(j.company)}</span>${scoreTag(j.score)}</div><div class="t2">${esc(j.title)}</div>
          <div class="t3">${s.statuses.length > 1 || s.id === 'closed' ? statusChip(j.status) : ''}<span class="chip">${esc(j.source)}</span>${j.is_assist_only ? '<span class="chip violet">Assist</span>' : ''}</div></button>`).join('') || '<div class="empty" style="padding:20px 8px">Empty</div>'}
        ${items.length > lim ? `<button class="btn sm ghost lane-more" data-act="lane-more" data-lane="${s.id}">+ ${fmt(items.length - lim)} more</button>` : ''}</div></div>`;
    }).join('')}</div>`;
  }

  afterRender.pipeline = () => {
    const rerender = () => { $('#pipe-body').innerHTML = S.pipe.mode === 'table' ? pipeTable() : pipeBoard(); };
    const q = $('#pipe-q');
    q && q.addEventListener('input', debounce(e => { S.pipe.q = e.target.value; S.pipe.limit = 100; rerender(); }, 120));
    $('#pipe-src') && $('#pipe-src').addEventListener('change', e => { S.pipe.source = e.target.value; rerender(); });
    $('#pipe-min') && $('#pipe-min').addEventListener('change', e => { S.pipe.min = e.target.value; rerender(); });
  };

  // ───────────────────────── Inspector (job detail) ─────────────────────────
  async function openJob(id) {
    id = Number(id);
    S.jobId = id;
    const insp = $('#inspector');
    insp.innerHTML = `<div class="insp-h"><span class="eyebrow">Job</span><div style="flex:1"></div><button class="btn icon ghost" data-act="close-insp">${icon('close')}</button></div><div class="insp-b"><div class="skel" style="height:60px"></div><div class="skel" style="height:120px"></div><div class="skel" style="height:180px"></div></div>`;
    insp.classList.add('on'); $('#scrim').classList.add('on');
    $$('[data-job]').forEach(el => el.classList.toggle('sel', Number(el.dataset.job) === id));
    try {
      const j = await api(`/jobs/${id}`);
      if (S.jobId !== id) return;
      S.job = j; renderInspector();
    } catch (e) {
      insp.querySelector('.insp-b').innerHTML = `<div class="empty">${icon('error')}<b>Couldn't load this job</b><span>${esc(e.message)}</span></div>`;
    }
  }
  function closeJob() {
    S.jobId = null; S.job = null;
    $('#inspector').classList.remove('on'); $('#scrim').classList.remove('on');
    $$('[data-job].sel').forEach(el => el.classList.remove('sel'));
  }
  function renderInspector() {
    const j = S.job; if (!j) return;
    const st = stageOf(j.status).id;
    const fits = [['Skills', j.skills_score, 'skills'], ['Experience', j.experience_score, 'experience'], ['Education', j.education_score, 'education'], ['Location', j.location_score, 'location'], ['Compensation', j.compensation_score, 'compensation'], ['Role relevance', j.role_relevance_score, 'role_relevance']];
    const fb = j.fit_breakdown || {};
    const hasFit = fits.some(f => f[1] > 0);
    const fitHtml = hasFit ? fits.map(([l, v, k]) => `<div class="fit-row" title="${esc(fb[k] || '')}"><span>${l}</span><div class="bar"><i style="width:${Math.min(100, v)}%;background:${v >= 80 ? 'var(--teal)' : v >= 60 ? 'var(--indigo)' : v >= 40 ? 'var(--amber)' : 'var(--coral)'}"></i></div><span>${Math.round(v)}</span></div>`).join('') : '<div class="faint" style="font-size:13px">Not scored yet. Run "Score new" from the pipeline.</div>';
    const skills = (arr, cls) => (arr || []).map(s => `<span class="chip ${cls}">${esc(s)}</span>`).join('');
    const apps = (j.applications || []).map(a => `<div class="tl ${a.status === 'submitted' ? 'teal' : a.status === 'failed' ? 'coral' : 'indigo'}">
      <b>${esc(STATUS_LABEL[a.status] || a.status)}</b> <span class="faint">${esc(stamp(a.submitted_at || a.applied_at))}</span>
      ${a.failure_reason ? `<small>${esc(a.failure_reason)}</small>` : ''}
      <small>${a.form_screenshot_url ? `<a href="${esc(a.form_screenshot_url)}" target="_blank" rel="noopener">Form screenshot</a>` : ''}${a.confirmation_screenshot_url && a.confirmation_screenshot_url !== a.form_screenshot_url ? ` · <a href="${esc(a.confirmation_screenshot_url)}" target="_blank" rel="noopener">Confirmation</a>` : ''}</small></div>`).join('');
    const timeline = `<div class="tl"><b>Discovered</b> <span class="faint">${esc(stamp(j.created_at))}</span><small>via ${esc(j.source)}</small></div>
      ${j.score > 0 ? `<div class="tl indigo"><b>Scored ${Number(j.score).toFixed(1)}</b><small>${esc(j.eligibility_status.replace(/_/g, ' '))}</small></div>` : ''}${apps}
      ${j.skip_reason ? `<div class="tl coral"><b>Skipped</b><small>${esc(j.skip_reason)}</small></div>` : ''}
      ${j.blocked_reason ? `<div class="tl coral"><b>Blocked</b><small>${esc(j.blocked_reason)}</small></div>` : ''}`;

    let primary = '', secondary = '';
    if (j.is_assist_only && !['submitted', 'interview'].includes(st)) {
      primary = `<a class="btn primary" href="${esc(j.url)}" target="_blank" rel="noopener">${icon('open_in_new')}Open & apply myself</a>`;
      secondary = `<button class="btn" data-act="mark-applied" data-id="${j.id}">${icon('done')}Mark applied</button>`;
    } else if (st === 'triage' || st === 'new') {
      primary = `<button class="btn primary" data-act="swipe" data-action="queue" data-id="${j.id}">${icon('playlist_add')}Queue</button>`;
      secondary = `<button class="btn" data-act="swipe" data-action="dismiss" data-id="${j.id}">Dismiss</button>`;
    } else if (st === 'queued') {
      primary = `<button class="btn primary" data-act="apply" data-id="${j.id}">${icon('bolt')}Apply now</button>`;
      secondary = `<button class="btn" data-act="swipe" data-action="dismiss" data-id="${j.id}">Remove</button>`;
    } else {
      primary = `<a class="btn primary" href="${esc(j.url)}" target="_blank" rel="noopener">${icon('open_in_new')}Open posting</a>`;
    }
    const statusOpts = ['discovered', 'maybe', 'queued', 'needs_review', 'applied', 'interview', 'offer', 'rejected', 'dismissed', 'skipped'];
    if (!statusOpts.includes(j.status)) statusOpts.unshift(j.status);

    $('#inspector').innerHTML = `
      <div class="insp-h">${statusChip(j.status)}<div style="flex:1"></div>
        <button class="btn icon ghost" data-act="save-job" data-id="${j.id}" title="${j.is_saved ? 'Unsave' : 'Save'}">${icon('bookmark', j.is_saved ? 'fill' : '')}</button>
        <a class="btn icon ghost" href="${esc(j.url)}" target="_blank" rel="noopener" title="Open posting">${icon('open_in_new')}</a>
        <button class="btn icon ghost" data-act="close-insp" title="Close (Esc)">${icon('close')}</button></div>
      <div class="insp-b">
        <div class="jd-head"><div class="mono-av lg">${esc(initials(j.company))}</div><div style="min-width:0"><h2>${esc(j.title)}</h2><div class="co">${esc(j.company)}</div></div>
          ${j.score > 0 ? `<div class="score-ring">${ring(j.score / 5, 52, 4, scoreColor(j.score))}<div>${Number(j.score).toFixed(1)}</div></div>` : ''}</div>
        <div class="meta-grid">
          <div><small>Location</small><span>${esc(j.location)}</span></div><div><small>Work mode</small><span style="text-transform:capitalize">${esc(j.work_mode)}</span></div>
          <div><small>Pay</small><span>${esc(j.salary_raw || j.stipend_raw || 'Not listed')}</span></div><div><small>Experience</small><span>${esc(j.experience_required)}</span></div>
          <div><small>Source</small><span style="text-transform:capitalize">${esc(j.source)}${j.is_assist_only ? ' · assist only' : ''}</span></div><div><small>Readiness</small><span class="tnum">${Math.round(j.quality_readiness_score)}%</span></div>
        </div>
        ${j.score_reason || j.eligibility_reason ? `<div class="card"><div class="card-b"><div class="eyebrow" style="margin-bottom:6px">Why this fits</div><div style="font-size:13px;line-height:1.5">${esc(j.score_reason || j.eligibility_reason)}</div></div></div>` : ''}
        <div class="card"><div class="card-b"><div class="eyebrow" style="margin-bottom:8px">Fit breakdown</div>${fitHtml}</div></div>
        ${(j.matching_skills || []).length || (j.missing_skills || []).length ? `<div class="card"><div class="card-b"><div class="eyebrow" style="margin-bottom:8px">Skills</div><div class="skills">${skills(j.matching_skills, 'teal')}${skills(j.missing_skills, 'coral')}</div></div></div>` : ''}
        <div class="card"><div class="card-b"><div class="eyebrow" style="margin-bottom:10px">Timeline</div><div class="timeline">${timeline}</div></div></div>
        <div class="card"><div class="card-b" style="display:flex;flex-direction:column;gap:10px">
          <div class="eyebrow">Manage</div>
          <div class="field"><label>Stage</label><select class="select" id="insp-status">${statusOpts.map(s => `<option value="${s}" ${s === j.status ? 'selected' : ''}>${esc(STATUS_LABEL[s] || s)}</option>`).join('')}</select></div>
          <div class="field"><label>Notes</label><textarea class="textarea" id="insp-notes" placeholder="Recruiter name, referral, follow-up…" style="min-height:64px">${esc(j.notes)}</textarea></div>
          <div style="display:flex;gap:8px;flex-wrap:wrap"><button class="btn sm" data-act="save-status" data-id="${j.id}">${icon('save')}Save</button>
            <button class="btn sm" data-act="tailor" data-id="${j.id}">${icon('description')}Tailor resume</button>
            ${st !== 'closed' ? `<button class="btn sm ghost danger" data-act="swipe" data-action="exclude" data-id="${j.id}">Exclude company</button>` : ''}</div>
        </div></div>
      </div>
      <div class="insp-f">${secondary}${primary}</div>`;
  }

  // ───────────────────────── View: Answers ─────────────────────────
  const MODES = ['always_use', 'ask me to review'];
  const CATS = { personal: 'Personal contact', education: 'Education & credentials', work_auth: 'Work authorization', technical: 'Technical skills & projects', behavioral: 'Behavioral', demographics: 'Demographics & disclosures', preferences: 'Preferences & pay', general: 'General', custom: 'Custom', ai_suggestion: 'AI suggestions' };
  const catName = (c) => CATS[c] || String(c).replace(/_/g, ' ').replace(/^./, m => m.toUpperCase());

  renderers.answers = () => {
    const A = S.ans, all = S.answers || [];
    const counts = {}; all.forEach(a => { counts[a.category] = (counts[a.category] || 0) + 1; });
    const cats = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);
    const q = A.q.trim().toLowerCase();
    const list = all.filter(a => (A.cat === 'all' || a.category === A.cat) && (!q || `${a.question_text} ${a.answer}`.toLowerCase().includes(q)));
    const groups = {}; list.forEach(a => (groups[a.category] = groups[a.category] || []).push(a));
    const order = cats.filter(c => groups[c]);
    const addForm = A.adding ? `<div class="card" style="margin-bottom:16px"><div class="card-b">${answerForm({ question_text: '', answer: '', category: A.cat !== 'all' ? A.cat : 'custom', mode: 'always_use' }, 'new')}</div></div>` : '';
    const body = order.length ? order.map(c => `<div class="ans-group"><span class="eyebrow">${esc(catName(c))} · ${groups[c].length}</span><div class="card list">${groups[c].map(answerRow).join('')}</div></div>`).join('')
      : `<div class="card"><div class="empty">${icon('search_off')}<b>No answers match</b></div></div>`;
    return `${mobileHead('Answers')}<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="ans-q" placeholder="Search questions or answers" value="${esc(A.q)}"></div>
      <div class="spacer"></div><span class="faint tnum" style="font-size:12px">${fmt(all.length)} saved · ${fmt(all.reduce((s, a) => s + (a.usage_count || 0), 0))} auto-fills</span>
      <button class="btn primary" data-act="ans-add">${icon('add')}New answer</button></div>
      <div class="ans-layout"><div class="cat-list"><button class="${A.cat === 'all' ? 'on' : ''}" data-cat="all">All <span class="n">${all.length}</span></button>${cats.map(c => `<button class="${A.cat === c ? 'on' : ''}" data-cat="${esc(c)}">${esc(catName(c))} <span class="n">${counts[c]}</span></button>`).join('')}</div>
      <div id="ans-body">${addForm}${body}</div></div>`;
  };
  function answerRow(a) {
    if (S.ans.editing === a.id) return `<div class="ans-row">${answerForm(a, a.id)}</div>`;
    const review = a.mode !== 'always_use';
    return `<div class="ans-row"><div style="min-width:0"><div class="q">${esc(a.question_text)}</div><div class="a">${esc(a.answer) || '<span class="faint">(empty)</span>'}</div></div>
      <div class="end"><div class="act"><button class="btn sm icon ghost" data-act="ans-edit" data-id="${a.id}" title="Edit">${icon('edit')}</button><button class="btn sm icon ghost danger" data-act="ans-del" data-id="${a.id}" title="Delete">${icon('delete')}</button></div>
        ${a.source === 'gemini' ? '<span class="chip violet">AI</span>' : ''}<span class="chip ${review ? 'amber' : ''}">${review ? 'Review' : 'Always use'}</span>
        <span class="faint tnum" style="font-size:11px;width:34px;text-align:right" title="Times auto-filled">${a.usage_count ? '×' + a.usage_count : ''}</span></div></div>`;
  }
  function answerForm(a, id) {
    const modes = MODES.includes(a.mode) ? MODES : [a.mode, ...MODES];
    const cats = Object.keys(CATS).includes(a.category) ? Object.keys(CATS) : [a.category, ...Object.keys(CATS)];
    return `<form class="ans-edit" data-ans-form="${id}">
      <div class="field"><label>Question</label><input class="input" name="question_text" value="${esc(a.question_text)}" required></div>
      <div class="field"><label>Answer</label><textarea class="textarea" name="answer" required>${esc(a.answer)}</textarea></div>
      <div class="row2"><div class="field"><label>Category</label><select class="select" name="category">${cats.map(c => `<option value="${esc(c)}" ${c === a.category ? 'selected' : ''}>${esc(catName(c))}</option>`).join('')}</select></div>
        <div class="field"><label>When filling forms</label><select class="select" name="mode">${modes.map(m => `<option value="${esc(m)}" ${m === a.mode ? 'selected' : ''}>${m === 'always_use' ? 'Always use' : m === 'ask me to review' ? 'Ask me to review' : esc(m)}</option>`).join('')}</select></div></div>
      <div style="display:flex;gap:8px;justify-content:flex-end"><button type="button" class="btn ghost" data-act="ans-cancel">Cancel</button><button type="submit" class="btn primary">${id === 'new' ? 'Add answer' : 'Save'}</button></div></form>`;
  }
  afterRender.answers = () => {
    const q = $('#ans-q');
    q && q.addEventListener('input', debounce(e => { S.ans.q = e.target.value; const pos = e.target.selectionStart; render(); const n = $('#ans-q'); n.focus(); n.setSelectionRange(pos, pos); }, 150));
    const f = $('[data-ans-form] [name=answer]'); if (f && (S.ans.adding || S.ans.editing)) { const t = $('[data-ans-form] [name=question_text]'); (S.ans.adding ? t : f).focus(); }
  };

  // ───────────────────────── View: Activity ─────────────────────────
  renderers.activity = () => {
    const A = S.act, q = A.q.trim().toLowerCase();
    const norm = (l) => l === 'warning' ? 'warn' : l;
    const counts = { all: S.logs.length }; S.logs.forEach(l => { const k = norm(l.level); counts[k] = (counts[k] || 0) + 1; });
    const list = S.logs.filter(l => (A.level === 'all' || norm(l.level) === A.level) && (!q || `${l.message} ${l.event_type} ${l.company}`.toLowerCase().includes(q)));
    const rows = list.map(l => `<tr style="cursor:default"><td class="faint tnum mono">${esc(l.created_at)}</td><td><span class="lvl ${esc(l.level)}">${esc(l.level)}</span></td>
      <td class="hide-m"><span class="chip">${esc(l.event_type)}</span></td><td class="msg"><span class="dot ${logColor(l)}" style="margin-right:8px"></span>${esc(l.message)}</td></tr>`).join('');
    return `${mobileHead('Activity')}<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="act-q" placeholder="Filter log" value="${esc(A.q)}"></div>
      <div class="seg">${['all', 'info', 'warn', 'error'].map(l => `<button class="${A.level === l ? 'on' : ''}" data-level="${l}">${l[0].toUpperCase() + l.slice(1)} <span class="n">${counts[l] || 0}</span></button>`).join('')}</div>
      <div class="spacer"></div><span class="faint" style="font-size:12px;display:flex;align-items:center;gap:6px"><span class="dot teal pulse"></span>Auto-refreshing</span>
      <button class="btn" data-act="backup">${icon('backup')}Back up now</button></div>
      <div class="card"><div class="table-wrap"><table class="tbl log-tbl"><thead><tr><th style="width:150px">Time</th><th style="width:70px">Level</th><th class="hide-m" style="width:150px">Event</th><th>Message</th></tr></thead>
      <tbody>${rows || `<tr><td colspan="4"><div class="empty">No log entries</div></td></tr>`}</tbody></table></div></div>`;
  };
  afterRender.activity = () => {
    const q = $('#act-q');
    q && q.addEventListener('input', debounce(e => { S.act.q = e.target.value; const pos = e.target.selectionStart; render(); const n = $('#act-q'); n.focus(); n.setSelectionRange(pos, pos); }, 150));
  };

  // ───────────────────────── View: Profile & rules ─────────────────────────
  renderers.settings = () => {
    const p = S.profile; if (!p) return errorView(new Error('Profile not available'));
    const g = S.gemini || {}, st = S.stats || {}, au = S.automation || {};
    const f = (name, label, opts = {}) => {
      const v = p[name] ?? '';
      const type = opts.type || 'text';
      const val = Array.isArray(v) ? v.join(', ') : v;
      return `<div class="field ${opts.full ? 'full' : ''}"><label for="f-${name}">${label}</label><input class="input ${type === 'number' ? 'tnum' : ''}" id="f-${name}" name="${name}" type="${type}" ${opts.step ? `step="${opts.step}"` : ''} ${opts.min !== undefined ? `min="${opts.min}"` : ''} ${opts.max !== undefined ? `max="${opts.max}"` : ''} value="${esc(val)}" data-kind="${Array.isArray(v) ? 'list' : type}">${opts.hint ? `<span class="hint">${opts.hint}</span>` : ''}</div>`;
    };
    const tg = (name, label, hint) => `<label class="set-row"><div class="grow">${label}${hint ? `<small>${hint}</small>` : ''}</div><span class="toggle"><input type="checkbox" name="${name}" ${p[name] ? 'checked' : ''}><i></i></span></label>`;
    return `${mobileHead('Profile')}
    <div class="settings">
      <div style="display:flex;flex-direction:column;gap:12px">
        <div class="card"><div class="profile-hero"><div class="mono-av">${esc(initials(p.full_name))}</div><div style="min-width:0"><h2>${esc(p.full_name)}</h2><div class="muted" style="font-size:13px">${esc(p.education)} · CGPA ${esc(p.cgpa)}</div></div></div></div>

        <form class="card" data-profile-form="engine"><div class="card-h"><span class="card-t">Engine</span><span class="aside">${st.go_live ? '<span class="chip coral">Live submissions</span>' : '<span class="chip">Dry run</span>'}</span></div>
          <div class="list" style="margin-top:8px">
            <div class="set-row"><div class="grow">Live submissions<small>${st.go_live ? 'Applications are really submitted to employers.' : 'Forms are filled and screenshotted but never submitted.'}</small></div><button type="button" class="btn sm ${st.go_live ? 'danger' : ''}" data-act="${st.go_live ? 'mode-dry' : 'mode-live'}">${st.go_live ? 'Switch to dry run' : 'Go live…'}</button></div>
            <div class="set-row"><div class="grow">Queue<small>${esc(engineLabel(st)[0])}${au.affected_queue_count ? ` · ${au.affected_queue_count} jobs waiting` : ''}</small></div><button type="button" class="btn sm" data-act="${st.is_paused ? 'resume' : 'pause'}">${st.is_paused ? 'Resume' : 'Pause'}</button></div>
          </div>
          <div class="card-b form-grid" style="border-top:1px solid var(--line)">
            ${f('daily_cap', 'Daily cap', { type: 'number', min: 0 })}${f('daily_target', 'Daily target', { type: 'number', min: 0 })}
            ${f('hourly_cap', 'Hourly cap', { type: 'number', min: 0 })}${f('timezone', 'Timezone')}
            ${f('active_hours_start', 'Active from (hour)', { type: 'number', min: 0, max: 23 })}${f('active_hours_end', 'Active until (hour)', { type: 'number', min: 0, max: 24 })}
            ${f('min_fit_score', 'Auto-queue at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Jobs at or above this are queued automatically' })}${f('maybe_fit_score', 'Triage at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Between the two lands in Needs you › Triage' })}
            <div class="full" style="display:flex;justify-content:flex-end"><button class="btn primary" type="submit">Save engine rules</button></div>
          </div></form>

        <form class="card" data-gemini-form><div class="card-h"><span class="card-t">Gemini auto-answer</span><span class="aside tnum">${fmt(g.gemini_answers_today || 0)} today · ~${fmt(g.saved_minutes || 0)} min saved</span></div>
          <div class="list" style="margin-top:8px"><label class="set-row"><div class="grow">Draft answers for unknown questions<small>Grounded only in your locked facts. Drafts wait in Needs you › AI drafts.</small></div><span class="toggle"><input type="checkbox" name="gemini_auto_answer_enabled" ${g.gemini_auto_answer_enabled ? 'checked' : ''}><i></i></span></label></div>
          <div class="card-b form-grid" style="border-top:1px solid var(--line)">
            <div class="field"><label>Minimum confidence</label><div class="range-row"><input type="range" name="gemini_min_confidence" min="0.5" max="1" step="0.01" value="${g.gemini_min_confidence ?? 0.85}" oninput="this.nextElementSibling.value=Math.round(this.value*100)+'%'"><output>${Math.round((g.gemini_min_confidence ?? 0.85) * 100)}%</output></div></div>
            <div class="field"><label>Daily answer cap</label><input class="input tnum" type="number" name="gemini_daily_cap" min="0" value="${g.gemini_daily_cap ?? 30}"></div>
            <div class="field full"><label>Always asks you about</label><div class="tags">${(g.gemini_sensitive_categories || []).map(c => `<span class="chip">${esc(c.replace(/_/g, ' '))}</span>`).join('')}</div></div>
            <div class="full" style="display:flex;justify-content:space-between;align-items:center"><span class="faint" style="font-size:12px">${esc(g.model_name || '')}${g.circuit_breaker_active ? ' · <span class="bad">rate-limit breaker active</span>' : ''}</span><button class="btn primary" type="submit">Save</button></div>
          </div></form>
      </div>

      <div style="display:flex;flex-direction:column;gap:12px">
        <form class="card" data-profile-form="targeting"><div class="card-h"><span class="card-t">Targeting</span></div>
          <div class="card-b form-grid">
            ${f('target_roles', 'Target roles', { full: true, hint: 'Comma separated' })}
            ${f('locations', 'Locations', { full: true, hint: 'Comma separated' })}
            ${f('excluded_companies', 'Never apply to', { full: true, hint: 'Comma separated' })}
            ${f('min_salary_inr', 'Minimum salary (₹ / year)', { type: 'number', min: 0 })}${f('min_stipend_inr', 'Minimum stipend (₹ / month)', { type: 'number', min: 0 })}
            ${f('preferred_work_mode', 'Work mode', { full: true })}
          </div>
          <div class="list" style="border-top:1px solid var(--line)">${tg('allow_unknown_salary', 'Apply when pay is not listed')}${tg('allow_unpaid_internships', 'Allow unpaid internships')}</div>
          <div class="card-b" style="display:flex;justify-content:flex-end;padding-top:0"><button class="btn primary" type="submit">Save targeting</button></div></form>

        <form class="card" data-profile-form="contact"><div class="card-h"><span class="card-t">Contact & credentials</span><span class="aside">Used verbatim on forms</span></div>
          <div class="card-b form-grid">
            ${f('full_name', 'Full name')}${f('email', 'Email', { type: 'email' })}
            ${f('phone', 'Phone')}${f('cgpa', 'CGPA')}
            ${f('education', 'Education', { full: true })}
            ${f('linkedin', 'LinkedIn', { full: true })}${f('github', 'GitHub', { full: true })}
            ${f('graduation_date', 'Graduation date')}${f('notice_period', 'Notice period')}
            ${f('work_authorization', 'Work authorization')}${f('relocation_preference', 'Relocation')}
            <div class="full" style="display:flex;justify-content:flex-end"><button class="btn primary" type="submit">Save contact</button></div>
          </div></form>

        <div class="card"><div class="card-h"><span class="card-t">Resume versions</span><span class="aside">${S.resumes.length}</span></div>
          <div class="list" style="margin-top:8px">${S.resumes.map(r => `<div class="row"><div class="mono-av">${icon('description')}</div>
            <div class="grow"><div class="main-t">${esc(r.version_name)}</div><div class="sub-t">${esc(r.target_role)} · ATS ${Math.round(r.ats_score)}</div></div>
            <div class="end">${r.is_master ? '<span class="chip teal">Master</span>' : ''}${r.pdf_path ? `<a class="btn sm icon ghost" href="${esc(r.pdf_path)}" target="_blank" rel="noopener" title="Open PDF">${icon('open_in_new')}</a>` : ''}</div></div>`).join('') || '<div class="empty">No resume versions</div>'}</div></div>
        ${IN_SHELL ? `<div class="card"><div class="list"><div class="set-row"><div class="grow">Phone app connection<small>${esc(location.host)}</small></div><button type="button" class="btn sm" data-act="shell-server">Change server</button></div></div></div>` : ''}
      </div>
    </div>`;
  };

  const PROFILE_SECTIONS = {
    engine: ['daily_cap', 'daily_target', 'hourly_cap', 'timezone', 'active_hours_start', 'active_hours_end', 'min_fit_score', 'maybe_fit_score'],
    targeting: ['target_roles', 'locations', 'excluded_companies', 'min_salary_inr', 'min_stipend_inr', 'preferred_work_mode', 'allow_unknown_salary', 'allow_unpaid_internships'],
    contact: ['full_name', 'email', 'phone', 'cgpa', 'education', 'linkedin', 'github', 'graduation_date', 'notice_period', 'work_authorization', 'relocation_preference'],
  };

  // ───────────────────────── Actions ─────────────────────────
  async function refreshAfterJobChange() {
    loadStats();
    if (S.view === 'pipeline') { S.jobs = await api('/jobs'); $('#pipe-body') ? ($('#pipe-body').innerHTML = S.pipe.mode === 'table' ? pipeTable() : pipeBoard()) : render(); }
    else if (S.view === 'inbox' || S.view === 'today') { await loaders[S.view](); render(); }
  }

  async function setMode(live) {
    const st = S.stats; if (!st || st.go_live === live) return;
    if (live) {
      const ok = await confirmModal({ title: 'Turn on live submissions?', body: 'ApplyPilot will <b>really submit</b> applications to employers within your caps and rules. Submissions can’t be withdrawn from here. You can switch back to dry run at any time.', ok: 'Go live', danger: true });
      if (!ok) return;
    }
    await run(null, () => api('/profile/toggle-go-live', { method: 'POST' }), r => r.go_live ? 'Live submissions on' : 'Back to dry run');
    await loadStats(); if (S.view === 'settings' || S.view === 'today') go(S.view, { silent: true });
  }

  const actions = {
    reload: () => go(S.view),
    'close-insp': closeJob,
    'mode-dry': () => setMode(false),
    'mode-live': () => setMode(true),
    async pause(btn) {
      await run(btn, () => api('/automation/pause', { method: 'POST', query: { reason: 'paused_by_user', details: 'Paused from command center' } }), 'Engine paused');
      await loadStats(); if (['today', 'settings'].includes(S.view)) go(S.view, { silent: true });
    },
    async resume(btn) {
      let r = await run(btn, () => api('/automation/resume', { method: 'POST' }));
      if (r === undefined) {
        const force = await confirmModal({ title: 'Pre-flight failed', body: 'A safety check is blocking resume (see the error). Override and resume anyway? The circuit breaker will be reset.', ok: 'Override & resume', danger: true });
        if (!force) return;
        r = await run(btn, () => api('/automation/resume', { method: 'POST', query: { force: true } }));
        if (r === undefined) return;
      }
      toast('Engine running');
      await loadStats(); if (['today', 'settings'].includes(S.view)) go(S.view, { silent: true });
    },
    async discover(btn) {
      await run(btn, () => api('/jobs/discover', { method: 'POST' }), r => `Discovery finished · ${fmt(r.new_jobs_discovered)} new roles`);
      refreshAfterJobChange();
    },
    async evaluate(btn) {
      await run(btn, () => api('/jobs/evaluate', { method: 'POST' }), r => `Scored ${fmt(r.jobs_scored)} roles`);
      refreshAfterJobChange();
    },
    async 'apply-next'(btn) {
      if (S.stats && S.stats.go_live) {
        const ok = await confirmModal({ title: 'Apply to the next queued job?', body: 'Live mode is on — this will <b>really submit</b> an application.', ok: 'Submit', danger: true });
        if (!ok) return;
      }
      const r = await run(btn, () => api('/jobs/apply-next', { method: 'POST' }));
      if (r) toast(r.message || (r.company ? `Processed ${r.company}` : 'Done'));
      refreshAfterJobChange();
    },
    async apply(btn) {
      const id = btn.dataset.id, live = S.stats && S.stats.go_live;
      const ok = await confirmModal({ title: live ? 'Submit this application?' : 'Run a dry-run application?', body: live ? `Live mode is on — ApplyPilot will <b>really submit</b> to ${esc(S.job ? S.job.company : 'this employer')}.` : 'The form will be filled and screenshotted but not submitted.', ok: live ? 'Submit' : 'Run dry run', danger: live });
      if (!ok) return;
      const r = await run(btn, () => api(`/jobs/${id}/apply`, { method: 'POST' }));
      if (r) toast(r.message || `${r.company || 'Job'}: ${typeof r.result === 'object' ? (r.result.status || 'done') : (r.result || 'done')}`);
      openJob(id); refreshAfterJobChange();
    },
    async swipe(btn) {
      const id = btn.dataset.id, action = btn.dataset.action;
      if (action === 'exclude') {
        const ok = await confirmModal({ title: 'Exclude this company?', body: 'The company is added to your never-apply list and this job is blocked.', ok: 'Exclude', danger: true });
        if (!ok) return;
      }
      const card = btn.closest('[data-tcard]');
      const r = await run(btn, () => api(`/jobs/${id}/swipe`, { method: 'POST', body: { action } }), { queue: 'Queued', dismiss: 'Dismissed', exclude: 'Company excluded' }[action]);
      if (r === undefined) return;
      if (card) { card.classList.add(action === 'queue' ? 'out-r' : 'out-l'); await new Promise(res => setTimeout(res, 220)); }
      S.triage = S.triage.filter(j => String(j.id) !== String(id));
      if (S.jobId === Number(id)) openJob(id);
      refreshAfterJobChange();
    },
    async 'mark-applied'(btn) {
      await run(btn, () => api(`/jobs/${btn.dataset.id}/mark-applied`, { method: 'POST' }), 'Marked as applied');
      openJob(btn.dataset.id); refreshAfterJobChange();
    },
    async 'save-job'(btn) {
      await run(btn, () => api(`/jobs/${btn.dataset.id}/toggle-save`, { method: 'POST' }));
      openJob(btn.dataset.id);
    },
    async 'save-status'(btn) {
      const status = $('#insp-status').value, notes = $('#insp-notes').value;
      await run(btn, () => api(`/jobs/${btn.dataset.id}/status`, { method: 'PUT', body: { status, notes } }), 'Saved');
      openJob(btn.dataset.id); refreshAfterJobChange();
    },
    async tailor(btn) {
      const r = await run(btn, () => api(`/jobs/${btn.dataset.id}/tailor`, { method: 'POST' }), r => `Resume tailored · ATS ${Math.round(r.ats_score)} · ${Math.round(r.keyword_coverage_percent)}% keywords`);
      if (r && r.pdf_path) { const m = String(r.pdf_path).replace(/\\/g, '/').match(/output\/.*$/); if (m) window.open('/' + m[0], '_blank', 'noopener'); }
    },
    // Inbox
    async 'q-resolve'(btn) {
      const id = Number(btn.dataset.id);
      const ta = $('#q-answer');
      const answer = (ta ? ta.value : (S.inbox.picks[id] ?? (S.needs.find(n => n.id === id) || {}).suggested_answer ?? '')).trim();
      if (!answer) { toast('Pick or type an answer first', true); return; }
      const remember = $('#q-remember') ? $('#q-remember').checked : true;
      S.inbox.remember = remember;
      const r = await run(btn, () => api(`/needs-you/${id}/resolve`, { method: 'POST', body: { answer, save_to_answer_bank: remember, mode: 'always_use' } }), 'Answer saved · application resuming');
      if (r === undefined) return;
      S.needs = S.needs.filter(n => n.id !== id); render(); loadStats();
    },
    async 'q-dismiss'(btn) {
      const id = Number(btn.dataset.id);
      const r = await run(btn, () => api(`/needs-you/${id}/dismiss`, { method: 'POST' }), 'Skipped');
      if (r === undefined) return;
      S.needs = S.needs.filter(n => n.id !== id); render(); loadStats();
    },
    async 'q-reject'(btn) {
      const id = Number(btn.dataset.id);
      const ok = await confirmModal({ title: `Reject and block ${btn.dataset.company}?`, body: 'This application is dropped and the company is added to your never-apply list.', ok: 'Reject & block', danger: true });
      if (!ok) return;
      const r = await run(btn, () => api(`/needs-you/${id}/reject`, { method: 'POST', body: { block_company: true, reason: 'Rejected from command center' } }), 'Rejected');
      if (r === undefined) return;
      S.needs = S.needs.filter(n => n.id !== id); render(); loadStats();
    },
    async 'ai-approve'(btn) {
      const id = Number(btn.dataset.id);
      if (await run(btn, () => api(`/needs-you/gemini-answers/${id}/approve`, { method: 'POST' }), 'Approved · saved to Answer Bank') === undefined) return;
      S.aiAnswers = S.aiAnswers.filter(a => a.id !== id); render();
    },
    async 'ai-reject'(btn) {
      const id = Number(btn.dataset.id);
      if (await run(btn, () => api(`/needs-you/gemini-answers/${id}/reject`, { method: 'POST' }), 'Draft rejected') === undefined) return;
      S.aiAnswers = S.aiAnswers.filter(a => a.id !== id); render();
    },
    'ai-edit'(btn) {
      const card = btn.closest('[data-ai]'), id = Number(btn.dataset.id);
      const a = S.aiAnswers.find(x => x.id === id);
      const box = card.querySelector('.ai-answer');
      box.outerHTML = `<textarea class="textarea ai-answer" style="margin-top:8px">${esc(a.answer)}</textarea>`;
      card.querySelector('.qactions').innerHTML = `<button class="btn primary sm" data-act="ai-save" data-id="${id}">${icon('check')}Save & approve</button><button class="btn sm ghost" data-act="ai-cancel">Cancel</button>`;
      card.querySelector('textarea').focus();
    },
    'ai-cancel': () => render(),
    async 'ai-save'(btn) {
      const id = Number(btn.dataset.id), answer = btn.closest('[data-ai]').querySelector('textarea').value.trim();
      if (!answer) { toast('Answer can’t be empty', true); return; }
      if (await run(btn, () => api(`/needs-you/gemini-answers/${id}/edit`, { method: 'POST', body: { answer } }), 'Edited & approved') === undefined) return;
      S.aiAnswers = S.aiAnswers.filter(a => a.id !== id); render();
    },
    // Pipeline
    'pipe-more'() { S.pipe.limit += 200; $('#pipe-body').innerHTML = pipeTable(); },
    'pipe-reset'() { Object.assign(S.pipe, { stage: 'all', q: '', source: '', min: '', limit: 100 }); render(); },
    'lane-more'(btn) { const l = btn.dataset.lane; S.pipe.laneLimit[l] = (S.pipe.laneLimit[l] || 25) + 50; $('#pipe-body').innerHTML = pipeBoard(); },
    // Answers
    'ans-add'() { S.ans.adding = true; S.ans.editing = null; render(); },
    'ans-edit'(btn) { S.ans.editing = Number(btn.dataset.id); S.ans.adding = false; render(); },
    'ans-cancel'() { S.ans.editing = null; S.ans.adding = false; render(); },
    async 'ans-del'(btn) {
      const id = Number(btn.dataset.id), a = S.answers.find(x => x.id === id);
      const ok = await confirmModal({ title: 'Delete this answer?', body: `“${esc(a.question_text)}” will no longer be auto-filled. This can’t be undone.`, ok: 'Delete', danger: true });
      if (!ok) return;
      if (await run(btn, () => api(`/answer-bank/${id}`, { method: 'DELETE' }), 'Answer deleted') === undefined) return;
      S.answers = S.answers.filter(x => x.id !== id); render();
    },
    async backup(btn) { await run(btn, () => api('/backup', { method: 'POST' }), 'Backup created'); },
    'shell-server'() { if (IN_SHELL) window.ApplyPilotShell.postMessage('change-server'); },
  };

  // ───────────────────────── Events ─────────────────────────
  document.addEventListener('click', (e) => {
    const t = e.target;
    const nav = t.closest('[data-nav]');
    if (nav) {
      if (nav.dataset.stage) { S.pipe.stage = nav.dataset.stage; S.pipe.limit = 100; }
      if (nav.dataset.tab) S.inbox.tab = nav.dataset.tab;
      closeJob(); go(nav.dataset.nav); return;
    }
    const act = t.closest('[data-act]');
    if (act && !act.disabled) { e.preventDefault(); actions[act.dataset.act] && actions[act.dataset.act](act); return; }
    const job = t.closest('[data-job]');
    if (job) { openJob(job.dataset.job); return; }
    const it = t.closest('[data-inbox-tab]');
    if (it) { S.inbox.tab = it.dataset.inboxTab; render(); return; }
    const q = t.closest('[data-q]');
    if (q) { S.inbox.sel = Number(q.dataset.q); render(); return; }
    const pick = t.closest('[data-pick]');
    if (pick) { const cur = S.needs[S.inbox.sel]; S.inbox.picks[cur.id] = pick.dataset.pick; $$('.opt').forEach(o => o.classList.toggle('on', o === pick)); return; }
    const sf = t.closest('[data-stage-f]');
    if (sf) { S.pipe.stage = sf.dataset.stageF; S.pipe.limit = 100; render(); return; }
    const pm = t.closest('[data-pipe-mode]');
    if (pm) { S.pipe.mode = pm.dataset.pipeMode; render(); return; }
    const so = t.closest('[data-sort]');
    if (so) { const k = so.dataset.sort; S.pipe.dir = S.pipe.sort === k ? -S.pipe.dir : (k === 'company' || k === 'title' ? 1 : -1); S.pipe.sort = k; $('#pipe-body').innerHTML = pipeTable(); return; }
    const cat = t.closest('[data-cat]');
    if (cat) { S.ans.cat = cat.dataset.cat; render(); return; }
    const lv = t.closest('[data-level]');
    if (lv) { S.act.level = lv.dataset.level; render(); return; }
    if (t.id === 'scrim') closeJob();
  });

  document.addEventListener('submit', async (e) => {
    const form = e.target;
    e.preventDefault();
    const btn = form.querySelector('[type=submit]');
    if (form.dataset.ansForm) {
      const fd = Object.fromEntries(new FormData(form));
      const id = form.dataset.ansForm;
      if (id === 'new') {
        const r = await run(btn, () => api('/answer-bank', { method: 'POST', body: { ...fd, source: 'manual_entry' } }), 'Answer added');
        if (r) { S.answers.unshift(r); S.ans.adding = false; render(); }
      } else {
        const r = await run(btn, () => api(`/answer-bank/${id}`, { method: 'PUT', body: fd }), 'Answer saved');
        if (r) { S.answers = S.answers.map(a => a.id === r.id ? r : a); S.ans.editing = null; render(); }
      }
      return;
    }
    if (form.dataset.profileForm) {
      const keys = PROFILE_SECTIONS[form.dataset.profileForm], body = {};
      keys.forEach(k => {
        const el = form.elements[k]; if (!el) return;
        if (el.type === 'checkbox') body[k] = el.checked;
        else if (el.dataset.kind === 'list') body[k] = el.value.split(',').map(s => s.trim()).filter(Boolean);
        else if (el.type === 'number') { if (el.value !== '') body[k] = Number(el.value); }
        else body[k] = el.value.trim() === '' && S.profile[k] == null ? null : el.value.trim();
      });
      const r = await run(btn, () => api('/profile', { method: 'PUT', body }), 'Saved');
      if (r) { S.profile = r; loadStats(); }
      return;
    }
    if (form.hasAttribute('data-gemini-form')) {
      const body = {
        gemini_auto_answer_enabled: form.elements.gemini_auto_answer_enabled.checked,
        gemini_min_confidence: Number(form.elements.gemini_min_confidence.value),
        gemini_daily_cap: Number(form.elements.gemini_daily_cap.value),
      };
      const r = await run(btn, () => api('/profile/gemini-settings', { method: 'POST', body }), 'Gemini settings saved');
      if (r) S.gemini = r;
    }
  });

  // ───────────────────────── Command palette ─────────────────────────
  let pal = null;
  function paletteItems(q) {
    q = q.trim().toLowerCase();
    const cmds = [
      ...VIEWS.map((v, i) => ({ icon: v.icon, label: `Go to ${v.label}`, hint: String(i + 1), run: () => go(v.id) })),
      { icon: 'bolt', label: 'Apply to next queued job', run: () => actions['apply-next']() },
      { icon: 'travel_explore', label: 'Discover new jobs', run: () => actions.discover() },
      { icon: 'analytics', label: 'Score discovered jobs', run: () => actions.evaluate() },
      S.stats && S.stats.is_paused ? { icon: 'play_arrow', label: 'Resume engine', run: () => actions.resume() } : { icon: 'pause', label: 'Pause engine', run: () => actions.pause() },
      { icon: 'science', label: S.stats && S.stats.go_live ? 'Switch to dry run' : 'Go live…', run: () => setMode(!(S.stats && S.stats.go_live)) },
      { icon: 'backup', label: 'Back up database now', run: () => actions.backup() },
      { icon: 'contrast', label: 'Toggle light / dark', run: toggleTheme },
      ...(IN_SHELL ? [{ icon: 'dns', label: 'Phone app: change server', run: () => actions['shell-server']() }] : []),
    ];
    const c = cmds.filter(x => !q || x.label.toLowerCase().includes(q));
    const jobs = q && S.jobs ? S.jobs.filter(j => `${j.company} ${j.title}`.toLowerCase().includes(q)).slice(0, 8)
      .map(j => ({ icon: 'work', label: `${j.company} — ${j.title}`, hint: STATUS_LABEL[j.status] || j.status, run: () => openJob(j.id) })) : [];
    return { cmds: c, jobs };
  }
  function openPalette() {
    if (pal) return;
    if (!S.jobs) api('/jobs').then(j => { S.jobs = j; if (pal) drawPalette(); }).catch(() => {});
    $('#overlay').innerHTML = `<div class="palette-wrap" id="pal-wrap"><div class="palette" role="dialog" aria-label="Command palette">
      <div class="palette-in">${icon('search')}<input id="pal-in" placeholder="Type a command or search jobs…" autocomplete="off"><span class="kbd">Esc</span></div>
      <div class="palette-list" id="pal-list"></div></div></div>`;
    pal = { sel: 0, flat: [] };
    const inp = $('#pal-in');
    inp.addEventListener('input', () => { pal.sel = 0; drawPalette(); });
    $('#pal-wrap').addEventListener('click', (e) => {
      const it = e.target.closest('[data-pi]');
      if (it) { execPalette(Number(it.dataset.pi)); return; }
      if (e.target.id === 'pal-wrap') closePalette();
    });
    drawPalette(); inp.focus();
  }
  function drawPalette() {
    const { cmds, jobs } = paletteItems($('#pal-in').value);
    pal.flat = [...jobs, ...cmds];
    pal.sel = Math.min(pal.sel, Math.max(0, pal.flat.length - 1));
    let i = 0;
    const sec = (title, items) => items.length ? `<div class="palette-sec">${title}</div>` + items.map(x => `<button class="palette-item ${i === pal.sel ? 'on' : ''}" data-pi="${i++}">${icon(x.icon)}<span class="grow">${esc(x.label)}</span>${x.hint ? `<span class="hint">${esc(x.hint)}</span>` : ''}</button>`).join('') : '';
    $('#pal-list').innerHTML = sec('Jobs', jobs) + sec('Commands', cmds) || `<div class="empty">No matches</div>`;
    const on = $('#pal-list .on'); on && on.scrollIntoView({ block: 'nearest' });
  }
  function execPalette(i) { const x = pal && pal.flat[i]; closePalette(); x && x.run(); }
  function closePalette() { pal = null; $('#overlay').innerHTML = ''; }
  $('#search-trigger').addEventListener('click', openPalette);

  function toggleTheme() {
    const next = document.documentElement.dataset.theme === 'light' ? 'dark' : 'light';
    document.documentElement.dataset.theme = next;
    $('meta[name=theme-color]').content = next === 'light' ? '#F5F4F1' : '#000000';
    try { localStorage.setItem('ap_theme', next); } catch (e) {}
  }
  $('#theme-btn').addEventListener('click', toggleTheme);

  document.addEventListener('keydown', (e) => {
    if (pal) {
      if (e.key === 'Escape') { e.preventDefault(); closePalette(); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); pal.sel = Math.min(pal.flat.length - 1, pal.sel + 1); drawPalette(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); pal.sel = Math.max(0, pal.sel - 1); drawPalette(); }
      else if (e.key === 'Enter') { e.preventDefault(); execPalette(pal.sel); }
      return;
    }
    if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'k') { e.preventDefault(); openPalette(); return; }
    if (e.key === 'Escape') { if (S.jobId) closeJob(); else if (isTyping()) document.activeElement.blur(); return; }
    if (isTyping() || e.ctrlKey || e.metaKey || e.altKey || $('#overlay').innerHTML) return;
    if (e.key === '/') { e.preventDefault(); openPalette(); return; }
    if (/^[1-6]$/.test(e.key)) { closeJob(); go(VIEWS[Number(e.key) - 1].id); return; }
    if (S.view === 'inbox' && S.inbox.tab === 'questions' && S.needs.length && (e.key === 'j' || e.key === 'k')) {
      S.inbox.sel = Math.max(0, Math.min(S.needs.length - 1, S.inbox.sel + (e.key === 'j' ? 1 : -1))); render(); return;
    }
    if (S.view === 'inbox' && S.inbox.tab === 'triage' && S.triage.length && (e.key === 'q' || e.key === 'x')) {
      const b = $(`[data-tcard] [data-action="${e.key === 'q' ? 'queue' : 'dismiss'}"]`); b && actions.swipe(b);
    }
  });

  // Android app (app/lib/shell): the hardware back button asks the page first.
  // Returns true when it closed something or went back to Today; false lets the app exit.
  window.__apBack = () => {
    if ($('#overlay').innerHTML) { if (pal) closePalette(); else $('#overlay').innerHTML = ''; return true; }
    if (S.jobId) { closeJob(); return true; }
    if (S.ans.editing || S.ans.adding) { actions['ans-cancel'](); return true; }
    if (S.view !== 'today') { go('today'); return true; }
    return false;
  };

  window.addEventListener('hashchange', () => { const v = location.hash.replace(/^#\/?/, ''); if (v && v !== S.view) go(v); });

  // ───────────────────────── Live polling ─────────────────────────
  async function poll() {
    if (document.hidden) return;
    await loadStats();
    const editing = isTyping() || $('#overlay').innerHTML || S.ans.editing || S.ans.adding;
    if (editing) return;
    if (S.view === 'today') { try { await loaders.today(); if (S.view === 'today') render(); } catch (e) {} }
    if (S.view === 'activity') { try { await loaders.activity(); if (S.view === 'activity') render(); } catch (e) {} }
  }

  // ───────────────────────── Boot ─────────────────────────
  (async () => {
    renderChrome();
    const start = location.hash.replace(/^#\/?/, '') || 'today';
    // Inbox counts power the nav badge everywhere, so fetch them alongside the first view.
    await Promise.allSettled([loadStats(), loaders.inbox()]);
    go(start);
    setInterval(poll, 15000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
  })();
})();
