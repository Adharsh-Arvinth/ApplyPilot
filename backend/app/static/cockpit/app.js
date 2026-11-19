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
  const icon = (name, cls = '') => `<span class="ms ${cls}" aria-hidden="true">${name}</span>`;
  const initials = (s) => (String(s || '?').replace(/[^A-Za-z0-9 ]/g, ' ').trim().split(/\s+/).slice(0, 2).map(w => w[0]).join('') || '?').toUpperCase();
  // Stable hue per company name -> generated "album art" tiles.
  const hue = (s) => { let h = 7; for (const ch of String(s || '')) h = (h * 31 + ch.charCodeAt(0)) >>> 0; return h % 360; };
  const art = (name, size = '') => `<span class="art ${size}" style="--h:${hue(name)}" aria-hidden="true">${esc(initials(name))}</span>`;
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
    setTimeout(() => { el.classList.add('out'); setTimeout(() => el.remove(), 320); }, err ? 5200 : 3000);
  }

  async function run(btn, fn, okMsg) {
    // Busy state: the label fades and a spinner takes its place (see .btn.busy in app.css).
    if (btn) { btn.classList.add('busy'); btn.disabled = true; btn.setAttribute('aria-busy', 'true'); btn.insertAdjacentHTML('beforeend', '<span class="spin" aria-hidden="true"></span>'); }
    try {
      const r = await fn();
      if (okMsg) toast(typeof okMsg === 'function' ? okMsg(r) : okMsg);
      return r;
    } catch (e) { toast(e.message || 'Something went wrong', true); return undefined; }
    finally {
      if (btn && btn.isConnected) {
        btn.classList.remove('busy'); btn.disabled = false; btn.removeAttribute('aria-busy');
        const s = btn.querySelector('.spin'); if (s) s.remove();
      }
    }
  }

  function confirmModal({ title, body, ok = 'Confirm', danger = false }) {
    return new Promise(resolve => {
      const ov = $('#overlay'), prev = document.activeElement;
      ov.innerHTML = `<div class="modal-wrap" data-close><div class="modal" role="alertdialog" aria-modal="true" aria-labelledby="modal-t">
        <h3 id="modal-t">${esc(title)}</h3><p>${body}</p>
        <div class="acts"><button class="btn ghost hv" data-x="0">Cancel</button><button class="btn primary hv ${danger ? 'danger' : ''}" data-x="1">${esc(ok)}</button></div>
      </div></div>`;
      const done = (v) => { ov.innerHTML = ''; document.removeEventListener('keydown', onKey, true); if (prev && prev.isConnected) prev.focus({ preventScroll: true }); resolve(v); };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.stopPropagation(); done(false); }
        else if (e.key === 'Enter') { e.preventDefault(); done(true); }
        else if (e.key === 'Tab') { e.preventDefault(); const bs = $$('.modal button', ov); const i = bs.indexOf(document.activeElement); bs[(i + (e.shiftKey ? -1 : 1) + bs.length) % bs.length].focus(); }
      };
      document.addEventListener('keydown', onKey, true);
      ov.querySelector('.modal-wrap').addEventListener('click', (e) => {
        const x = e.target.closest('[data-x]');
        if (x) return done(x.dataset.x === '1');
        if (e.target.hasAttribute('data-close')) done(false);
      });
      ov.querySelector('[data-x="1"]').focus();
    });
  }

  function ring(pct, size = 64, stroke = 7, color = 'var(--accent)') {
    const r = (size - stroke) / 2, c = 2 * Math.PI * r, off = c * (1 - Math.max(0, Math.min(1, pct))), mid = size / 2;
    return `<svg width="${size}" height="${size}" viewBox="0 0 ${size} ${size}" aria-hidden="true">
      <circle cx="${mid}" cy="${mid}" r="${r}" fill="none" stroke="var(--track)" stroke-width="${stroke}"/>
      <circle class="v" cx="${mid}" cy="${mid}" r="${r}" fill="none" stroke="${color}" stroke-width="${stroke}" stroke-linecap="round"
        stroke-dasharray="${c.toFixed(2)}" stroke-dashoffset="${off.toFixed(2)}"/></svg>`;
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
    jobId: null, job: null, returnFocus: null,
    online: true, anim: false, lastHtml: '',
  };

  const today = () => new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' });
  const VIEWS = [
    { id: 'today', label: 'Today', icon: 'space_dashboard', mobile: 'today', sub: today },
    { id: 'inbox', label: 'Needs you', icon: 'inbox', mobile: 'notifications', sub: () => 'Every decision that needs a human, in one place' },
    { id: 'pipeline', label: 'Pipeline', icon: 'view_kanban', mobile: 'work', sub: () => S.jobs ? `${fmt(S.jobs.length)} tracked roles` : 'Tracked roles' },
    { id: 'answers', label: 'Answers', icon: 'forum', mobile: 'forum', sub: () => 'Verified facts the agent reuses on forms' },
    { id: 'activity', label: 'Activity', icon: 'receipt_long', sub: () => 'Engine run log' },
    { id: 'settings', label: 'Profile & rules', icon: 'tune', mobile: 'person', sub: () => 'Who you are and how the agent behaves' },
  ];
  const MOBILE_TABS = ['today', 'inbox', 'pipeline', 'answers', 'settings'];
  const MOBILE_LABEL = { today: 'Today', inbox: 'Needs You', pipeline: 'Jobs', answers: 'Answers', settings: 'Profile' };

  const inboxCount = () => (S.stats ? S.stats.needs_you_count : S.needs.length) + S.aiAnswers.length + (S.stats ? S.stats.maybe_count : S.triage.length);

  // ───────────────────────── Rendering primitives ─────────────────────────
  // Only touch the DOM when markup really changed, so background polling never
  // interrupts a hover, press or sliding animation.
  function setHTML(el, html) {
    if (!el || el.__html === html) return false;
    el.innerHTML = html; el.__html = html; return true;
  }

  // Liquid lens for nav, tab bar and segmented controls. It remembers its last position
  // per control, glides from the old item even after a re-render, and briefly stretches
  // ("moving") while it travels — position uses `translate`, the stretch uses `scale`,
  // so the two never fight and both stay on the compositor.
  const glidePos = {};
  function glide(root, key, activeSel = '.on') {
    if (!root || !root.getClientRects().length) return;
    let ind = root.querySelector(':scope > .glide');
    const fresh = !ind;
    if (fresh) { ind = document.createElement('i'); ind.className = 'glide'; ind.setAttribute('aria-hidden', 'true'); root.prepend(ind); }
    const on = root.querySelector(activeSel);
    if (!on || !on.offsetWidth) { ind.style.opacity = '0'; return; }
    const to = { x: on.offsetLeft, y: on.offsetTop, w: on.offsetWidth, h: on.offsetHeight };
    const from = glidePos[key];
    const place = (p) => { ind.style.translate = `${p.x}px ${p.y}px`; ind.style.width = `${p.w}px`; ind.style.height = `${p.h}px`; };
    if (fresh) { ind.style.transition = 'none'; place(from || to); void ind.offsetWidth; ind.style.transition = ''; }
    if (from && (from.x !== to.x || from.y !== to.y)) {
      ind.classList.add('moving');
      clearTimeout(ind.__t); ind.__t = setTimeout(() => ind.classList.remove('moving'), 200);
    }
    place(to); ind.style.opacity = '1';
    glidePos[key] = to;
  }

  // ───────────────────────── Liquid Glass ─────────────────────────
  // Edge refraction: a displacement map that is neutral in the middle and ramps at the
  // rim, so the backdrop bends like light through the edge of a lens. Chromium only
  // (Chrome, Edge, Android WebView); elsewhere the CSS falls back to frosted blur.
  function initLiquidGlass() {
    const ok = !!window.chrome && CSS.supports('backdrop-filter', 'url(#lg-lens) blur(2px)')
      && !matchMedia('(prefers-reduced-transparency: reduce)').matches;
    if (!ok) return;
    const map = `<svg xmlns="http://www.w3.org/2000/svg" width="200" height="100" viewBox="0 0 200 100" preserveAspectRatio="none">
      <defs><linearGradient id="r" x1="0" x2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#f00"/></linearGradient>
      <linearGradient id="g" x1="0" x2="0" y1="0" y2="1"><stop offset="0" stop-color="#000"/><stop offset="1" stop-color="#0f0"/></linearGradient>
      <filter id="b" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="10"/></filter></defs>
      <rect width="200" height="100" fill="url(#r)"/><rect width="200" height="100" fill="url(#g)" style="mix-blend-mode:screen"/>
      <rect x="16" y="14" width="168" height="72" rx="36" fill="#808000" filter="url(#b)"/></svg>`;
    const href = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(map);
    document.body.insertAdjacentHTML('beforeend', `<svg width="0" height="0" style="position:absolute" aria-hidden="true" focusable="false">
      <filter id="lg-lens" x="0" y="0" width="100%" height="100%" color-interpolation-filters="sRGB">
        <feImage href="${href}" x="0" y="0" width="100%" height="100%" preserveAspectRatio="none" result="map"/>
        <feDisplacementMap in="SourceGraphic" in2="map" scale="-64" xChannelSelector="R" yChannelSelector="G"/>
      </filter></svg>`);
    document.documentElement.classList.add('lg-refract');
  }

  // Specular highlight that follows the pointer across glass controls (one rAF per frame,
  // touches only the hovered element's custom properties).
  const SPEC = '.btn, .search-trigger, .lcd, .filter-chip, .nav-item, .seg button, .mode-switch button';
  let specEvt = null, specRaf = 0;
  document.addEventListener('pointermove', (e) => {
    if (e.pointerType !== 'mouse') return;
    specEvt = e;
    if (specRaf) return;
    specRaf = requestAnimationFrame(() => {
      specRaf = 0;
      const el = specEvt.target.closest && specEvt.target.closest(SPEC);
      if (!el) return;
      const r = el.getBoundingClientRect();
      el.style.setProperty('--mx', `${specEvt.clientX - r.left}px`);
      el.style.setProperty('--my', `${specEvt.clientY - r.top}px`);
    });
  }, { passive: true });

  // After every render: sliding pills + accessible names for icon-only controls.
  function enhance(root) {
    $$('.seg', root).forEach((el, i) => glide(el, `${S.view}:${el.dataset.glide || i}`));
    $$('button[title]:not([aria-label]), a[title]:not([aria-label])', root).forEach(b => {
      const text = Array.from(b.childNodes).filter(n => !(n.classList && n.classList.contains('ms'))).map(n => n.textContent).join('').trim();
      if (!text) b.setAttribute('aria-label', b.title);
    });
  }

  // ───────────────────────── Chrome (nav, engine display, tabbar) ─────────────────────────
  function renderNav() {
    const n = inboxCount();
    setHTML($('#nav'), `<div class="nav-label">Workspace</div>` + VIEWS.map((v, i) => {
      const on = S.view === v.id;
      const end = v.id === 'inbox' ? `<span class="nav-count ${n ? '' : 'zero'}">${n || 0}</span>` : `<span class="kbd" aria-hidden="true">${i + 1}</span>`;
      return `<button class="nav-item hv ${on ? 'active' : ''}" data-nav="${v.id}" title="${esc(v.label)}" ${on ? 'aria-current="page"' : ''}>${icon(v.icon)}<span class="lbl">${esc(v.label)}</span>${end}</button>`;
    }).join(''));
    glide($('#nav'), 'nav', '.nav-item.active');
    setHTML($('#tabbar'), MOBILE_TABS.map(id => {
      const v = VIEWS.find(x => x.id === id), on = S.view === id, b = id === 'inbox' ? n : 0;
      return `<button class="${on ? 'active' : ''}" data-nav="${id}" ${on ? 'aria-current="page"' : ''}>${icon(v.mobile)}<span>${MOBILE_LABEL[id]}</span>${b ? `<span class="badge">${b > 99 ? '99+' : b}</span>` : ''}</button>`;
    }).join(''));
    glide($('#tabbar'), 'tab', 'button.active');
  }

  function renderEngine() {
    const st = S.stats;
    const [label, color] = engineLabel(st);
    const live = !!(st && st.go_live), paused = !!(st && st.is_paused);
    const applied = st ? st.daily_applied : 0, cap = st ? st.daily_cap : 0;
    const pct = cap ? Math.min(1, applied / cap) : 0;
    setHTML($('#engine'), `<div class="engine-title">Submission mode</div>
      <div class="mode-switch" role="radiogroup" aria-label="Submission mode">
        <button role="radio" aria-checked="${!live}" class="${live ? '' : 'on'}" data-act="mode-dry">Dry run</button>
        <button role="radio" aria-checked="${live}" class="${live ? 'on live' : ''}" data-act="mode-live">Live</button>
      </div>`);
    glide($('#engine .mode-switch'), 'mode');
    const verb = paused ? 'Resume engine' : 'Pause engine';
    setHTML($('#lcd'), `
      <button class="lcd-btn hv" data-act="${paused ? 'resume' : 'pause'}" ${st ? '' : 'disabled'} aria-label="${verb}" title="${verb}">${icon(paused ? 'play_arrow' : 'pause')}</button>
      <div class="lcd-text"><div class="lcd-t"><span class="dot ${color} ${color === 'teal' ? 'pulse' : ''}"></span>${esc(label)}</div>
        <div class="lcd-s tnum">${fmt(applied)} of ${fmt(cap)} applied today</div></div>
      <span class="chip ${live ? 'accent' : ''}">${live ? 'Live' : 'Dry run'}</span>
      <div class="lcd-bar"><i style="transform:scaleX(${pct.toFixed(3)})"></i></div>`);
    setHTML($('#top-actions'), `
      <button class="btn hv" data-act="discover" title="Scan ATS boards for new roles">${icon('travel_explore')}Discover</button>
      <button class="btn primary hv" data-act="apply-next" title="Process the top queued job" ${paused ? 'disabled' : ''}>${icon('bolt')}Apply next</button>`);
  }

  function renderChrome() {
    renderNav(); renderEngine();
    document.title = `${VIEWS.find(x => x.id === S.view).label} · ApplyPilot`;
  }

  const pageHead = (right = '') => {
    const v = VIEWS.find(x => x.id === S.view);
    return `<header class="view-head"><div class="min0"><h1><span class="t-desk">${esc(v.label)}</span><span class="t-mob">${esc(MOBILE_LABEL[v.id] || v.label)}</span></h1>
      <div class="sub">${esc(v.sub())}</div></div>${right}</header>`;
  };

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
    if (changed || !silent) { $('#content').innerHTML = skeleton(view); $('#content').scrollTop = 0; S.lastHtml = ''; }
    try { await loaders[view](); }
    catch (e) { if (my === viewToken) $('#content').innerHTML = errorView(e); return; }
    if (my !== viewToken) return;
    render();
  }
  function render({ poll = false } = {}) {
    const html = renderers[S.view]();
    if (poll && html === S.lastHtml) { renderChrome(); return; }
    S.lastHtml = html;
    const anim = S.anim; S.anim = false;
    const content = $('#content'), y = content.scrollTop;
    content.innerHTML = `<div class="view ${anim ? 'enter' : ''}">${html}</div>`;
    if (!anim) content.scrollTop = y;
    renderChrome();
    enhance(content);
    afterRender[S.view] && afterRender[S.view]();
  }
  // Loading skeletons shaped like the view that is coming (dashboard vs. list views).
  const skeleton = (view) => `<div class="view" aria-busy="true"><div class="view-head"><div class="skel sk-title"></div></div>${view === 'today'
    ? `<div class="kpis">${'<div class="card kpi"><div class="skel sk-line"></div><div class="skel sk-num"></div></div>'.repeat(4)}</div>
       <div class="grid-today"><div class="card card-b span-8"><div class="skel sk-block"></div></div><div class="card card-b span-4"><div class="skel sk-block"></div></div></div>`
    : `<div class="card list">${'<div class="skel sk-row"></div>'.repeat(6)}</div>`}</div>`;
  const errorView = (e) => `<div class="view"><div class="card"><div class="empty error" role="alert">${icon('cloud_off')}<b>Couldn't reach the ApplyPilot backend</b><span>${esc(e.message)}</span><button class="btn hv" data-act="reload">${icon('refresh')}Try again</button></div></div></div>`;
  const emptyCard = (ic, title, text = '', extra = '') => `<div class="card"><div class="empty">${icon(ic)}<b>${title}</b>${text ? `<span>${text}</span>` : ''}${extra}</div></div>`;

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
        <div class="actions"><button class="btn hv" data-nav="activity">View log</button><button class="btn primary hv" data-act="resume">Run pre-flight & resume</button></div></div>`;
    } else if (st.is_paused) {
      alert = `<div class="alert">${icon('pause_circle')}<div><div class="alert-t">Engine paused${st.paused_at ? ` since ${esc(st.paused_at)}` : ''}</div><div class="alert-d">${esc(st.recovery_instruction || st.pause_reason || 'Automation is paused.')}</div></div>
        <div class="actions"><button class="btn primary hv" data-act="resume" ${st.can_resume === false ? 'disabled' : ''}>${icon('play_arrow')}Resume</button></div></div>`;
    }
    const nyCount = (st.needs_you_count || 0) + S.aiAnswers.length;
    const kpi = (attrs, dot, label, value, sub, warn = false) => `<button class="card kpi lift" ${attrs}>
      <span class="kpi-l"><span class="dot ${dot}"></span>${label}</span><span class="kpi-v ${warn ? 'warn' : ''}">${value}</span><span class="kpi-s">${sub}</span>${icon('arrow_forward', 'go')}</button>`;
    const kpis = `<div class="kpis">
      <div class="card kpi quota"><div class="ring">${ring(cap ? applied / cap : 0, 66, 7)}<div class="c">${fmt(applied)}</div></div>
        <div><div class="kpi-l">Applied today</div><div class="kpi-s tnum">of ${fmt(cap)} cap · target ${fmt(st.daily_target || 0)}</div>
        <div class="kpi-s tnum">${fmt(st.real_applied_today || 0)} live · ${fmt(st.dry_run_today || 0)} dry run</div></div></div>
      ${kpi('data-nav="pipeline" data-stage="queued"', 'indigo', 'Queued', fmt(st.queue_count), 'ready to apply')}
      ${kpi('data-nav="inbox"', 'amber', 'Needs you', fmt(nyCount), `${fmt(st.needs_you_count || 0)} questions · ${fmt(S.aiAnswers.length)} AI drafts`, nyCount > 0)}
      ${kpi('data-nav="inbox" data-tab="triage"', 'violet', 'To triage', fmt(st.maybe_count), 'borderline fits')}
      ${kpi('data-nav="pipeline" data-stage="submitted"', 'teal', 'Submitted', fmt((st.total_submitted_real || 0) + (st.total_dry_run || 0)), `${fmt(st.total_submitted_real || 0)} live · ${fmt(st.total_dry_run || 0)} dry run`)}
      ${kpi('data-nav="pipeline" data-stage="interview"', 'teal', 'Interviews', fmt(st.interview_count), an.offers_count ? `${fmt(an.offers_count)} offers` : 'no offers yet')}
    </div>`;

    const top = (an.top_matches || []).slice(0, 10);
    const shelf = top.length ? `<section class="block"><h2 class="section-t">Top matches <button class="btn sm ghost hv ml-auto" data-nav="pipeline">See all ${icon('chevron_right')}</button></h2>
      <div class="shelf">${top.map(m => `<button class="tile" data-job="${m.id}" aria-label="${esc(m.title)} at ${esc(m.company)}">
        <span class="art" style="--h:${hue(m.company)}">${esc(initials(m.company))}${m.match_percent ? `<span class="badge">${m.match_percent}%</span>` : ''}<span class="open">${icon('arrow_outward')}</span></span>
        <span class="tile-t">${esc(m.title)}</span><span class="tile-s"><span class="ellipsis">${esc(m.company)}</span>${scoreTag(m.score)}</span></button>`).join('')}</div></section>` : '';

    const week = an.weekly_trend || [];
    const max = Math.max(1, ...week.map(w => w.count));
    const bars = week.length ? `<div class="bars">${week.map((w, i) => `<div class="col ${i === week.length - 1 ? 'today' : ''}" title="${esc(w.date)}: ${w.count}">
        <span class="v">${w.count}</span><div class="b" style="height:${Math.max(2, w.count / max * 100)}%"></div><span class="d">${esc(w.day)}</span></div>`).join('')}</div>`
      : `<div class="empty">No submissions this week yet</div>`;

    const funnel = (an.funnel || []).filter(f => f.stage);
    const fMax = Math.max(1, ...funnel.map(f => f.count));
    const fColor = { blue: 'var(--indigo)', amber: 'var(--amber)', violet: 'var(--violet)', emerald: 'var(--teal)', green: 'var(--teal)', gold: 'var(--amber)', rose: 'var(--coral)', red: 'var(--coral)' };
    const funnelHtml = funnel.map(f => `<div class="funnel-row"><span class="lab">${esc(f.stage)}</span>
      <div class="bar"><i style="width:${Math.max(f.count ? 1.5 : 0, f.count / fMax * 100)}%;background:${fColor[f.color] || 'var(--slate)'}"></i></div>
      <span class="val">${fmt(f.count)}</span></div>`).join('');

    const feed = (S.logs || []).slice(0, 9).map(l => `<div class="feed-item"><span class="dot ${logColor(l)}"></span>
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
    const tierHtml = `<div class="tier-bar">${tiers.map(t => t[1] ? `<i style="flex:${t[1]};background:${t[2]}" title="${t[0]}: ${t[1]}"></i>` : '').join('')}</div>
      <div class="tier-grid">${tiers.map(t => `<div><span class="dot" style="background:${t[2]}"></span><span class="muted">Score ${t[0]}</span><span class="tnum ml-auto">${fmt(t[1] || 0)} <span class="faint">${Math.round((t[1] || 0) / tTotal * 100)}%</span></span></div>`).join('')}</div>`;

    const card = (span, title, aside, body) => `<div class="card ${span}"><div class="card-h"><span class="card-t">${title}</span><span class="aside">${aside}</span></div>${body}</div>`;
    return `${pageHead()}${alert}${kpis}${shelf}
    <div class="grid-today">
      ${card('span-8', 'This week', `<span class="tnum">${fmt(goal.weekly_applied || 0)} of ${fmt(goal.weekly_target || 0)} goal</span>`, `<div class="card-b">${bars}</div>`)}
      ${card('span-4', 'Funnel', `<span class="tnum">${fmt(an.total_tracked || 0)} tracked</span>`, `<div class="card-b funnel">${funnelHtml || '<div class="empty">No data</div>'}</div>`)}
      ${card('span-7', 'Live activity', `<button class="btn sm ghost hv" data-nav="activity">Full log ${icon('chevron_right')}</button>`, `<div class="feed">${feed}</div>`)}
      ${card('span-5', 'Pre-flight', au.can_resume === false ? '<span class="chip coral">Blocked</span>' : '<span class="chip teal">Clear</span>',
        `<div class="card-b"><div class="checklist">${checkHtml || '<span class="faint">No checks reported</span>'}</div>${na.failed_tasks ? `<div class="alert-d mt-3">${fmt(na.failed_tasks)} failed tasks in the log</div>` : ''}</div>`)}
      ${card('span-6', 'Fit distribution', `<span class="tnum">${fmt(tTotal)} scored</span>`, `<div class="card-b">${tierHtml}</div>`)}
      ${card('span-6', 'Sources', `${src.length} boards`, `<div class="card-b">${srcHtml || '<div class="empty">No sources yet</div>'}</div>`)}
    </div>`;
  };

  // ───────────────────────── View: Needs you (inbox) ─────────────────────────
  renderers.inbox = () => {
    const I = S.inbox;
    const tabs = [['questions', 'Questions', S.needs.length], ['ai', 'AI drafts', S.aiAnswers.length], ['triage', 'Triage', S.triage.length]];
    const seg = `<div class="seg" role="tablist" data-glide="inbox">${tabs.map(([id, l, n]) => `<button role="tab" aria-selected="${I.tab === id}" class="${I.tab === id ? 'on' : ''}" data-inbox-tab="${id}">${l} <span class="n">${n}</span></button>`).join('')}</div>`;
    const hint = I.tab === 'triage' ? 'Q queue · X dismiss the first card' : I.tab === 'questions' ? 'J / K to move between questions' : '';
    const body = I.tab === 'questions' ? inboxQuestions() : I.tab === 'ai' ? inboxAI() : inboxTriage();
    return `${pageHead()}<div class="toolbar">${seg}<div class="spacer"></div><span class="hint">${hint}</span></div>${body}`;
  };

  function inboxQuestions() {
    const I = S.inbox;
    if (!S.needs.length) return emptyCard('task_alt', 'Nothing is waiting on you', 'When an application form asks something the Answer Bank can’t answer, it lands here.',
      S.aiAnswers.length ? `<button class="btn hv" data-inbox-tab="ai">Review ${S.aiAnswers.length} AI drafts</button>` : '');
    I.sel = Math.min(I.sel, S.needs.length - 1);
    const q = S.needs[I.sel];
    const list = S.needs.map((n, i) => `<button class="inbox-item hv ${i === I.sel ? 'sel' : ''}" data-q="${i}" ${i === I.sel ? 'aria-current="true"' : ''}>
      ${art(n.company, 'sm')}<div class="min0"><div class="q">${esc(n.question_text)}</div><div class="meta">${esc(n.company)} · ${esc(n.role)} · ${rel(n.created_at)}</div></div></button>`).join('');
    const pick = I.picks[q.id] ?? q.suggested_answer ?? '';
    const opts = (q.options || []).filter(Boolean);
    const input = opts.length
      ? `<div class="opts" role="radiogroup">${opts.map(o => `<button role="radio" aria-checked="${pick === o}" class="opt ${pick === o ? 'on' : ''}" data-pick="${esc(o)}"><span>${esc(o)}</span>${icon('check_circle', 'fill')}</button>`).join('')}</div>`
      : `<textarea class="textarea" id="q-answer" aria-label="Answer" placeholder="Type the answer exactly as it should appear on the form">${esc(pick)}</textarea>`;
    return `<div class="inbox">
      <div class="card inbox-list">${list}</div>
      <div class="card qcard">
        <div class="who">${art(q.company, 'lg')}<div class="min0"><div class="strong">${esc(q.company)}</div><div class="muted small">${esc(q.role)}</div></div>
          <span class="chip ml-auto">Question ${I.sel + 1} of ${S.needs.length}</span></div>
        <h2>${esc(q.question_text)}</h2>
        ${q.suggested_answer ? `<div class="suggest">${icon('auto_awesome')} Suggested: ${esc(q.suggested_answer)}</div>` : ''}
        ${input}
        <label class="remember"><div class="grow">Remember for future applications<small>Saves to the Answer Bank so similar fields are filled automatically</small></div>
          <span class="toggle"><input type="checkbox" id="q-remember" ${I.remember ? 'checked' : ''}><i></i></span></label>
        <div class="qactions">
          <button class="btn primary lg hv" data-act="q-resolve" data-id="${q.id}">Save & continue ${icon('arrow_forward')}</button>
          <button class="btn hv" data-act="q-dismiss" data-id="${q.id}" title="Skip this question and the job">Skip job</button>
          <button class="btn ghost danger hv" data-act="q-reject" data-id="${q.id}" data-company="${esc(q.company)}">Reject & block company</button>
          <button class="btn ghost hv ml-auto" data-job="${q.job_id}">View job ${icon('open_in_new')}</button>
        </div>
      </div></div>`;
  }

  function inboxAI() {
    if (!S.aiAnswers.length) return emptyCard('verified', 'No AI drafts to review', 'Answers Gemini writes on the fly appear here until you approve them.');
    return `<div class="stack">${S.aiAnswers.map(a => {
      const pct = Math.round((a.confidence || 0) * 100);
      return `<div class="card ai-card" data-ai="${a.id}"><div class="card-b">
      <div class="ai-head"><span class="chip violet">${icon('auto_awesome')}AI draft</span><span class="muted small">${esc(a.company)}${a.role ? ' · ' + esc(a.role) : ''}</span>
        <span class="conf">Confidence <span class="bar"><i style="width:${pct}%;background:${a.confidence >= .85 ? 'var(--teal)' : 'var(--amber)'}"></i></span><span class="tnum">${pct}%</span></span></div>
      <div class="q">${esc(a.question)}</div>
      <div class="ai-answer">${esc(a.answer)}</div>
      ${(a.facts_used || []).length ? `<div class="facts">${a.facts_used.slice(0, 6).map(f => `<span class="chip" title="${esc(f)}">${esc(String(f).slice(0, 48))}${String(f).length > 48 ? '…' : ''}</span>`).join('')}</div>` : ''}
      <div class="qactions mt-3">
        <button class="btn primary sm hv" data-act="ai-approve" data-id="${a.id}">${icon('check')}Approve</button>
        <button class="btn sm hv" data-act="ai-edit" data-id="${a.id}">${icon('edit')}Edit</button>
        <button class="btn sm ghost danger hv" data-act="ai-reject" data-id="${a.id}">Reject</button>
        <span class="faint small ml-auto">${rel(a.created_at)}</span>
      </div></div></div>`;
    }).join('')}</div>`;
  }

  function inboxTriage() {
    if (!S.triage.length) return emptyCard('done_all', 'Triage is clear', 'Borderline matches (between your maybe and minimum fit scores) show up here for a quick yes / no.');
    return `<div class="triage">${S.triage.map(j => `<div class="card tcard lift" data-tcard="${j.id}">
      <div class="top">${art(j.company)}<div class="grow"><div class="strong">${esc(j.company)}</div><div class="muted small ellipsis">${esc(j.title)}</div></div>${scoreTag(j.score)}</div>
      <div class="tags"><span class="chip">${esc(j.location)}</span><span class="chip cap">${esc(j.source)}</span>${j.salary_raw ? `<span class="chip">${esc(j.salary_raw)}</span>` : ''}${j.is_assist_only ? '<span class="chip violet">Assist only</span>' : ''}</div>
      <div class="reason">${esc(j.score_reason || j.eligibility_reason || 'No scoring notes')}</div>
      <div class="acts"><button class="btn hv" data-act="swipe" data-action="dismiss" data-id="${j.id}">${icon('close')}Dismiss</button>
        <button class="btn primary hv" data-act="swipe" data-action="queue" data-id="${j.id}">${icon('playlist_add')}Queue</button>
        <button class="btn icon hv" data-job="${j.id}" title="Details">${icon('open_in_full')}</button></div></div>`).join('')}</div>`;
  }

  // ───────────────────────── View: Pipeline ─────────────────────────
  function filteredJobs() {
    const P = S.pipe, q = P.q.trim().toLowerCase();
    const list = (S.jobs || []).filter(j => {
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
    const chips = `<div class="chips-scroll" role="group" aria-label="Stage"><button class="filter-chip ${P.stage === 'all' ? 'on' : ''}" data-stage-f="all" aria-pressed="${P.stage === 'all'}">All <span class="n">${fmt(jobs.length)}</span></button>${STAGES.map(s => `<button class="filter-chip ${P.stage === s.id ? 'on' : ''}" data-stage-f="${s.id}" aria-pressed="${P.stage === s.id}"><span class="dot ${s.color}"></span>${s.label} <span class="n">${fmt(counts[s.id] || 0)}</span></button>`).join('')}</div>`;
    const toolbar = `<div class="toolbar">
      <div class="search">${icon('search')}<input class="input" id="pipe-q" aria-label="Filter jobs" placeholder="Filter company, role, location" value="${esc(P.q)}"></div>
      <select class="select w-sm" id="pipe-src" aria-label="Source"><option value="">All sources</option>${sources.map(s => `<option ${P.source === s ? 'selected' : ''} value="${esc(s)}">${esc(s)}</option>`).join('')}</select>
      <select class="select w-sm" id="pipe-min" aria-label="Minimum score"><option value="">Any score</option>${[4.5, 4, 3.5, 3].map(v => `<option ${String(P.min) === String(v) ? 'selected' : ''} value="${v}">Score ≥ ${v}</option>`).join('')}</select>
      <div class="spacer"></div>
      <button class="btn hv" data-act="evaluate" title="Score newly discovered jobs">${icon('analytics')}Score new</button>
      <div class="seg" data-glide="mode"><button class="${P.mode === 'table' ? 'on' : ''}" data-pipe-mode="table">${icon('table_rows')}Table</button><button class="${P.mode === 'board' ? 'on' : ''}" data-pipe-mode="board">${icon('view_kanban')}Board</button></div>
    </div>${chips}`;
    return `${pageHead()}${toolbar}<div id="pipe-body">${P.mode === 'table' ? pipeTable() : pipeBoard()}</div>`;
  };

  function pipeTable() {
    const P = S.pipe, list = filteredJobs();
    if (!list.length) return emptyCard('search_off', 'No roles match these filters', '', `<button class="btn hv" data-act="pipe-reset">Reset filters</button>`);
    const th = (key, label, cls = '') => `<th class="sortable ${cls}" data-sort="${key}" aria-sort="${P.sort === key ? (P.dir > 0 ? 'ascending' : 'descending') : 'none'}">${label}${P.sort === key ? icon(P.dir > 0 ? 'arrow_upward' : 'arrow_downward') : ''}</th>`;
    const rows = list.slice(0, P.limit).map(j => `<tr data-job="${j.id}" tabindex="0" class="${S.jobId === j.id ? 'sel' : ''}">
      <td><div class="co">${art(j.company, 'sm')}<div class="min0"><div class="strong ellipsis">${esc(j.title)}</div><div class="muted small">${esc(j.company)}</div></div></div></td>
      <td>${statusChip(j.status)}</td>
      <td class="r">${scoreTag(j.score)}</td>
      <td class="hide-m muted cap">${esc(j.source)}</td>
      <td class="hide-m muted loc" title="${esc(j.location)}">${esc(j.location)}</td>
      <td class="hide-m muted">${esc(j.salary_raw || (j.stipend_raw ? j.stipend_raw + ' stipend' : '—'))}</td>
      <td class="hide-m faint tnum">${rel(j.updated_at)}</td></tr>`).join('');
    return `<div class="card"><div class="table-wrap"><table class="tbl"><thead><tr>${th('title', 'Role')}<th>Stage</th>${th('score', 'Score', 'r')}<th class="hide-m">Source</th><th class="hide-m">Location</th><th class="hide-m">Pay</th>${th('updated', 'Updated', 'hide-m')}</tr></thead><tbody>${rows}</tbody></table></div>
      <div class="table-foot"><span class="tnum">Showing ${fmt(Math.min(P.limit, list.length))} of ${fmt(list.length)}</span>${list.length > P.limit ? `<button class="btn sm hv" data-act="pipe-more">Show more</button>` : ''}</div></div>`;
  }

  function pipeBoard() {
    const P = S.pipe, list = filteredJobs();
    const lanes = STAGES.filter(s => P.stage === 'all' || s.id === P.stage);
    return `<div class="board">${lanes.map(s => {
      const items = list.filter(j => stageOf(j.status).id === s.id);
      const lim = P.laneLimit[s.id] || 25;
      return `<section class="lane" aria-label="${s.label}"><div class="lane-h"><span class="dot ${s.color}"></span>${s.label}<span class="n">${fmt(items.length)}</span></div>
        <div class="lane-b">${items.slice(0, lim).map(j => `<button class="jcard hv ${S.jobId === j.id ? 'sel' : ''}" data-job="${j.id}">
          ${art(j.company, 'sm')}<div class="body"><div class="t1"><span>${esc(j.company)}</span>${scoreTag(j.score)}</div><div class="t2">${esc(j.title)}</div>
          <div class="t3">${s.statuses.length > 1 || s.id === 'closed' ? statusChip(j.status) : ''}<span class="chip cap">${esc(j.source)}</span>${j.is_assist_only ? '<span class="chip violet">Assist</span>' : ''}</div></div></button>`).join('') || '<div class="empty tight">Empty</div>'}
        ${items.length > lim ? `<button class="btn sm ghost hv lane-more" data-act="lane-more" data-lane="${s.id}">+ ${fmt(items.length - lim)} more</button>` : ''}</div></section>`;
    }).join('')}</div>`;
  }

  afterRender.pipeline = () => {
    const rerender = () => { $('#pipe-body').innerHTML = S.pipe.mode === 'table' ? pipeTable() : pipeBoard(); enhance($('#pipe-body')); };
    const q = $('#pipe-q');
    q && q.addEventListener('input', debounce(e => { S.pipe.q = e.target.value; S.pipe.limit = 100; rerender(); }, 120));
    $('#pipe-src') && $('#pipe-src').addEventListener('change', e => { S.pipe.source = e.target.value; rerender(); });
    $('#pipe-min') && $('#pipe-min').addEventListener('change', e => { S.pipe.min = e.target.value; rerender(); });
  };

  // ───────────────────────── Inspector (job sheet) ─────────────────────────
  async function openJob(id) {
    id = Number(id);
    if (!S.jobId) S.returnFocus = document.activeElement;
    S.jobId = id;
    const insp = $('#inspector');
    insp.innerHTML = `<div class="insp-h"><div class="grow"></div><button class="btn icon hv" data-act="close-insp" title="Close">${icon('close')}</button></div>
      <div class="insp-b"><div class="insp-hero"><div class="skel sk-art"></div><div class="skel sk-title"></div></div><div class="skel sk-block"></div></div>`;
    insp.classList.add('on'); $('#scrim').classList.add('on');
    insp.setAttribute('aria-modal', 'true'); insp.setAttribute('role', 'dialog');
    $$('[data-job]').forEach(el => el.classList.toggle('sel', Number(el.dataset.job) === id));
    try {
      const j = await api(`/jobs/${id}`);
      if (S.jobId !== id) return;
      S.job = j; renderInspector();
      const close = $('#inspector [data-act=close-insp]'); close && close.focus({ preventScroll: true });
    } catch (e) {
      insp.querySelector('.insp-b').innerHTML = `<div class="empty">${icon('error')}<b>Couldn't load this job</b><span>${esc(e.message)}</span></div>`;
    }
  }
  function closeJob() {
    if (!S.jobId) return;
    S.jobId = null; S.job = null;
    $('#inspector').classList.remove('on'); $('#scrim').classList.remove('on');
    $$('[data-job].sel').forEach(el => el.classList.remove('sel'));
    const back = S.returnFocus; S.returnFocus = null;
    if (back && back.isConnected) back.focus({ preventScroll: true });
  }
  function renderInspector() {
    const j = S.job; if (!j) return;
    const st = stageOf(j.status).id;
    const fits = [['Skills', j.skills_score, 'skills'], ['Experience', j.experience_score, 'experience'], ['Education', j.education_score, 'education'], ['Location', j.location_score, 'location'], ['Compensation', j.compensation_score, 'compensation'], ['Role relevance', j.role_relevance_score, 'role_relevance']];
    const fb = j.fit_breakdown || {};
    const fitColor = (v) => v >= 80 ? 'var(--teal)' : v >= 60 ? 'var(--indigo)' : v >= 40 ? 'var(--amber)' : 'var(--coral)';
    const fitHtml = fits.some(f => f[1] > 0)
      ? fits.map(([l, v, k]) => `<div class="fit-row" title="${esc(fb[k] || '')}"><span>${l}</span><div class="bar"><i style="width:${Math.min(100, v)}%;background:${fitColor(v)}"></i></div><span>${Math.round(v)}</span></div>`).join('')
      : '<div class="faint small">Not scored yet. Run “Score new” from the pipeline.</div>';
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
      primary = `<a class="btn primary hv" href="${esc(j.url)}" target="_blank" rel="noopener">${icon('open_in_new')}Open & apply myself</a>`;
      secondary = `<button class="btn hv" data-act="mark-applied" data-id="${j.id}">${icon('done')}Mark applied</button>`;
    } else if (st === 'triage' || st === 'new') {
      primary = `<button class="btn primary hv" data-act="swipe" data-action="queue" data-id="${j.id}">${icon('playlist_add')}Queue</button>`;
      secondary = `<button class="btn hv" data-act="swipe" data-action="dismiss" data-id="${j.id}">Dismiss</button>`;
    } else if (st === 'queued') {
      primary = `<button class="btn primary hv" data-act="apply" data-id="${j.id}">${icon('bolt')}Apply now</button>`;
      secondary = `<button class="btn hv" data-act="swipe" data-action="dismiss" data-id="${j.id}">Remove</button>`;
    } else {
      primary = `<a class="btn primary hv" href="${esc(j.url)}" target="_blank" rel="noopener">${icon('open_in_new')}Open posting</a>`;
    }
    const statusOpts = ['discovered', 'maybe', 'queued', 'needs_review', 'applied', 'interview', 'offer', 'rejected', 'dismissed', 'skipped'];
    if (!statusOpts.includes(j.status)) statusOpts.unshift(j.status);
    const section = (title, body) => `<div class="card"><div class="card-b"><div class="eyebrow mb-2">${title}</div>${body}</div></div>`;

    $('#inspector').innerHTML = `
      <div class="insp-h"><div class="grow"></div>
        <button class="btn icon hv" data-act="save-job" data-id="${j.id}" title="${j.is_saved ? 'Unsave' : 'Save'}">${icon('bookmark', j.is_saved ? 'fill' : '')}</button>
        <a class="btn icon hv" href="${esc(j.url)}" target="_blank" rel="noopener" title="Open posting">${icon('open_in_new')}</a>
        <button class="btn icon hv" data-act="close-insp" title="Close">${icon('close')}</button></div>
      <div class="insp-b">
        <div class="insp-hero" style="--h:${hue(j.company)}">
          <div class="row-between">${art(j.company, 'xl')}${j.score > 0 ? `<div class="score-ring">${ring(j.score / 5, 56, 5, scoreColor(j.score))}<div>${Number(j.score).toFixed(1)}</div></div>` : ''}</div>
          <div><div class="mb-2">${statusChip(j.status)}</div><h2 id="insp-title">${esc(j.title)}</h2><div class="co">${esc(j.company)}</div></div>
        </div>
        <div class="meta-grid">
          <div><small>Location</small><span>${esc(j.location)}</span></div><div><small>Work mode</small><span class="cap">${esc(j.work_mode)}</span></div>
          <div><small>Pay</small><span>${esc(j.salary_raw || j.stipend_raw || 'Not listed')}</span></div><div><small>Experience</small><span>${esc(j.experience_required)}</span></div>
          <div><small>Source</small><span class="cap">${esc(j.source)}${j.is_assist_only ? ' · assist only' : ''}</span></div><div><small>Readiness</small><span class="tnum">${Math.round(j.quality_readiness_score)}%</span></div>
        </div>
        ${j.score_reason || j.eligibility_reason ? section('Why this fits', `<div class="small">${esc(j.score_reason || j.eligibility_reason)}</div>`) : ''}
        ${section('Fit breakdown', fitHtml)}
        ${(j.matching_skills || []).length || (j.missing_skills || []).length ? section('Skills', `<div class="skills">${skills(j.matching_skills, 'teal')}${skills(j.missing_skills, 'coral')}</div>`) : ''}
        ${section('Timeline', `<div class="timeline">${timeline}</div>`)}
        ${section('Manage', `<div class="stack">
          <div class="field"><label for="insp-status">Stage</label><select class="select" id="insp-status">${statusOpts.map(s => `<option value="${s}" ${s === j.status ? 'selected' : ''}>${esc(STATUS_LABEL[s] || s)}</option>`).join('')}</select></div>
          <div class="field"><label for="insp-notes">Notes</label><textarea class="textarea short" id="insp-notes" placeholder="Recruiter name, referral, follow-up…">${esc(j.notes)}</textarea></div>
          <div class="qactions"><button class="btn sm hv" data-act="save-status" data-id="${j.id}">${icon('save')}Save</button>
            <button class="btn sm hv" data-act="tailor" data-id="${j.id}">${icon('description')}Tailor resume</button>
            ${st !== 'closed' ? `<button class="btn sm ghost danger hv" data-act="swipe" data-action="exclude" data-id="${j.id}">Exclude company</button>` : ''}</div></div>`)}
      </div>
      <div class="insp-f">${secondary}${primary}</div>`;
    $('#inspector').setAttribute('aria-labelledby', 'insp-title');
    enhance($('#inspector'));
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
    const addForm = A.adding ? `<div class="card block"><div class="card-b">${answerForm({ question_text: '', answer: '', category: A.cat !== 'all' ? A.cat : 'custom', mode: 'always_use' }, 'new')}</div></div>` : '';
    const body = order.length ? order.map(c => `<div class="ans-group"><span class="eyebrow">${esc(catName(c))} · ${groups[c].length}</span><div class="card list">${groups[c].map(answerRow).join('')}</div></div>`).join('')
      : emptyCard('search_off', 'No answers match');
    const catBtn = (id, label, n) => `<button class="hv ${A.cat === id ? 'on' : ''}" data-cat="${esc(id)}" aria-pressed="${A.cat === id}">${esc(label)} <span class="n">${n}</span></button>`;
    return `${pageHead()}<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="ans-q" aria-label="Search answers" placeholder="Search questions or answers" value="${esc(A.q)}"></div>
      <div class="spacer"></div><span class="hint tnum">${fmt(all.length)} saved · ${fmt(all.reduce((s, a) => s + (a.usage_count || 0), 0))} auto-fills</span>
      <button class="btn primary hv" data-act="ans-add">${icon('add')}New answer</button></div>
      <div class="ans-layout"><nav class="cat-list" aria-label="Categories">${catBtn('all', 'All', all.length)}${cats.map(c => catBtn(c, catName(c), counts[c])).join('')}</nav>
      <div id="ans-body">${addForm}${body}</div></div>`;
  };
  function answerRow(a) {
    if (S.ans.editing === a.id) return `<div class="ans-row">${answerForm(a, a.id)}</div>`;
    const review = a.mode !== 'always_use';
    return `<div class="ans-row hv"><div class="min0"><div class="q">${esc(a.question_text)}</div><div class="a">${esc(a.answer) || '<span class="faint">(empty)</span>'}</div></div>
      <div class="end"><div class="act"><button class="btn sm icon ghost hv" data-act="ans-edit" data-id="${a.id}" title="Edit answer">${icon('edit')}</button><button class="btn sm icon ghost danger hv" data-act="ans-del" data-id="${a.id}" title="Delete answer">${icon('delete')}</button></div>
        ${a.source === 'gemini' ? '<span class="chip violet">AI</span>' : ''}<span class="chip ${review ? 'amber' : ''}">${review ? 'Review' : 'Always use'}</span>
        <span class="uses" title="Times auto-filled">${a.usage_count ? '×' + a.usage_count : ''}</span></div></div>`;
  }
  function answerForm(a, id) {
    const modes = MODES.includes(a.mode) ? MODES : [a.mode, ...MODES];
    const cats = Object.keys(CATS).includes(a.category) ? Object.keys(CATS) : [a.category, ...Object.keys(CATS)];
    const fid = `af-${id}`;
    return `<form class="ans-edit" data-ans-form="${id}">
      <div class="field"><label for="${fid}-q">Question</label><input class="input" id="${fid}-q" name="question_text" value="${esc(a.question_text)}" required></div>
      <div class="field"><label for="${fid}-a">Answer</label><textarea class="textarea" id="${fid}-a" name="answer" required>${esc(a.answer)}</textarea></div>
      <div class="row2"><div class="field"><label for="${fid}-c">Category</label><select class="select" id="${fid}-c" name="category">${cats.map(c => `<option value="${esc(c)}" ${c === a.category ? 'selected' : ''}>${esc(catName(c))}</option>`).join('')}</select></div>
        <div class="field"><label for="${fid}-m">When filling forms</label><select class="select" id="${fid}-m" name="mode">${modes.map(m => `<option value="${esc(m)}" ${m === a.mode ? 'selected' : ''}>${m === 'always_use' ? 'Always use' : m === 'ask me to review' ? 'Ask me to review' : esc(m)}</option>`).join('')}</select></div></div>
      <div class="row-end"><button type="button" class="btn ghost hv" data-act="ans-cancel">Cancel</button><button type="submit" class="btn primary hv">${id === 'new' ? 'Add answer' : 'Save'}</button></div></form>`;
  }
  afterRender.answers = () => {
    const q = $('#ans-q');
    q && q.addEventListener('input', debounce(e => { S.ans.q = e.target.value; const pos = e.target.selectionStart; render(); const n = $('#ans-q'); n.focus(); n.setSelectionRange(pos, pos); }, 150));
    if (S.ans.adding || S.ans.editing) { const t = $(S.ans.adding ? '[data-ans-form] [name=question_text]' : '[data-ans-form] [name=answer]'); t && t.focus(); }
  };

  // ───────────────────────── View: Activity ─────────────────────────
  renderers.activity = () => {
    const A = S.act, q = A.q.trim().toLowerCase();
    const norm = (l) => l === 'warning' ? 'warn' : l;
    const counts = { all: S.logs.length }; S.logs.forEach(l => { const k = norm(l.level); counts[k] = (counts[k] || 0) + 1; });
    const list = S.logs.filter(l => (A.level === 'all' || norm(l.level) === A.level) && (!q || `${l.message} ${l.event_type} ${l.company}`.toLowerCase().includes(q)));
    const rows = list.map(l => `<tr><td class="faint tnum mono">${esc(l.created_at)}</td><td><span class="lvl ${esc(l.level)}">${esc(l.level)}</span></td>
      <td class="hide-m"><span class="chip">${esc(l.event_type)}</span></td><td class="msg"><span class="dot ${logColor(l)}"></span> ${esc(l.message)}</td></tr>`).join('');
    return `${pageHead()}<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="act-q" aria-label="Filter log" placeholder="Filter log" value="${esc(A.q)}"></div>
      <div class="seg" data-glide="level">${['all', 'info', 'warn', 'error'].map(l => `<button class="${A.level === l ? 'on' : ''}" data-level="${l}" aria-pressed="${A.level === l}">${l[0].toUpperCase() + l.slice(1)} <span class="n">${counts[l] || 0}</span></button>`).join('')}</div>
      <div class="spacer"></div><span class="live-ind"><span class="dot teal pulse"></span>Live</span>
      <button class="btn hv" data-act="backup">${icon('backup')}Back up now</button></div>
      <div class="card"><div class="table-wrap"><table class="tbl log-tbl"><thead><tr><th class="w-time">Time</th><th class="w-lvl">Level</th><th class="hide-m w-ev">Event</th><th>Message</th></tr></thead>
      <tbody>${rows || `<tr><td colspan="4"><div class="empty">No log entries</div></td></tr>`}</tbody></table></div></div>`;
  };
  afterRender.activity = () => {
    const q = $('#act-q');
    q && q.addEventListener('input', debounce(e => { S.act.q = e.target.value; const pos = e.target.selectionStart; render(); const n = $('#act-q'); n.focus(); n.setSelectionRange(pos, pos); }, 150));
  };

  // ───────────────────────── View: Profile & rules ─────────────────────────
  renderers.settings = () => {
    const p = S.profile; if (!p) return emptyCard('person_off', 'Profile not available');
    const g = S.gemini || {}, st = S.stats || {}, au = S.automation || {};
    const f = (name, label, opts = {}) => {
      const v = p[name] ?? '';
      const type = opts.type || 'text';
      const val = Array.isArray(v) ? v.join(', ') : v;
      return `<div class="field ${opts.full ? 'full' : ''}"><label for="f-${name}">${label}</label><input class="input ${type === 'number' ? 'tnum' : ''}" id="f-${name}" name="${name}" type="${type}" ${opts.step ? `step="${opts.step}"` : ''} ${opts.min !== undefined ? `min="${opts.min}"` : ''} ${opts.max !== undefined ? `max="${opts.max}"` : ''} value="${esc(val)}" data-kind="${Array.isArray(v) ? 'list' : type}">${opts.hint ? `<span class="hint">${opts.hint}</span>` : ''}</div>`;
    };
    const tg = (name, label, hint) => `<label class="set-row hv"><div class="grow">${label}${hint ? `<small>${hint}</small>` : ''}</div><span class="toggle"><input type="checkbox" name="${name}" ${p[name] ? 'checked' : ''}><i></i></span></label>`;
    const save = (label) => `<div class="full row-end"><button class="btn primary hv" type="submit">${label}</button></div>`;
    return `${pageHead()}
    <div class="settings">
      <div class="stack">
        <div class="card"><div class="profile-hero">${art(p.full_name, 'lg')}<div class="min0"><h2>${esc(p.full_name)}</h2><div class="muted small">${esc(p.education)} · CGPA ${esc(p.cgpa)}</div></div></div></div>

        <div class="card"><div class="card-h"><span class="card-t">Appearance</span><span class="aside">Saved on this device</span></div>
          <div class="card-b">${themeSwatches()}</div></div>

        <form class="card" data-profile-form="engine"><div class="card-h"><span class="card-t">Engine</span><span class="aside">${st.go_live ? '<span class="chip accent">Live submissions</span>' : '<span class="chip">Dry run</span>'}</span></div>
          <div class="set-list">
            <div class="set-row"><div class="grow">Live submissions<small>${st.go_live ? 'Applications are really submitted to employers.' : 'Forms are filled and screenshotted but never submitted.'}</small></div><button type="button" class="btn sm hv ${st.go_live ? 'danger' : ''}" data-act="${st.go_live ? 'mode-dry' : 'mode-live'}">${st.go_live ? 'Switch to dry run' : 'Go live…'}</button></div>
            <div class="set-row"><div class="grow">Queue<small>${esc(engineLabel(st)[0])}${au.affected_queue_count ? ` · ${au.affected_queue_count} jobs waiting` : ''}</small></div><button type="button" class="btn sm hv" data-act="${st.is_paused ? 'resume' : 'pause'}">${st.is_paused ? 'Resume' : 'Pause'}</button></div>
          </div>
          <div class="card-b form-grid card-sep">
            ${f('daily_cap', 'Daily cap', { type: 'number', min: 0 })}${f('daily_target', 'Daily target', { type: 'number', min: 0 })}
            ${f('hourly_cap', 'Hourly cap', { type: 'number', min: 0 })}${f('timezone', 'Timezone')}
            ${f('active_hours_start', 'Active from (hour)', { type: 'number', min: 0, max: 23 })}${f('active_hours_end', 'Active until (hour)', { type: 'number', min: 0, max: 24 })}
            ${f('min_fit_score', 'Auto-queue at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Jobs at or above this are queued automatically' })}${f('maybe_fit_score', 'Triage at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Between the two lands in Needs you › Triage' })}
            ${save('Save engine rules')}
          </div></form>

        <form class="card" data-gemini-form><div class="card-h"><span class="card-t">Gemini auto-answer</span><span class="aside tnum">${fmt(g.gemini_answers_today || 0)} today · ~${fmt(g.saved_minutes || 0)} min saved</span></div>
          <div class="set-list"><label class="set-row hv"><div class="grow">Draft answers for unknown questions<small>Grounded only in your locked facts. Drafts wait in Needs you › AI drafts.</small></div><span class="toggle"><input type="checkbox" name="gemini_auto_answer_enabled" ${g.gemini_auto_answer_enabled ? 'checked' : ''}><i></i></span></label></div>
          <div class="card-b form-grid card-sep">
            <div class="field"><label for="g-conf">Minimum confidence</label><div class="range-row"><input type="range" id="g-conf" name="gemini_min_confidence" min="0.5" max="1" step="0.01" value="${g.gemini_min_confidence ?? 0.85}"><output>${Math.round((g.gemini_min_confidence ?? 0.85) * 100)}%</output></div></div>
            <div class="field"><label for="g-cap">Daily answer cap</label><input class="input tnum" id="g-cap" type="number" name="gemini_daily_cap" min="0" value="${g.gemini_daily_cap ?? 30}"></div>
            <div class="field full"><label>Always asks you about</label><div class="tags">${(g.gemini_sensitive_categories || []).map(c => `<span class="chip">${esc(c.replace(/_/g, ' '))}</span>`).join('')}</div></div>
            <div class="full row-between"><span class="faint small">${esc(g.model_name || '')}${g.circuit_breaker_active ? ' · <span class="bad">rate-limit breaker active</span>' : ''}</span><button class="btn primary hv" type="submit">Save</button></div>
          </div></form>
      </div>

      <div class="stack">
        <form class="card" data-profile-form="targeting"><div class="card-h"><span class="card-t">Targeting</span></div>
          <div class="card-b form-grid">
            ${f('target_roles', 'Target roles', { full: true, hint: 'Comma separated' })}
            ${f('locations', 'Locations', { full: true, hint: 'Comma separated' })}
            ${f('excluded_companies', 'Never apply to', { full: true, hint: 'Comma separated' })}
            ${f('min_salary_inr', 'Minimum salary (₹ / year)', { type: 'number', min: 0 })}${f('min_stipend_inr', 'Minimum stipend (₹ / month)', { type: 'number', min: 0 })}
            ${f('preferred_work_mode', 'Work mode', { full: true })}
          </div>
          <div class="set-list card-sep">${tg('allow_unknown_salary', 'Apply when pay is not listed')}${tg('allow_unpaid_internships', 'Allow unpaid internships')}</div>
          <div class="card-b row-end">${save('Save targeting')}</div></form>

        <form class="card" data-profile-form="contact"><div class="card-h"><span class="card-t">Contact & credentials</span><span class="aside">Used verbatim on forms</span></div>
          <div class="card-b form-grid">
            ${f('full_name', 'Full name')}${f('email', 'Email', { type: 'email' })}
            ${f('phone', 'Phone')}${f('cgpa', 'CGPA')}
            ${f('education', 'Education', { full: true })}
            ${f('linkedin', 'LinkedIn', { full: true })}${f('github', 'GitHub', { full: true })}
            ${f('graduation_date', 'Graduation date')}${f('notice_period', 'Notice period')}
            ${f('work_authorization', 'Work authorization')}${f('relocation_preference', 'Relocation')}
            ${save('Save contact')}
          </div></form>

        <div class="card"><div class="card-h"><span class="card-t">Resume versions</span><span class="aside">${S.resumes.length}</span></div>
          <div class="list">${S.resumes.map(r => `<div class="row"><span class="art plain">${icon('description')}</span>
            <div class="grow"><div class="main-t">${esc(r.version_name)}</div><div class="sub-t">${esc(r.target_role)} · ATS ${Math.round(r.ats_score)}</div></div>
            <div class="end">${r.is_master ? '<span class="chip teal">Master</span>' : ''}${r.pdf_path ? `<a class="btn sm icon ghost hv" href="${esc(r.pdf_path)}" target="_blank" rel="noopener" title="Open PDF">${icon('open_in_new')}</a>` : ''}</div></div>`).join('') || '<div class="empty">No resume versions</div>'}</div></div>
        ${IN_SHELL ? `<div class="card"><div class="set-list"><div class="set-row"><div class="grow">Phone app connection<small>${esc(location.host)}</small></div><button type="button" class="btn sm hv" data-act="shell-server">Change server</button></div></div></div>` : ''}
      </div>
    </div>`;
  };
  afterRender.settings = () => {
    const r = $('#g-conf');
    r && r.addEventListener('input', () => { r.nextElementSibling.value = Math.round(r.value * 100) + '%'; });
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
      box.outerHTML = `<textarea class="textarea mt-2" aria-label="Edit answer">${esc(a.answer)}</textarea>`;
      card.querySelector('.qactions').innerHTML = `<button class="btn primary sm hv" data-act="ai-save" data-id="${id}">${icon('check')}Save & approve</button><button class="btn sm ghost hv" data-act="ai-cancel">Cancel</button>`;
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
      ...THEMES.map(t => ({ icon: 'palette', label: `Theme: ${t.name}`, hint: themePref() === t.id ? 'Current' : t.note, run: () => setTheme(t.id) })),
      { icon: 'brightness_auto', label: 'Theme: Match system', hint: themePref() === 'auto' ? 'Current' : '', run: () => setTheme('auto') },
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
    const sec = (title, items) => items.length ? `<div class="palette-sec">${title}</div>` + items.map(x => `<button class="palette-item hv ${i === pal.sel ? 'on' : ''}" data-pi="${i++}" role="option" aria-selected="${i - 1 === pal.sel}">${icon(x.icon)}<span class="grow">${esc(x.label)}</span>${x.hint ? `<span class="hint">${esc(x.hint)}</span>` : ''}</button>`).join('') : '';
    $('#pal-list').innerHTML = sec('Jobs', jobs) + sec('Commands', cmds) || `<div class="empty">No matches</div>`;
    const on = $('#pal-list .on'); on && on.scrollIntoView({ block: 'nearest' });
  }
  function execPalette(i) { const x = pal && pal.flat[i]; closePalette(); x && x.run(); }
  function closePalette() { pal = null; $('#overlay').innerHTML = ''; }
  $('#search-trigger').addEventListener('click', openPalette);

  // ───────────────────────── Themes ─────────────────────────
  // Every colour lives in a [data-theme] block in app.css. The choice is saved in
  // localStorage (applied before first paint by the inline script in index.html) and
  // switched with a View Transition cross-fade, so there is no flash between themes.
  const THEMES = [
    { id: 'neutral', name: 'Neutral', note: 'Default · light' },
    { id: 'neutral-dark', name: 'Neutral Dark', note: 'Charcoal' },
    { id: 'midnight', name: 'Midnight', note: 'Deep blue' },
    { id: 'rose', name: 'Rose', note: 'Music-inspired accent' },
  ];
  const THEME_KEY = 'ap_theme';
  const LEGACY_THEME = { light: 'neutral', dark: 'rose' };
  const darkQuery = matchMedia('(prefers-color-scheme: dark)');
  function themePref() {
    let p = 'neutral';
    try { p = localStorage.getItem(THEME_KEY) || 'neutral'; } catch (e) {}
    p = LEGACY_THEME[p] || p;
    return p === 'auto' || THEMES.some(t => t.id === p) ? p : 'neutral';
  }
  const resolveTheme = (p) => p === 'auto' ? (darkQuery.matches ? 'neutral-dark' : 'neutral') : p;
  function applyTheme(pref, animate = true) {
    const id = resolveTheme(pref), root = document.documentElement;
    const swap = () => {
      root.dataset.theme = id;
      const cs = getComputedStyle(root), bg = cs.getPropertyValue('--bg').trim();
      const m = $('meta[name=theme-color]'); if (m) m.content = bg;
      // Android app: let the native status/navigation bars match the page ("theme:#RRGGBB:light|dark").
      if (IN_SHELL) window.ApplyPilotShell.postMessage(`theme:${bg}:${cs.colorScheme.includes('dark') ? 'dark' : 'light'}`);
    };
    if (root.dataset.theme === id) return swap();
    if (animate && document.startViewTransition && !matchMedia('(prefers-reduced-motion: reduce)').matches) document.startViewTransition(swap);
    else swap();
  }
  function setTheme(pref) {
    try { localStorage.setItem(THEME_KEY, pref); } catch (e) {}
    applyTheme(pref);
    syncThemeControls();
    const t = THEMES.find(x => x.id === resolveTheme(pref));
    toast(pref === 'auto' ? `Theme follows your system · ${t.name}` : `${t.name} theme`);
  }
  darkQuery.addEventListener('change', () => { if (themePref() === 'auto') { applyTheme('auto'); syncThemeControls(); } });

  // Swatches render a live mini-preview using each theme's own tokens (data-theme on the preview).
  function themeSwatches() {
    const pref = themePref(), cur = resolveTheme(pref);
    return `<div class="swatches" role="radiogroup" aria-label="Theme">${THEMES.map(t => `<button class="swatch ${cur === t.id ? 'on' : ''}" role="radio" aria-checked="${pref === t.id}" data-theme-choice="${t.id}">
      <span class="check">${icon('check')}</span>
      <span class="preview" data-theme="${t.id}" aria-hidden="true"><span class="p-side"></span><span class="p-main"><span class="p-line"></span><span class="p-line s"></span><span class="p-card"><span class="p-btn"></span></span></span></span>
      <span class="swatch-name">${t.name}</span><span class="swatch-note">${t.note}</span></button>`).join('')}</div>
      <label class="theme-row"><span class="grow">Match system<small>Neutral by day, Neutral Dark at night</small></span>
        <span class="toggle"><input type="checkbox" data-theme-auto ${pref === 'auto' ? 'checked' : ''}><i></i></span></label>`;
  }
  function syncThemeControls() {
    const pref = themePref(), cur = resolveTheme(pref);
    $$('.swatch').forEach(s => { s.classList.toggle('on', s.dataset.themeChoice === cur); s.setAttribute('aria-checked', String(pref === s.dataset.themeChoice)); });
    $$('[data-theme-auto]').forEach(c => { c.checked = pref === 'auto'; });
  }
  function openThemePop() {
    if ($('#theme-pop')) { closeThemePop(); return; }
    document.body.insertAdjacentHTML('beforeend', `<div class="theme-pop" id="theme-pop" role="dialog" aria-label="Appearance">
      <h3>Appearance</h3><p>Saved on this device.</p>${themeSwatches()}</div>`);
    $('#theme-btn').setAttribute('aria-expanded', 'true');
    const first = $('#theme-pop .swatch.on') || $('#theme-pop .swatch'); first && first.focus({ preventScroll: true });
  }
  function closeThemePop(restoreFocus = false) {
    const p = $('#theme-pop'); if (!p) return;
    p.remove();
    $('#theme-btn').setAttribute('aria-expanded', 'false');
    if (restoreFocus) $('#theme-btn').focus({ preventScroll: true });
  }
  $('#theme-btn').addEventListener('click', (e) => { e.stopPropagation(); openThemePop(); });
  document.addEventListener('click', (e) => {
    const choice = e.target.closest('[data-theme-choice]');
    if (choice) { setTheme(choice.dataset.themeChoice); return; }
    if ($('#theme-pop') && !e.target.closest('#theme-pop')) closeThemePop();
  });
  document.addEventListener('change', (e) => {
    if (e.target.matches('[data-theme-auto]')) setTheme(e.target.checked ? 'auto' : resolveTheme('auto'));
  });
  // Arrow keys move between swatches; Escape closes the popover.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && $('#theme-pop')) { e.stopImmediatePropagation(); closeThemePop(true); return; }
    const sw = e.target.closest && e.target.closest('.swatch');
    if (!sw || !/^Arrow(Left|Right|Up|Down)$/.test(e.key)) return;
    e.preventDefault();
    const all = $$('.swatch', sw.parentElement), step = /Right|Down/.test(e.key) ? 1 : -1;
    all[(all.indexOf(sw) + step + all.length) % all.length].focus();
  }, true);

  document.addEventListener('keydown', (e) => {
    if (pal) {
      if (e.key === 'Escape') { e.preventDefault(); closePalette(); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); pal.sel = Math.min(pal.flat.length - 1, pal.sel + 1); drawPalette(); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); pal.sel = Math.max(0, pal.sel - 1); drawPalette(); }
      else if (e.key === 'Enter') { e.preventDefault(); execPalette(pal.sel); }
      return;
    }
    // Table rows open the job sheet from the keyboard like buttons do.
    if ((e.key === 'Enter' || e.key === ' ') && e.target.matches && e.target.matches('tr[data-job]')) { e.preventDefault(); openJob(e.target.dataset.job); return; }
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
    // render({ poll: true }) skips the DOM entirely when nothing changed, so hovers are never interrupted.
    if (S.view === 'today') { try { await loaders.today(); if (S.view === 'today') render({ poll: true }); } catch (e) {} }
    if (S.view === 'activity') { try { await loaders.activity(); if (S.view === 'activity') render({ poll: true }); } catch (e) {} }
  }

  // ───────────────────────── Boot ─────────────────────────
  (async () => {
    applyTheme(themePref(), false);   // pre-paint script set the theme; this syncs the browser chrome colour
    initLiquidGlass();
    renderChrome();
    const start = location.hash.replace(/^#\/?/, '') || 'today';
    // Inbox counts power the nav badge everywhere, so fetch them alongside the first view.
    await Promise.allSettled([loadStats(), loaders.inbox()]);
    go(start);
    setInterval(poll, 15000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
  })();
})();
