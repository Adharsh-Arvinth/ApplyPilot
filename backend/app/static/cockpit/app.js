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
  // Your photo (Settings › Profile), or your initials until you add one
  const me = (size = '') => (S.avatar && S.avatar.has_avatar)
    ? `<img class="avatar ${size}" src="/api/v1/profile/avatar?v=${S.avatar.version}" alt="" decoding="async">`
    : art((S.profile && S.profile.full_name) || 'You', size);
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

  // Read-only text sheet (cover letter, interview prep) with a copy button.
  function textSheet(title, text, note = '') {
    $('#overlay').innerHTML = `<div class="modal-wrap" data-close><div class="modal sheet-modal" role="dialog" aria-modal="true" aria-labelledby="sheet-t">
      <h3 id="sheet-t">${esc(title)}</h3>${note ? `<p class="small">${esc(note)}</p>` : ''}
      <textarea class="textarea sheet-text" id="sheet-text" spellcheck="true">${esc(text || '')}</textarea>
      <div class="acts"><button class="btn ghost hv" data-x="close">Close</button><button class="btn primary hv" data-act="copy-text">${icon('content_copy')}Copy</button></div></div></div>`;
    $('#overlay .modal-wrap').addEventListener('click', (e) => { if (e.target.hasAttribute('data-close') || e.target.closest('[data-x="close"]')) $('#overlay').innerHTML = ''; });
    $('#sheet-text').focus();
  }
  function openProof(id) {
    const p = (S.proofs || []).find(x => x.id === id); if (!p) return;
    const k = PROOF_KIND[p.kind] || [p.kind, ''];
    $('#overlay').innerHTML = `<div class="modal-wrap" data-close><div class="modal sheet-modal" role="dialog" aria-modal="true" aria-labelledby="proof-t">
      <div class="row-between mb-2">${art(p.company, 'lg')}<span class="chip ${k[1]}">${esc(k[0])}</span></div>
      <h3 id="proof-t">${esc(p.subject || p.company)}</h3>
      <p class="small">${esc(p.sender)} · ${esc(stamp(p.received_at))}</p>
      <p class="proof-body">${esc(p.snippet || '')}${(p.snippet || '').length >= 600 ? '…' : ''}</p>
      <div class="acts"><button class="btn ghost hv" data-x="close">Close</button>${p.job_id ? `<button class="btn primary hv" data-x="job">Open application</button>` : ''}</div></div></div>`;
    $('#overlay .modal-wrap').addEventListener('click', (e) => {
      if (e.target.closest('[data-x="job"]')) { $('#overlay').innerHTML = ''; openJob(p.job_id); }
      else if (e.target.hasAttribute('data-close') || e.target.closest('[data-x="close"]')) $('#overlay').innerHTML = '';
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
    { id: 'submitted', label: 'Submitted', color: 'teal', statuses: ['applied', 'submitted', 'unverified'] },
    { id: 'practice', label: 'Dry runs', color: 'indigo', statuses: ['dry_run'] },
    { id: 'interview', label: 'Interview', color: 'sky', statuses: ['interview', 'offer'] },
    { id: 'new', label: 'Discovered', color: 'slate', statuses: ['discovered'] },
    { id: 'closed', label: 'Closed', color: 'coral', statuses: ['skipped', 'rejected', 'failed', 'dismissed', 'blocked', 'expired'] },
  ];
  const stageOf = (status) => STAGES.find(s => s.statuses.includes(status)) || STAGES.find(s => s.id === 'new');
  const STATUS_LABEL = {
    maybe: 'Maybe', evaluated: 'Evaluated', needs_verification: 'Verify', queued: 'Queued', approved: 'Queued',
    applying: 'Applying', needs_review: 'Needs review', needs_attention: 'Attention', needs_input: 'Needs you',
    dry_run: 'Dry run · not sent', unverified: 'Sent · unconfirmed', applied: 'Applied', submitted: 'Submitted', interview: 'Interview', offer: 'Offer',
    discovered: 'Discovered', skipped: 'Skipped', rejected: 'Rejected', failed: 'Failed', dismissed: 'Dismissed', blocked: 'Blocked', expired: 'Expired',
  };
  const statusColor = (s) => ({ needs_review: 'violet', needs_attention: 'amber', needs_input: 'amber', failed: 'coral', rejected: 'coral', blocked: 'coral', skipped: 'slate', dismissed: 'slate', dry_run: 'indigo', unverified: 'amber', offer: 'teal', interview: 'sky' }[s] || stageOf(s).color);
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
    view: 'home', fresh: {},
    stats: null, analytics: null, logs: [], automation: null, profile: null, gemini: null, resumes: [],
    jobs: null, needs: [], aiAnswers: [], triage: [], answers: null,
    autopilot: null, proofStatus: null, proofs: [], resume: null,
    inbox: { tab: 'questions', sel: 0, picks: {}, remember: true },
    pipe: { stage: 'all', q: '', source: '', min: '', mode: 'table', sort: 'score', dir: -1, limit: 100, laneLimit: {} },
    ans: { cat: 'all', q: '', editing: null, adding: false },
    act: { level: 'all', q: '' },
    ins: { tab: 'overview' },
    proof: { kind: 'all' },
    set: { section: 'profile' },
    jobId: null, job: null, returnFocus: null,
    online: true, anim: false, lastHtml: '',
  };

  const today = () => new Date().toLocaleDateString('en-IN', { weekday: 'long', day: 'numeric', month: 'long' });
  const VIEWS = [
    { id: 'home', label: 'Home', icon: 'home', mobile: 'home', sub: today },
    { id: 'inbox', label: 'Needs you', icon: 'inbox', mobile: 'notifications', sub: () => 'Decisions only you can make' },
    { id: 'pipeline', label: 'Applications', icon: 'work', mobile: 'work', sub: () => S.jobs ? `${fmt(S.jobs.length)} roles tracked` : 'Every role ApplyPilot is tracking' },
    { id: 'proof', label: 'Proof', icon: 'mark_email_read', mobile: 'mark_email_read', sub: () => 'Emails from employers confirming your applications' },
    { id: 'insights', label: 'Insights', icon: 'insights', sub: () => 'Trends, funnel and the engine log' },
    { id: 'settings', label: 'Settings', icon: 'settings', mobile: 'settings', sub: () => 'Profile, resume, autopilot, appearance and help' },
  ];
  // Old links keep working: #/today, #/activity, #/answers
  const VIEW_ALIAS = { today: ['home'], activity: ['insights', 'log'], answers: ['settings', 'answers'] };
  const MOBILE_TABS = ['home', 'inbox', 'pipeline', 'proof', 'settings'];
  const MOBILE_LABEL = { home: 'Home', inbox: 'Needs You', pipeline: 'Jobs', proof: 'Proof', settings: 'Settings' };

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
      && !matchMedia('(prefers-reduced-transparency: reduce)').matches
      && !document.documentElement.classList.contains('lite'); // the displacement filter is too heavy for phones
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
  const SPEC = '.btn, .search-trigger, .lcd, .filter-chip, .nav-item, .set-link, .seg button, .mode-switch button';
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

  // ── Horizontal scrollers: mouse wheel, mouse drag and soft edge fades ──
  // Tab-like rows turn a vertical wheel into a smooth sideways glide (until they reach an end,
  // then the page scrolls as usual). Every scroller can be dragged with the mouse, and fades
  // its edges while more content is hidden there.
  const HSCROLL = '.set-nav, .chips-scroll, .cat-list, .shelf, .board';
  const WHEEL_X = '.set-nav, .chips-scroll, .cat-list';
  const reduceMotion = () => document.documentElement.dataset.motion === 'reduce' || matchMedia('(prefers-reduced-motion: reduce)').matches;
  let setNavLeft = 0;
  function edgeFade(el) {
    const max = el.scrollWidth - el.clientWidth;
    const f = max > 1 ? [el.scrollLeft > 1 ? 'l' : '', el.scrollLeft < max - 1 ? 'r' : ''].filter(Boolean).join(' ') : '';
    if ((el.dataset.fade || '') !== f) { if (f) el.dataset.fade = f; else delete el.dataset.fade; }
  }
  function hscroll(root) { $$(HSCROLL, root || document).forEach(edgeFade); }
  document.addEventListener('scroll', (e) => {
    const el = e.target;
    if (!(el instanceof Element) || !el.matches(HSCROLL)) return;
    edgeFade(el);
    if (el.classList.contains('set-nav')) setNavLeft = el.scrollLeft;
  }, { capture: true, passive: true });
  let fadeRaf = 0;
  window.addEventListener('resize', () => { cancelAnimationFrame(fadeRaf); fadeRaf = requestAnimationFrame(() => hscroll(document)); }, { passive: true });

  const wheelGoal = new WeakMap();
  document.addEventListener('wheel', (e) => {
    if (e.ctrlKey || Math.abs(e.deltaX) >= Math.abs(e.deltaY)) return;
    const el = e.target.closest && e.target.closest(WHEEL_X);
    if (!el) return;
    const max = el.scrollWidth - el.clientWidth;
    if (max <= 1) return;
    const dy = e.deltaY * (e.deltaMode === 1 ? 32 : e.deltaMode === 2 ? el.clientWidth : 1);
    const from = wheelGoal.has(el) ? wheelGoal.get(el) : el.scrollLeft;
    if ((dy < 0 && from <= 0) || (dy > 0 && from >= max - 1)) return; // at an end: let the page scroll
    e.preventDefault();
    const goal = Math.max(0, Math.min(max, from + dy));
    if (reduceMotion()) { el.scrollLeft = goal; return; }
    const running = wheelGoal.has(el);
    wheelGoal.set(el, goal);
    if (running) return;
    const step = () => {
      if (!wheelGoal.has(el)) return;
      const g = wheelGoal.get(el), d = g - el.scrollLeft;
      if (Math.abs(d) < 0.5) { el.scrollLeft = g; wheelGoal.delete(el); return; }
      el.scrollLeft += d * 0.2;
      requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }, { passive: false });

  let hdrag = null;
  document.addEventListener('pointerdown', (e) => {
    if (e.pointerType !== 'mouse' || e.button !== 0) return;
    const el = e.target.closest && e.target.closest(HSCROLL);
    if (!el || el.scrollWidth - el.clientWidth <= 1 || e.target.closest('input, textarea, select, [draggable="true"]')) return;
    hdrag = { el, x: e.clientX, left: el.scrollLeft, moved: false };
  });
  document.addEventListener('pointermove', (e) => {
    if (!hdrag) return;
    const dx = e.clientX - hdrag.x;
    if (!hdrag.moved) {
      if (Math.abs(dx) < 6) return;
      hdrag.moved = true; hdrag.el.classList.add('hdrag'); wheelGoal.delete(hdrag.el);
    }
    hdrag.el.scrollLeft = hdrag.left - dx;
  });
  const endDrag = () => {
    if (!hdrag) return;
    const { el, moved } = hdrag; hdrag = null;
    el.classList.toggle('hdrag', false);
    if (moved) { // a drag is not a click on whatever was under the pointer
      const swallow = (ev) => { ev.stopPropagation(); ev.preventDefault(); };
      document.addEventListener('click', swallow, { capture: true, once: true });
      setTimeout(() => document.removeEventListener('click', swallow, true), 0);
    }
  };
  document.addEventListener('pointerup', endDrag);
  document.addEventListener('pointercancel', endDrag);

  // After every render: sliding pills + accessible names for icon-only controls.
  function enhance(root) {
    $$('.seg', root).forEach((el, i) => glide(el, `${S.view}:${el.dataset.glide || i}`));
    const setNav = $('.set-nav', root);
    if (setNav) {
      glide(setNav, 'settings', '.set-link.on');
      // Horizontal on narrow screens: keep where you were, then bring the chosen tab into view
      const on = $('.set-link.on', setNav), max = setNav.scrollWidth - setNav.clientWidth;
      if (on && max > 1) {
        setNav.scrollLeft = setNavLeft;
        const want = Math.max(0, Math.min(max, on.offsetLeft - (setNav.clientWidth - on.offsetWidth) / 2));
        if (Math.abs(want - setNav.scrollLeft) > 1) setNav.scrollTo({ left: want, behavior: reduceMotion() ? 'auto' : 'smooth' });
      }
    }
    hscroll(root);
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

  // ── Tab bar: hold and glide (like Apple Music) ──
  // Press a tab and the glass lens swells; slide and it follows your finger with a light tick on
  // every tab it crosses; lift to open the tab under your finger. A plain tap works as before.
  (function tabGlide() {
    const bar = $('#tabbar');
    if (!bar) return;
    let drag = null;
    const tabs = () => $$('button[data-nav]', bar);
    const tabAt = (x) => {
      const list = tabs();
      return list.find(b => { const r = b.getBoundingClientRect(); return x >= r.left && x < r.right; })
        || (x < bar.getBoundingClientRect().left + 8 ? list[0] : list[list.length - 1]);
    };
    const lens = () => bar.querySelector(':scope > .glide');
    const tick = () => { try { navigator.vibrate && navigator.vibrate(6); } catch (e) {} };
    const follow = (x) => {
      const l = lens(); if (!l) return;
      const br = bar.getBoundingClientRect(), w = l.offsetWidth;
      const left = Math.max(0, Math.min(br.width - w, x - br.left - w / 2));
      l.style.translate = `${left}px ${l.style.translate.split(' ')[1] || '0px'}`;
    };
    const hot = (btn) => tabs().forEach(b => b.classList.toggle('hot', b === btn));
    bar.addEventListener('pointerdown', (e) => {
      const btn = e.target.closest('button[data-nav]');
      if (!btn || (e.pointerType === 'mouse' && e.button !== 0)) return;
      drag = { id: e.pointerId, x0: e.clientX, over: btn, gliding: false };
      const l = lens(); if (l) l.classList.add('held');
      hot(btn);
    });
    bar.addEventListener('pointermove', (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      if (!drag.gliding) {
        if (Math.abs(e.clientX - drag.x0) < 8) return;
        drag.gliding = true;
        try { bar.setPointerCapture(e.pointerId); } catch (err) {}
        const l = lens(); if (l) l.classList.add('gliding');
      }
      follow(e.clientX);
      const over = tabAt(e.clientX);
      if (over && over !== drag.over) { drag.over = over; hot(over); tick(); }
    });
    const end = (e, cancel) => {
      if (!drag || (e && e.pointerId !== drag.id)) return;
      const { gliding, over } = drag; drag = null;
      const l = lens(); if (l) l.classList.remove('held', 'gliding');
      hot(null);
      if (!gliding) return; // a plain tap: the normal click handler navigates
      const swallow = (ev) => { ev.stopPropagation(); ev.preventDefault(); };
      document.addEventListener('click', swallow, { capture: true, once: true });
      setTimeout(() => document.removeEventListener('click', swallow, true), 0);
      if (cancel || !over) { glide(bar, 'tab', 'button.active'); return; }
      if (over.dataset.nav === S.view) glide(bar, 'tab', 'button.active');
      else go(over.dataset.nav);
    };
    bar.addEventListener('pointerup', (e) => end(e, false));
    bar.addEventListener('pointercancel', (e) => end(e, true));
    bar.addEventListener('contextmenu', (e) => e.preventDefault()); // long-press shouldn't open a menu
  })();

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
  // Run several requests, keep whatever succeeds (one slow/failed call never blanks a view).
  async function settle(map) {
    const keys = Object.keys(map);
    const res = await Promise.allSettled(keys.map(k => map[k]));
    res.forEach((r, i) => { if (r.status === 'fulfilled') S[keys[i]] = r.value; });
  }
  const loaders = {
    async home() {
      await settle({ autopilot: api('/autopilot'), proofStatus: api('/proofs/status'), proofs: api('/proofs', { query: { limit: 5 } }),
        resume: api('/profile/resume'), profile: api('/profile'), analytics: api('/analytics'), jobs: api('/jobs', { query: { compact: 1 } }), avatar: api('/profile/avatar/meta') });
    },
    async proof() {
      await settle({ proofStatus: api('/proofs/status'), proofs: api('/proofs', { query: { limit: 300 } }), stats: api('/stats') });
    },
    async insights() {
      await settle({ analytics: api('/analytics'), automation: api('/automation/status'), logs: api('/logs', { query: { limit: 250 } }) });
    },
    async inbox() {
      const [n, g, t] = await Promise.allSettled([api('/needs-you'), api('/needs-you/gemini-answers'), api('/jobs', { query: { status: 'maybe' } })]);
      if (n.status === 'fulfilled') S.needs = n.value;
      if (g.status === 'fulfilled') S.aiAnswers = g.value;
      if (t.status === 'fulfilled') S.triage = t.value;
    },
    async pipeline() { S.jobs = await api('/jobs', { query: { compact: 1 } }); },
    async settings() {
      await settle({ profile: api('/profile'), gemini: api('/profile/gemini-settings'), resumes: api('/resumes'),
        automation: api('/automation/status'), autopilot: api('/autopilot'), proofStatus: api('/proofs/status'),
        resume: api('/profile/resume'), answers: api('/answer-bank'), avatar: api('/profile/avatar/meta'), facts: api('/profile/facts'), localAI: api('/ai/local') });
    },
  };

  // ───────────────────────── Router ─────────────────────────
  let viewToken = 0;
  async function go(view, { silent = false } = {}) {
    // Accept "settings/appearance", "insights/log" and old view names.
    let [base, sub] = String(view || '').split('/');
    if (VIEW_ALIAS[base]) [base, sub = sub] = VIEW_ALIAS[base].length > 1 && !sub ? VIEW_ALIAS[base] : [VIEW_ALIAS[base][0], sub];
    if (base === 'settings' && sub) S.set.section = sub;
    if (base === 'insights' && sub) S.ins.tab = sub;
    view = VIEWS.some(v => v.id === base) ? base : 'home';
    const changed = S.view !== view;
    S.view = view;
    if (location.hash !== '#/' + view) history.replaceState(null, '', '#/' + view);
    renderChrome();
    const my = ++viewToken;
    if (changed) S.anim = true;
    // Seen this tab before? Show it instantly from memory, then refresh quietly in the background.
    const cached = !!S.fresh[view];
    if (cached && changed) { $('#content').scrollTop = 0; S.lastHtml = ''; render(); }
    else if (changed || !silent) { $('#content').innerHTML = skeleton(view); $('#content').scrollTop = 0; S.lastHtml = ''; }
    try { await loaders[view](); S.fresh[view] = Date.now(); if (view === 'home') persist(); }
    catch (e) { if (my === viewToken && !cached) $('#content').innerHTML = errorView(e); return; }
    if (my !== viewToken) return;
    render({ poll: cached });
    prefetchSoon();
  }
  // Warm every other tab while the app is idle, so the first visit is instant too.
  let prefetched = false;
  function prefetchSoon() {
    if (prefetched) return; prefetched = true;
    const idle = window.requestIdleCallback || ((fn) => setTimeout(fn, 600));
    idle(async () => {
      for (const v of ['home', 'pipeline', 'inbox', 'proof', 'settings', 'insights']) {
        if (S.fresh[v] || !loaders[v]) continue;
        try { await loaders[v](); S.fresh[v] = Date.now(); } catch (e) {}
        await new Promise(r => setTimeout(r, 150)); // stay out of the way of scrolling
      }
    }, { timeout: 2500 });
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
  const skeleton = (view) => `<div class="view" aria-busy="true"><div class="view-head"><div class="skel sk-title"></div></div>${view === 'home' || view === 'insights'
    ? `<div class="kpis">${'<div class="card kpi"><div class="skel sk-line"></div><div class="skel sk-num"></div></div>'.repeat(4)}</div>
       <div class="grid-today"><div class="card card-b span-8"><div class="skel sk-block"></div></div><div class="card card-b span-4"><div class="skel sk-block"></div></div></div>`
    : `<div class="card list">${'<div class="skel sk-row"></div>'.repeat(6)}</div>`}</div>`;
  const errorView = (e) => `<div class="view"><div class="card"><div class="empty error" role="alert">${icon('cloud_off')}<b>Couldn't reach the ApplyPilot backend</b><span>${esc(e.message)}</span><button class="btn hv" data-act="reload">${icon('refresh')}Try again</button></div></div></div>`;
  const emptyCard = (ic, title, text = '', extra = '') => `<div class="card"><div class="empty">${icon(ic)}<b>${title}</b>${text ? `<span>${text}</span>` : ''}${extra}</div></div>`;

  // ───────────────────────── View: Today ─────────────────────────
  const renderers = {};
  const afterRender = {};

  function insightsOverview() {
    const st = S.stats || {}, an = S.analytics || {}, au = S.automation || {};
    const goal = an.goal || {};
    const cap = st.daily_cap || goal.daily_target || 0;
    const applied = st.daily_applied || 0;
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
      ${kpi('data-nav="pipeline" data-stage="submitted"', 'teal', 'Submitted', fmt(st.total_submitted_real || 0), `sent to employers · ${fmt(st.total_dry_run || 0)} dry runs not sent`)}
      ${kpi('data-nav="pipeline" data-stage="interview"', 'teal', 'Interviews', fmt(st.interview_count), an.offers_count ? `${fmt(an.offers_count)} offers` : 'no offers yet')}
    </div>`;

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
    return `${kpis}
    <div class="grid-today">
      ${card('span-8', 'This week', `<span class="tnum">${fmt(goal.weekly_applied || 0)} of ${fmt(goal.weekly_target || 0)} goal</span>`, `<div class="card-b">${bars}</div>`)}
      ${card('span-4', 'Funnel', `<span class="tnum">${fmt(an.total_tracked || 0)} tracked</span>`, `<div class="card-b funnel">${funnelHtml || '<div class="empty">No data</div>'}</div>`)}
      ${card('span-12', 'Pre-flight', au.can_resume === false ? '<span class="chip coral">Blocked</span>' : '<span class="chip teal">Clear</span>',
        `<div class="card-b"><div class="checklist">${checkHtml || '<span class="faint">No checks reported</span>'}</div>${na.failed_tasks ? `<div class="alert-d mt-3">${fmt(na.failed_tasks)} failed tasks in the log</div>` : ''}</div>`)}
      ${card('span-6', 'Fit distribution', `<span class="tnum">${fmt(tTotal)} scored</span>`, `<div class="card-b">${tierHtml}</div>`)}
      ${card('span-6', 'Sources', `${src.length} boards`, `<div class="card-b">${srcHtml || '<div class="empty">No sources yet</div>'}</div>`)}
    </div>`;
  }


  // Calm dashboard: two small charts, numbers on demand (hover / tap), nothing shouting.
  function weekChart() {
    const week = ((S.analytics && S.analytics.weekly_trend) || []).map(w => ({
      ...w, sent: w.sent ?? w.count ?? 0, dry: w.dry_run ?? 0,
    }));
    if (!week.length) return '';
    const total = week.reduce((a, w) => a + w.sent + w.dry, 0);
    const sent = week.reduce((a, w) => a + w.sent, 0);
    const max = Math.max(1, ...week.map(w => w.sent + w.dry));
    const peak = week.reduce((b, w, i) => (w.sent + w.dry > week[b].sent + week[b].dry ? i : b), 0);
    const cols = week.map((w, i) => {
      const t = w.sent + w.dry, today = i === week.length - 1;
      const showV = t > 0 && (today || i === peak);
      const tip = `${w.day} ${w.date} · ${w.sent} sent · ${w.dry} dry run${w.dry === 1 ? '' : 's'}`;
      return `<div class="wk-col ${today ? 'today' : ''}" data-tip="${esc(tip)}" role="img" aria-label="${esc(tip)}">
        <span class="wk-v tnum">${showV ? t : ''}</span>
        <div class="wk-stack" style="height:${t ? Math.max(4, t / max * 100) : 0}%">
          ${w.dry ? `<i class="seg-dry" style="flex:${w.dry}"></i>` : ''}${w.sent ? `<i class="seg-sent" style="flex:${w.sent}"></i>` : ''}
        </div>
        <span class="wk-d">${esc(today ? 'Today' : w.day)}</span></div>`;
    }).join('');
    return `<div class="dash-pane">
      <div class="dash-h"><span class="dash-t">Applications</span><span class="dash-sub">last 7 days</span></div>
      <div class="dash-big tnum">${fmt(sent)}<span class="dash-of"> sent${total - sent ? ` · ${fmt(total - sent)} dry run${total - sent === 1 ? '' : 's'}` : ''}</span></div>
      <div class="wk">${cols}</div>
      <div class="legend"><span><i class="sw sent"></i>Sent</span><span><i class="sw dry"></i>Dry run</span></div>
    </div>`;
  }
  function stageChart() {
    const st = S.stats || {};
    const rows = [
      ['Waiting in queue', st.queue_count || 0, 'pipeline', 'queued'],
      ['Needs you', st.needs_you_count || 0, 'inbox', ''],
      ['Dry runs', st.total_dry_run || 0, 'pipeline', 'practice'],
      ['Sent to employers', st.total_submitted_real || 0, 'pipeline', 'submitted'],
      ['Interviews', st.interview_count || 0, 'pipeline', 'interview'],
    ];
    const max = Math.max(1, ...rows.map(r => r[1]));
    return `<div class="dash-pane">
      <div class="dash-h"><span class="dash-t">Where things stand</span><span class="dash-sub">all time</span></div>
      <div class="st-rows">${rows.map(([label, n, nav, stage]) => `<button class="st-row hv" data-nav="${nav}" ${stage ? `data-stage="${stage}"` : ''} data-tip="${esc(label)}: ${fmt(n)}">
        <span class="st-l">${label}</span><span class="st-bar"><i style="width:${n ? Math.max(2, n / max * 100) : 0}%"></i></span><span class="st-n tnum">${fmt(n)}</span></button>`).join('')}</div>
    </div>`;
  }
  const dashboard = () => {
    const w = weekChart();
    return `<section class="block"><h2 class="section-t">Your week</h2><div class="card dash">${w}${w ? '<div class="dash-rule" aria-hidden="true"></div>' : ''}${stageChart()}</div></section>`;
  };

  // One shared tooltip for anything with data-tip (charts). Pointer on desktop, tap on phones.
  const tipEl = document.createElement('div');
  tipEl.className = 'tip'; tipEl.setAttribute('role', 'tooltip');
  document.body.appendChild(tipEl);
  let tipFor = null;
  const showTip = (el) => {
    tipFor = el; tipEl.textContent = el.dataset.tip;
    const r = el.getBoundingClientRect();
    tipEl.classList.add('on');
    const w = tipEl.offsetWidth, h = tipEl.offsetHeight;
    const x = Math.max(8, Math.min(innerWidth - w - 8, r.left + r.width / 2 - w / 2));
    const y = r.top - h - 8 < 8 ? r.bottom + 8 : r.top - h - 8;
    tipEl.style.translate = `${Math.round(x)}px ${Math.round(y)}px`;
  };
  const hideTip = () => { tipFor = null; tipEl.classList.remove('on'); };
  document.addEventListener('pointerover', (e) => { const el = e.target.closest && e.target.closest('[data-tip]'); if (el && el !== tipFor) showTip(el); else if (!el && tipFor) hideTip(); }, { passive: true });
  document.addEventListener('scroll', hideTip, { capture: true, passive: true });

  // ───────────────────────── View: Home ─────────────────────────
  // One glance: who you are, what the autopilot is doing, and only what needs you.
  const firstName = () => String((S.profile && S.profile.full_name) || '').trim().split(/\s+/)[0] || '';
  function greeting() {
    const h = new Date().getHours();
    const part = h < 5 ? 'Working late' : h < 12 ? 'Good morning' : h < 17 ? 'Good afternoon' : h < 22 ? 'Good evening' : 'Good night';
    return firstName() ? `${part}, ${firstName()}` : part;
  }
  const relFuture = (iso) => {
    const d = toDate(iso); if (!d) return '';
    const m = Math.round((d - Date.now()) / 60000);
    if (m <= 0) return 'any moment';
    if (m < 60) return `in ${m} min`;
    const h = Math.round(m / 60);
    return h < 24 ? `in ${h} h` : `in ${Math.round(h / 24)} d`;
  };
  function engineStatus() {
    const st = S.stats || {}, ap = S.autopilot || {}, live = !!st.go_live;
    const key = st.is_circuit_broken ? 'circuit_broken' : (ap.status || (st.is_paused ? 'paused' : 'running'));
    const capPause = st.pause_reason === 'paused_by_daily_cap';
    return ({
      running: { label: 'Running', dot: 'teal', line: `Applying for you automatically in ${live ? 'live' : 'dry run'} mode.` },
      sleeping: { label: 'Resting', dot: 'slate', line: 'Outside your active hours. It picks up again on its own.' },
      paused: { label: 'Paused', dot: 'amber', line: capPause ? 'Today’s limit is reached. It resumes tomorrow on its own.' : 'Paused. Resume whenever you’re ready.' },
      circuit_broken: { label: 'Stopped for safety', dot: 'coral', line: 'Several job sites failed in a row, so it paused itself.' },
      off: { label: 'Off', dot: 'slate', line: 'Autopilot is switched off in Settings.' },
      no_profile: { label: 'Setting up', dot: 'slate', line: 'Finish your profile to start.' },
    })[key] || { label: 'Running', dot: 'teal', line: 'Applying for you automatically.' };
  }
  function followUpsDue() {
    const now = Date.now();
    return (S.jobs || []).filter(j => j.follow_up_date && toDate(j.follow_up_date) <= now && !['rejected', 'dismissed', 'skipped', 'offer'].includes(j.status));
  }
  function attentionItems() {
    const st = S.stats || {}, items = [];
    const n = st.needs_you_count || 0, drafts = S.aiAnswers.length, tri = st.maybe_count || 0, fu = followUpsDue().length;
    if (S.resume && !S.resume.uploaded) items.push(['upload_file', 'Add your resume', 'It’s used for every application', 'settings/resume']);
    if (n) items.push(['help', `${n} question${n > 1 ? 's' : ''} to answer`, 'Applications are waiting on you', 'inbox/questions']);
    if (drafts) items.push(['auto_awesome', `${drafts} AI answer${drafts > 1 ? 's' : ''} to review`, 'Approve once, reused forever', 'inbox/ai']);
    if (fu) items.push(['schedule', `${fu} follow-up${fu > 1 ? 's' : ''} due`, 'Roles you planned to chase up', 'pipeline']);
    if (tri) items.push(['swipe', `${tri} role${tri > 1 ? 's' : ''} to triage`, 'Borderline fits — quick yes or no', 'inbox/triage']);
    const assist = (S.autopilot && S.autopilot.assist_queued) || 0;
    if (assist) items.push(['touch_app', `${assist} role${assist > 1 ? 's' : ''} to apply yourself`, 'LinkedIn, Indeed and similar sites don’t allow bots', 'pipeline']);
    if (S.proofStatus && !S.proofStatus.connected) items.push(['mail', 'Connect your email', 'Employer confirmations become proof', 'settings/email']);
    return items;
  }
  const CHECK_KEY = 'ap_checklist_hidden';
  function checklist() {
    let hidden = false; try { hidden = localStorage.getItem(CHECK_KEY) === '1'; } catch (e) {}
    const st = S.stats || {}, ap = (S.autopilot && S.autopilot.config) || {};
    const steps = [
      ['Upload your resume', !!(S.resume && S.resume.uploaded), 'settings/resume'],
      ['Check your job preferences', !!(S.profile && (S.profile.target_roles || []).length && (S.profile.locations || []).length), 'settings/preferences'],
      ['Connect your email for proof', !!(S.proofStatus && S.proofStatus.connected), 'settings/email'],
      ['Keep autopilot on', ap.enabled !== false, 'settings/autopilot'],
      ['Turn on live submissions', !!st.go_live, 'settings/autopilot'],
    ];
    const done = steps.filter(s => s[1]).length;
    if (hidden || done === steps.length) return '';
    return `<section class="card block checklist-card">
      <div class="card-h"><span class="card-t">Getting started</span><span class="aside tnum">${done} of ${steps.length}</span>
        <button class="btn sm icon ghost hv" data-act="hide-checklist" title="Hide checklist">${icon('close')}</button></div>
      <div class="bar thin mx"><i style="width:${done / steps.length * 100}%"></i></div>
      <div class="list">${steps.map(([label, ok, to]) => `<button class="row hv ${ok ? 'done' : ''}" data-nav="${to}">
        ${icon(ok ? 'check_circle' : 'radio_button_unchecked', ok ? 'fill step-ok' : 'step-todo')}<span class="grow">${label}</span>${ok ? '' : icon('chevron_right', 'faint')}</button>`).join('')}</div></section>`;
  }
  function topShelf(limit = 10) {
    const top = ((S.analytics && S.analytics.top_matches) || []).slice(0, limit);
    if (!top.length) return '';
    return `<section class="block"><h2 class="section-t">Top matches <button class="btn sm ghost hv ml-auto" data-nav="pipeline">See all ${icon('chevron_right')}</button></h2>
      <div class="shelf">${top.map(m => `<button class="tile" data-job="${m.id}" aria-label="${esc(m.title)} at ${esc(m.company)}">
        <span class="art" style="--h:${hue(m.company)}">${esc(initials(m.company))}${m.match_percent ? `<span class="badge">${m.match_percent}%</span>` : ''}<span class="open">${icon('arrow_outward')}</span></span>
        <span class="tile-t">${esc(m.title)}</span><span class="tile-s"><span class="ellipsis">${esc(m.company)}</span>${scoreTag(m.score)}</span></button>`).join('')}</div></section>`;
  }
  const PROOF_KIND = { confirmation: ['Confirmed', 'teal'], interview: ['Interview', 'violet'], rejection: ['Declined', 'slate'] };
  const proofRow = (p) => `<button class="row hv" data-proof="${p.id}">
    ${art(p.company, 'sm')}<span class="grow"><span class="main-t">${esc(p.subject || p.company)}</span><span class="sub-t">${esc(p.company)}${p.role ? ' · ' + esc(p.role) : ''}</span></span>
    <span class="end"><span class="chip ${PROOF_KIND[p.kind] ? PROOF_KIND[p.kind][1] : ''}">${PROOF_KIND[p.kind] ? PROOF_KIND[p.kind][0] : esc(p.kind)}</span><span class="faint small tnum">${rel(p.received_at)}</span></span></button>`;

  renderers.home = () => {
    const st = S.stats || {}, ap = S.autopilot || {}, ps = S.proofStatus || {};
    const es = engineStatus(), items = attentionItems();
    const applied = st.daily_applied || 0, cap = st.daily_cap || 0;
    const confirmations = (ps.counts && ps.counts.confirmation) || 0;
    const summary = items.length
      ? `${es.line} ${items.length === 1 ? 'One thing needs you.' : `${items.length} things need you.`}`
      : `${es.line} Nothing needs you right now.`;
    const paused = !!st.is_paused;
    const next = ap.status === 'running' && ap.queued ? relFuture(ap.next_apply_at) || 'soon' : '—';
    const metric = (value, label, extra = '') => `<div class="hm"><span class="hm-v tnum">${value}${extra}</span><span class="hm-l">${label}</span></div>`;
    const hero = `<section class="card status-card block">
      <div class="sc-top">
        <span class="sc-state"><span class="dot ${es.dot} ${es.dot === 'teal' ? 'pulse' : ''}"></span>Autopilot · ${esc(es.label)}</span>
        <span class="chip">${st.go_live ? 'Live' : 'Dry run'}</span>
        <button class="btn sm hv ml-auto" data-act="${paused ? 'resume' : 'pause'}">${icon(paused ? 'play_arrow' : 'pause')}${paused ? 'Resume' : 'Pause'}</button>
      </div>
      <div class="sc-metrics">
        ${metric(fmt(applied), 'Applied today', `<span class="hm-of"> / ${fmt(cap)}</span>`)}
        ${metric(fmt(ap.queued ?? st.queue_count ?? 0), 'Waiting in queue')}
        ${metric(fmt(confirmations), 'Confirmed by email')}
        ${metric(esc(next), 'Next application')}
      </div>
      <div class="bar thin"><i style="width:${cap ? Math.min(100, applied / cap * 100) : 0}%"></i></div>
    </section>`;
    const forYou = `<section class="block"><h2 class="section-t">For you</h2><div class="card list">${items.length
      ? items.map(([ic, t, d, to]) => `<button class="row hv" data-nav="${to}"><span class="row-ic">${icon(ic)}</span><span class="grow"><span class="main-t">${t}</span><span class="sub-t">${d}</span></span>${icon('chevron_right', 'faint')}</button>`).join('')
      : `<div class="row calm">${icon('check_circle', 'fill step-ok')}<span class="grow"><span class="main-t">You’re all caught up</span><span class="sub-t">ApplyPilot will let you know when something needs you.</span></span></div>`}</div></section>`;
    const recent = (S.proofs || []).slice(0, 3);
    const recentHtml = recent.length ? `<section class="block"><h2 class="section-t">Latest from employers <button class="btn sm ghost hv ml-auto" data-nav="proof">All proof ${icon('chevron_right')}</button></h2>
      <div class="card list">${recent.map(proofRow).join('')}</div></section>` : '';
    return `<header class="view-head greet"><div class="min0"><div class="eyebrow">${esc(today())}</div><h1>${esc(greeting())}</h1><p class="sub">${esc(summary)}</p></div>
      <button class="greet-me" data-nav="settings/profile" title="Your profile">${me('lg')}</button></header>
      ${hero}${checklist()}${forYou}${dashboard()}${recentHtml}${topShelf(8)}`;
  };

  // ───────────────────────── View: Proof ─────────────────────────
  function emailConnectForm(compact = false) {
    return `<form class="stack" data-email-form>
      ${compact ? '' : `<p class="muted small">ApplyPilot reads your inbox <b>read-only</b> to find “thank you for applying”, interview and decision emails, and links them to the right application. It never sends, deletes or marks mail as read.</p>`}
      <div class="form-grid">
        <div class="field"><label for="em-addr">Gmail address</label><input class="input" id="em-addr" name="address" type="email" autocomplete="username" placeholder="you@gmail.com" value="${esc((S.proofStatus && S.proofStatus.address) || '')}" required></div>
        <div class="field"><label for="em-pass">Google app password</label><input class="input" id="em-pass" name="app_password" type="password" autocomplete="new-password" placeholder="16 characters" required></div>
      </div>
      <div class="row-between wrap"><button type="button" class="btn ghost sm hv" data-nav="settings/help" data-tut="email">${icon('help')}How do I get an app password?</button><button class="btn primary hv" type="submit">${icon('link')}Connect</button></div>
    </form>`;
  }
  renderers.proof = () => {
    const ps = S.proofStatus || {}, c = ps.counts || {}, st = S.stats || {}, kind = S.proof.kind;
    const list = (S.proofs || []).filter(p => kind === 'all' || p.kind === kind);
    const head = pageHead(ps.connected ? `<button class="btn hv" data-act="proof-sync">${icon('refresh')}Check inbox</button>` : '');
    if (!ps.connected) {
      return `${head}<section class="card block"><div class="card-h"><span class="card-t">Connect your inbox</span></div><div class="card-b">${emailConnectForm()}</div></section>
        <section class="card"><div class="empty">${icon('mark_email_unread')}<b>Proof appears here</b><span>Once connected, every confirmation an employer sends is matched to its application.</span></div></section>`;
    }
    const metric = (v, l) => `<div class="hm"><span class="hm-v tnum">${fmt(v)}</span><span class="hm-l">${l}</span></div>`;
    const seg = `<div class="seg" data-glide="proof">${[['all', 'All', ps.total || 0], ['confirmation', 'Confirmed', c.confirmation || 0], ['interview', 'Interviews', c.interview || 0], ['rejection', 'Declined', c.rejection || 0]]
      .map(([id, l, n]) => `<button class="${kind === id ? 'on' : ''}" data-proof-kind="${id}">${l} <span class="n">${n}</span></button>`).join('')}</div>`;
    return `${head}
      <section class="card status-card block"><div class="sc-metrics">
        ${metric(st.total_submitted_real || 0, 'Submitted live')}${metric(c.confirmation || 0, 'Confirmed by email')}${metric(c.interview || 0, 'Interview invites')}
        <div class="hm"><span class="hm-v small-v">${ps.last_sync ? esc(rel(ps.last_sync)) : 'Not yet'}</span><span class="hm-l">Last checked · ${esc(ps.address || '')}</span></div>
      </div>${ps.last_error ? `<p class="small bad mt-2">${icon('error')} ${esc(ps.last_error)}</p>` : ''}</section>
      <div class="toolbar">${seg}<div class="spacer"></div><span class="hint">Checked automatically every ${fmt(((S.autopilot && S.autopilot.config) || {}).proof_sync_minutes || 20)} min</span></div>
      ${list.length ? `<div class="card list">${list.map(proofRow).join('')}</div>`
        : emptyCard('mark_email_unread', 'No employer emails yet', 'Dry runs don’t send anything, so confirmations arrive only after live applications — usually within minutes.')}`;
  };

  // ───────────────────────── View: Insights ─────────────────────────
  renderers.insights = () => {
    const tab = S.ins.tab === 'log' ? 'log' : 'overview';
    const seg = `<div class="seg" data-glide="ins"><button class="${tab === 'overview' ? 'on' : ''}" data-ins-tab="overview">${icon('insights')}Overview</button><button class="${tab === 'log' ? 'on' : ''}" data-ins-tab="log">${icon('receipt_long')}Activity log</button></div>`;
    return `${pageHead()}<div class="toolbar">${seg}</div>${tab === 'log' ? activityLog() : insightsOverview()}`;
  };
  afterRender.insights = () => { if (S.ins.tab === 'log') afterRender.activity(); };
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
    const chips = `<div class="chips-scroll" role="group" aria-label="Stage"><button class="filter-chip ${P.stage === 'all' ? 'on' : ''}" data-stage-f="all" aria-pressed="${P.stage === 'all'}">All <span class="n">${fmt(jobs.length)}</span></button>${STAGES.map(s => `<button class="filter-chip ${P.stage === s.id ? 'on' : ''}" style="--tone: var(--${s.color})" data-stage-f="${s.id}" aria-pressed="${P.stage === s.id}"><span class="dot ${s.color}"></span>${s.label} <span class="n">${fmt(counts[s.id] || 0)}</span></button>`).join('')}</div>`;
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
    const rerender = () => { $('#pipe-body').innerHTML = S.pipe.mode === 'table' ? pipeTable() : pipeBoard(); enhance($('#pipe-body')); hscroll(); };
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
          <div class="form-grid">
            <div class="field"><label for="insp-contact">Recruiter / contact</label><input class="input" id="insp-contact" placeholder="Name, email or LinkedIn" value="${esc(j.recruiter_info || '')}"></div>
            <div class="field"><label for="insp-follow">Follow up on</label><input class="input" id="insp-follow" type="date" value="${j.follow_up_date ? esc(String(j.follow_up_date).slice(0, 10)) : ''}"></div>
          </div>
          <div class="field"><label for="insp-notes">Notes</label><textarea class="textarea short" id="insp-notes" placeholder="Referral, salary discussion, anything to remember…">${esc(j.notes)}</textarea></div>
          <div class="qactions"><button class="btn sm hv" data-act="save-status" data-id="${j.id}">${icon('save')}Save</button>
            <button class="btn sm hv" data-act="cover-letter" data-id="${j.id}">${icon('edit_note')}Cover letter</button>
            <button class="btn sm hv" data-act="interview-prep" data-id="${j.id}">${icon('record_voice_over')}Interview prep</button>
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

  function answersBody() {
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
    return `<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="ans-q" aria-label="Search answers" placeholder="Search questions or answers" value="${esc(A.q)}"></div>
      <div class="spacer"></div><span class="hint tnum">${fmt(all.length)} saved · ${fmt(all.reduce((s, a) => s + (a.usage_count || 0), 0))} auto-fills</span>
      <button class="btn primary hv" data-act="ans-add">${icon('add')}New answer</button></div>
      <div class="ans-layout"><nav class="cat-list" aria-label="Categories">${catBtn('all', 'All', all.length)}${cats.map(c => catBtn(c, catName(c), counts[c])).join('')}</nav>
      <div id="ans-body">${addForm}${body}</div></div>`;
  }
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
  function activityLog() {
    const A = S.act, q = A.q.trim().toLowerCase();
    const norm = (l) => l === 'warning' ? 'warn' : l;
    const counts = { all: S.logs.length }; S.logs.forEach(l => { const k = norm(l.level); counts[k] = (counts[k] || 0) + 1; });
    const list = S.logs.filter(l => (A.level === 'all' || norm(l.level) === A.level) && (!q || `${l.message} ${l.event_type} ${l.company}`.toLowerCase().includes(q)));
    const rows = list.map(l => `<tr><td class="faint tnum mono">${esc(l.created_at)}</td><td><span class="lvl ${esc(l.level)}">${esc(l.level)}</span></td>
      <td class="hide-m"><span class="chip">${esc(l.event_type)}</span></td><td class="msg"><span class="dot ${logColor(l)}"></span> ${esc(l.message)}</td></tr>`).join('');
    return `<div class="toolbar"><div class="search">${icon('search')}<input class="input" id="act-q" aria-label="Filter log" placeholder="Filter log" value="${esc(A.q)}"></div>
      <div class="seg" data-glide="level">${['all', 'info', 'warn', 'error'].map(l => `<button class="${A.level === l ? 'on' : ''}" data-level="${l}" aria-pressed="${A.level === l}">${l[0].toUpperCase() + l.slice(1)} <span class="n">${counts[l] || 0}</span></button>`).join('')}</div>
      <div class="spacer"></div><span class="live-ind"><span class="dot teal pulse"></span>Live</span>
      <button class="btn hv" data-act="backup">${icon('backup')}Back up now</button></div>
      <div class="card"><div class="table-wrap"><table class="tbl log-tbl"><thead><tr><th class="w-time">Time</th><th class="w-lvl">Level</th><th class="hide-m w-ev">Event</th><th>Message</th></tr></thead>
      <tbody>${rows || `<tr><td colspan="4"><div class="empty">No log entries</div></td></tr>`}</tbody></table></div></div>`;
  }
  afterRender.activity = () => {
    const q = $('#act-q');
    q && q.addEventListener('input', debounce(e => { S.act.q = e.target.value; const pos = e.target.selectionStart; render(); const n = $('#act-q'); n.focus(); n.setSelectionRange(pos, pos); }, 150));
  };

  // ───────────────────────── View: Profile & rules ─────────────────────────
  // ───────────────────────── Appearance: text size, font, motion ─────────────────────────
  // Saved per device (localStorage) and applied before first paint by index.html, like the theme.
  const FONT_KEY = 'ap_font';
  const FONT_STYLES = [
    { id: 'default', name: 'System', note: 'SF Pro / Inter' },
    { id: 'modern', name: 'Modern', note: 'Plus Jakarta Sans', href: 'Plus+Jakarta+Sans:wght@400;500;600;700' },
    { id: 'elegant', name: 'Elegant', note: 'Fraunces headings', href: 'Fraunces:opsz,wght@9..144,400..700' },
    { id: 'rounded', name: 'Rounded', note: 'Soft and friendly', href: 'Nunito:wght@400;500;600;700' },
    { id: 'serif', name: 'Serif', note: 'Editorial', href: 'Newsreader:opsz,wght@6..72,400..700' },
    { id: 'readable', name: 'Readable', note: 'Atkinson Hyperlegible', href: 'Atkinson+Hyperlegible:wght@400;700' },
    { id: 'mono', name: 'Mono', note: 'Technical', href: 'JetBrains+Mono:wght@400;500;600;700' },
  ];
  const FONT_SIZES = [['s', 'Small', 0.9], ['m', 'Default', 1], ['l', 'Large', 1.12], ['xl', 'Extra large', 1.25]];
  function fontPrefs() {
    const base = { size: 'm', style: 'default', motion: 'auto' };
    try { return { ...base, ...(JSON.parse(localStorage.getItem(FONT_KEY) || '{}') || {}) }; } catch (e) { return base; }
  }
  function applyFont(p = fontPrefs()) {
    const root = document.documentElement, size = FONT_SIZES.find(x => x[0] === p.size) || FONT_SIZES[1];
    root.style.setProperty('--text-scale', size[2]);
    root.dataset.font = p.style; root.dataset.motion = p.motion;
    const st = FONT_STYLES.find(f => f.id === p.style);
    if (st && st.href && !document.getElementById(`font-${st.id}`)) {
      document.head.insertAdjacentHTML('beforeend', `<link id="font-${st.id}" rel="stylesheet" href="https://fonts.googleapis.com/css2?family=${st.href}&display=swap">`);
    }
  }
  function setFont(patch) {
    const p = { ...fontPrefs(), ...patch };
    try { localStorage.setItem(FONT_KEY, JSON.stringify(p)); } catch (e) {}
    // Re-render inside the same step as the size change, so sliding pills measure the new layout
    const swap = () => { applyFont(p); S.lastHtml = ''; render(); };
    if (document.startViewTransition && p.motion !== 'reduce') document.startViewTransition(swap); else swap();
  }
  function appearancePanel(standalone = false) {
    const fp = fontPrefs();
    let open = true; try { open = standalone || localStorage.getItem('ap_appearance_open') !== '0'; } catch (e) {}
    return `<details class="card collapse" data-collapse="appearance" ${open ? 'open' : ''}>
      <summary class="card-h"><span class="card-t">Appearance</span><span class="aside">Theme, text size and font</span>${icon('expand_more', 'chev')}</summary>
      <div class="card-b stack">
        <div><div class="eyebrow mb-2">Theme</div>${themeSwatches()}</div>
        <div><div class="eyebrow mb-2">Text size</div>
          <div class="seg wide" data-glide="size" role="radiogroup" aria-label="Text size">${FONT_SIZES.map(([id, label]) => `<button role="radio" aria-checked="${fp.size === id}" class="${fp.size === id ? 'on' : ''}" data-font-size="${id}"><span class="size-a size-${id}" aria-hidden="true">A</span>${label}</button>`).join('')}</div></div>
        <div><div class="eyebrow mb-2">Font</div>
          <div class="font-grid" role="radiogroup" aria-label="Font">${FONT_STYLES.map(f => `<button class="font-opt hv ${fp.style === f.id ? 'on' : ''}" role="radio" aria-checked="${fp.style === f.id}" data-font-style="${f.id}"><span class="font-aa" data-font="${f.id}">Aa</span><span class="strong">${f.name}</span><span class="faint small">${f.note}</span></button>`).join('')}</div></div>
        <label class="set-row hv bordered"><span class="grow">Reduce motion<small>Turns off sliding, lifting and drifting effects</small></span>
          <span class="toggle"><input type="checkbox" data-reduce-motion ${fp.motion === 'reduce' ? 'checked' : ''}><i></i></span></label>
      </div></details>`;
  }

  // ───────────────────────── Help & tutorials ─────────────────────────
  const TUTORIALS = [
    { id: 'start', icon: 'rocket_launch', title: 'Getting started in five minutes', to: ['Open Resume', 'settings/resume'], steps: [
      'Upload your resume in Settings › Resume. Each new upload replaces the old one.',
      'Check Settings › Job preferences: roles, locations, minimum pay and companies to avoid.',
      'Connect your email in Settings › Email proof so employer confirmations are tracked.',
      'Review Settings › Autopilot: limits, active hours and the fit scores it uses.',
      'Watch a few dry runs, then turn on Live submissions.'] },
    { id: 'autopilot', icon: 'smart_toy', title: 'How autopilot works', to: ['Open Autopilot', 'settings/autopilot'], steps: [
      'Every few hours it finds new roles on Greenhouse, Lever and Ashby boards and scores each one against your profile (0–5).',
      'Roles at or above your auto-queue score are queued. Borderline ones go to Needs you › Triage.',
      'It applies to the best queued role, spaced out to respect your hourly limit, stops at the daily limit and resumes the next day on its own.',
      'Dry run fills the form and saves a screenshot without submitting. Live submits for real.',
      'LinkedIn, Indeed, Naukri and Workday forbid bots, so those stay assist-only: ApplyPilot prepares everything and you press submit.'] },
    { id: 'needs', icon: 'inbox', title: 'Answering questions', to: ['Open Needs you', 'inbox'], steps: [
      'When a form asks something your Answer bank doesn’t know, that application waits in Needs you.',
      'Answer once and keep “Remember” on — it’s reused automatically from then on.',
      'AI drafts are answers Gemini wrote from your verified facts. Approve or edit them.',
      'Sensitive questions (visa, salary, legal, identity) always come to you.'] },
    { id: 'ai', icon: 'auto_awesome', title: 'AI: your own Gemini key or the free model', to: ['Open AI settings', 'settings/ai'], steps: [
      'ApplyPilot uses AI to answer form questions, fix form errors, write cover letters, prep interviews and power the assistant.',
      'Best: paste your own free Gemini key (Settings › AI answers › Gemini API key). Get one at aistudio.google.com/apikey.',
      'No key, or out of quota? The free model takes over automatically. Install Ollama (free) from ollama.com, then press Download model — the right size for your computer is picked for you.',
      'Want everything private? Set “When to use it” to Always: nothing leaves your computer.',
      'Computer too slow for a local model? Use a free cloud model (Groq or OpenRouter) with a free key.'] },
    { id: 'email', icon: 'mail', title: 'Email proof and your Gmail app password', to: ['Open Email proof', 'settings/email'], steps: [
      'Turn on 2-Step Verification for your Google account (app passwords need it).',
      'Visit myaccount.google.com/apppasswords, create one called “ApplyPilot” and copy the 16 characters.',
      'Paste it with your Gmail address in Settings › Email proof and press Connect.',
      'ApplyPilot checks your inbox read-only every 20 minutes and links confirmations, interview invites and decisions to the right application.',
      'Disconnect any time here, and revoke the app password from your Google account.'] },
    { id: 'apply', icon: 'description', title: 'Cover letters, interview prep and follow-ups', to: ['Open Applications', 'pipeline'], steps: [
      'Open any role in Applications to see why it fits, its timeline and actions.',
      '“Cover letter” writes a short letter from your verified facts — copy and edit as you like.',
      '“Interview prep” gives likely technical and behavioural questions with answer outlines.',
      'Set a follow-up date and a recruiter contact; due follow-ups show up on Home.',
      'Export everything to a spreadsheet from Settings › Data & privacy.'] },
    { id: 'look', icon: 'palette', title: 'Themes, text size and shortcuts', to: ['Open Appearance', 'settings/profile'], steps: [
      'Settings › Profile › Appearance: choose a theme, text size and font. The section folds away when you don’t need it.',
      'Press Ctrl+K (or /) to search jobs and run any command.',
      'Press 1–6 to jump between sections and Esc to close panels.'] },
    { id: 'phone', icon: 'smartphone', title: 'Using the phone app', steps: [
      'Install the APK and keep Tailscale on, on both your PC and phone.',
      'Enter your PC’s Tailscale address and token once — the app remembers them.',
      'Everything here works on the phone, and the bars follow your theme.'] },
    { id: 'safety', icon: 'shield', title: 'Safety rails', steps: [
      'Live submissions stay off until you turn them on.',
      'Daily and hourly limits, a 30-day cooldown per company and an automatic stop after repeated site failures.',
      'Answers are grounded only in your verified facts; nothing is made up.'] },
  ];
  function helpPanel() {
    const openId = S.helpOpen;
    return `<section class="card block"><div class="card-b row-between wrap">
        <div><div class="card-t">New here?</div><div class="muted small">A one-minute tour of how ApplyPilot works.</div></div>
        <button class="btn primary hv" data-act="tour">${icon('play_circle')}Replay the welcome tour</button></div></section>
      <div class="stack">${TUTORIALS.map(t => `<details class="card collapse" data-tut-id="${t.id}" ${openId === t.id ? 'open' : ''}>
        <summary class="card-h"><span class="row-ic">${icon(t.icon)}</span><span class="card-t">${t.title}</span>${icon('expand_more', 'chev ml-auto')}</summary>
        <div class="card-b"><ol class="steps">${t.steps.map(s => `<li>${esc(s)}</li>`).join('')}</ol>
          ${t.to ? `<div class="row-end mt-3"><button class="btn sm hv" data-nav="${t.to[1]}">${t.to[0]} ${icon('chevron_right')}</button></div>` : ''}</div></details>`).join('')}</div>`;
  }

  // ───────────────────────── View: Settings ─────────────────────────
  const SETTINGS_SECTIONS = [
    ['profile', 'person', 'Profile'], ['appearance', 'palette', 'Appearance'], ['resume', 'description', 'Resume'], ['facts', 'school', 'Your background'], ['preferences', 'tune', 'Job preferences'],
    ['autopilot', 'smart_toy', 'Autopilot'], ['email', 'mail', 'Email proof'], ['ai', 'auto_awesome', 'AI answers'],
    ['answers', 'forum', 'Answer bank'], ['help', 'help', 'Help & tutorials'], ['data', 'shield_lock', 'Data & privacy'],
  ];
  renderers.settings = () => {
    const p = S.profile; if (!p) return `${pageHead()}${emptyCard('person_off', 'Profile not available')}`;
    const sec = SETTINGS_SECTIONS.some(s => s[0] === S.set.section) ? S.set.section : 'profile';
    const nav = `<nav class="set-nav" aria-label="Settings sections">${SETTINGS_SECTIONS.map(([id, ic, label]) =>
      `<button class="set-link hv ${sec === id ? 'on' : ''}" data-section="${id}" ${sec === id ? 'aria-current="page"' : ''}>${icon(ic)}<span>${label}</span></button>`).join('')}</nav>`;
    return `${pageHead()}<div class="settings-shell">${nav}<div class="set-panel" id="set-panel">${settingsPanel(sec)}</div></div>`;
  };

  // ── Your background: the verified facts every form answer, resume and AI reply is built from ──
  const projRow = (pr = {}) => `<div class="proj-row">
      <div class="field"><label>Project</label><input class="input" data-proj="name" value="${esc(pr.name || '')}" placeholder="Project name"></div>
      <div class="field"><label>What it does / results</label><textarea class="textarea short" data-proj="description" placeholder="One or two sentences with real numbers">${esc(pr.description || '')}</textarea></div>
      <button type="button" class="btn sm ghost hv" data-act="proj-del" aria-label="Remove project">${icon('delete')}Remove</button></div>`;
  function factsEditor() {
    const f = S.facts || {}, p = f.personal || {}, e = f.education || {};
    const txt = (sec, k, label, attrs = '') => `<div class="field"><label for="ff-${sec}-${k}">${label}</label><input class="input" id="ff-${sec}-${k}" data-sec="${sec}" name="${k}" value="${esc((sec === 'personal' ? p : e)[k] || '')}" ${attrs}></div>`;
    const one = (k, label, hint) => `<div class="field full"><label for="ff-${k}">${label}</label><input class="input" id="ff-${k}" name="${k}" value="${esc(f[k] || '')}" placeholder="${hint || ''}"></div>`;
    const list = (k, label, hint, sep = '\n') => `<div class="field full"><label for="ff-${k}">${label}<small class="faint"> · ${hint}</small></label><textarea class="textarea" id="ff-${k}" name="${k}" data-sep="${sep === '\n' ? 'line' : 'comma'}">${esc((f[k] || []).join(sep === '\n' ? '\n' : ', '))}</textarea></div>`;
    return `<form class="stack" data-facts-form>
      <p class="muted small">This is the only source ApplyPilot uses for anything it says about you — form answers, tailored resumes, cover letters and the assistant. It stays on your PC. Change anything, any time; your previous version is backed up automatically.</p>
      <section class="card"><div class="card-h"><span class="card-t">About you</span><span class="aside">Used on application forms</span></div>
        <div class="card-b form-grid">${txt('personal', 'name', 'Full name', 'autocomplete="name"')}${txt('personal', 'email', 'Email', 'type="email" autocomplete="email"')}
          ${txt('personal', 'phone', 'Phone', 'type="tel" autocomplete="tel"')}${txt('personal', 'location', 'Current location', 'placeholder="City, Country"')}
          ${txt('personal', 'linkedin', 'LinkedIn URL', 'type="url"')}${txt('personal', 'github', 'GitHub / portfolio URL', 'type="url"')}</div></section>
      <section class="card"><div class="card-h"><span class="card-t">Education</span></div>
        <div class="card-b form-grid">${txt('education', 'degree', 'Degree')}${txt('education', 'institution', 'Institution (short)')}
          ${txt('education', 'institution_full', 'Institution (full name)')}${txt('education', 'cgpa', 'CGPA / grade')}
          ${txt('education', 'start_date', 'Started')}${txt('education', 'expected_graduation', 'Graduation (expected)')}</div></section>
      <section class="card"><div class="card-h"><span class="card-t">Projects</span><button type="button" class="btn sm hv ml-auto" data-act="proj-add">${icon('add')}Add project</button></div>
        <div class="card-b stack" id="proj-list">${(f.projects || []).map(projRow).join('') || projRow()}</div></section>
      <section class="card"><div class="card-h"><span class="card-t">Achievements & skills</span></div>
        <div class="card-b form-grid">${list('patents', 'Patents / publications', 'one per line')}${list('certifications', 'Certifications', 'one per line')}${list('skills', 'Skills', 'separate with commas', ',')}</div></section>
      <section class="card"><div class="card-h"><span class="card-t">Work details</span><span class="aside">Answers to common screening questions</span></div>
        <div class="card-b form-grid">${one('work_authorization', 'Work authorisation', 'e.g. Indian citizen, no sponsorship needed')}${one('notice_period', 'Notice period / earliest start', 'e.g. Immediately')}${one('relocation_preference', 'Open to relocation?', 'e.g. Yes, anywhere in India')}</div></section>
      <div class="row-end sticky-save"><button class="btn primary hv" type="submit">${icon('check')}Save background</button></div>
    </form>`;
  }

  // ── Gemini key: everyone uses their own (free from Google AI Studio); the PC's .env key is only a fallback ──

  // ── Free AI: an open model on this computer (sized for its hardware), or a free cloud model ──
  const CLOUD_PRESETS = [
    ['', 'Choose a free provider…', ''],
    ['https://api.groq.com/openai/v1', 'Groq (free tier)', 'llama-3.1-8b-instant'],
    ['https://openrouter.ai/api/v1', 'OpenRouter (free models)', 'qwen/qwen3-8b:free'],
  ];
  function freeAICard() {
    const L = S.localAI || {}, hw = L.hardware || {}, pull = L.pull || {}, cloud = L.cloud || {};
    const size = (tag) => ((L.choices || []).find(c => c.tag === tag) || {}).size || '';
    const state = L.ready ? ['teal', `Ready · ${esc(L.model)}`] : L.installed ? ['amber', 'Model not downloaded yet'] : cloud.ready ? ['teal', 'Using the free cloud model'] : ['slate', 'Not set up'];
    const pulling = pull.status === 'pulling';
    const pct = pull.total ? Math.round(pull.done / pull.total * 100) : 0;
    const hwLine = `This computer: ${hw.ram_gb || '?'} GB memory${hw.gpu ? ` · ${esc(hw.gpu)} (${hw.gpu_gb} GB)` : ' · no graphics card found'}`;
    const setup = !L.installed
      ? `<ol class="steps small"><li>Install <b>Ollama</b> — free, from <a href="https://ollama.com/download" target="_blank" rel="noopener">ollama.com/download</a>.</li><li>Come back here and press <b>Download model</b>. The right size for this computer is chosen for you.</li></ol>
         <div class="row-end"><button type="button" class="btn sm hv" data-act="local-ai-refresh">${icon('refresh')}I've installed it</button></div>`
      : !L.ready ? `${pulling ? `<div class="pull"><div class="bar thin"><i style="width:${pct}%"></i></div><span class="small faint tnum">Downloading ${esc(pull.model || '')} · ${pct}%</span></div>`
          : pull.status === 'error' ? `<p class="small bad">${esc(pull.error)}</p>` : ''}
         <div class="row-end"><button type="button" class="btn primary hv" data-act="local-ai-pull" ${pulling ? 'disabled' : ''}>${icon('download')}Download ${esc(L.model || 'model')} · ${esc(size(L.model))}</button></div>` : '';
    return `<form class="card" data-local-ai-form><div class="card-h"><span class="card-t">Free AI · no key needed</span><span class="aside"><span class="dot ${state[0]}"></span>${state[1]}</span></div>
      <div class="card-b stack">
        <p class="muted small">An open model (Qwen3.5) runs on the computer that runs ApplyPilot — free, unlimited and private. It takes over whenever Gemini has no key, runs out of quota or is down. Phones use it through this computer.</p>
        <div class="form-grid">
          <div class="field"><label for="la-mode">When to use it</label><select class="select" id="la-mode" name="mode">
            ${[['auto', 'Automatically when Gemini is unavailable'], ['local', 'Always (private — nothing leaves this computer)'], ['gemini', 'Never (Gemini only)']].map(([v, l]) => `<option value="${v}" ${L.mode === v ? 'selected' : ''}>${l}</option>`).join('')}</select></div>
          <div class="field"><label for="la-model">Model</label><select class="select" id="la-model" name="model">
            <option value="auto" ${(L.model_setting || 'auto') === 'auto' ? 'selected' : ''}>Best for this computer (${esc(L.recommended || '')})</option>
            ${(L.choices || []).map(c => `<option value="${esc(c.tag)}" ${L.model_setting === c.tag ? 'selected' : ''}>${esc(c.tag)} · ${esc(c.size)}</option>`).join('')}</select></div>
        </div>
        <span class="faint small">${hwLine}</span>
        ${setup}
        <details class="collapse plain"><summary class="small muted">Computer too slow for a local model? Use a free cloud model ${icon('expand_more', 'chev')}</summary>
          <div class="form-grid mt-3">
            <div class="field"><label for="la-preset">Provider</label><select class="select" id="la-preset" data-cloud-preset>${CLOUD_PRESETS.map(([u, l]) => `<option value="${esc(u)}" ${cloud.url === u && u ? 'selected' : ''}>${esc(l)}</option>`).join('')}</select></div>
            <div class="field"><label for="la-cmodel">Model</label><input class="input" id="la-cmodel" name="cloud_model" value="${esc(cloud.model || '')}" placeholder="e.g. llama-3.1-8b-instant"></div>
            <div class="field full"><label for="la-curl">Endpoint (OpenAI-compatible)</label><input class="input" id="la-curl" name="cloud_url" value="${esc(cloud.url || '')}" placeholder="https://…/v1"></div>
            <div class="field full"><label for="la-ckey">Free API key ${cloud.has_key ? '<small class="faint">· saved (leave empty to keep)</small>' : ''}</label><input class="input" id="la-ckey" name="cloud_key" type="password" autocomplete="off" placeholder="Paste the free key from the provider"></div>
          </div></details>
        <div class="row-end"><button class="btn primary hv" type="submit">Save</button></div>
      </div></form>`;
  }
  let localPullTimer = 0;
  function watchLocalPull() {
    clearTimeout(localPullTimer);
    if (!S.localAI || !S.localAI.pull || S.localAI.pull.status !== 'pulling') return;
    localPullTimer = setTimeout(async () => {
      try { S.localAI = await api('/ai/local'); if (S.view === 'settings' && S.set.section === 'ai') { S.lastHtml = ''; render(); } } catch (e) {}
      watchLocalPull();
    }, 1500);
  }
  function geminiKeyCard() {
    const g = S.gemini || {}, src = g.key_source || 'none';
    const state = src === 'yours' ? ['teal', `Using your key ${esc(g.key_hint || '')}`]
      : src === 'server' ? ['amber', `Using this computer's key ${esc(g.key_hint || '')}`]
      : ['coral', 'No key — AI features use simple built-in fallbacks'];
    return `<form class="card" data-gemini-key-form><div class="card-h"><span class="card-t">Gemini API key</span><span class="aside"><span class="dot ${state[0]}"></span>${state[1]}</span></div>
      <div class="card-b stack">
        <p class="muted small">Answers, cover letters, form fixes and the assistant run on Google Gemini. Use your own free key so your usage is yours alone. It's checked with Google before saving and stored encrypted on this computer.</p>
        <div class="field"><label for="gk">Your key</label><input class="input" id="gk" name="api_key" type="password" autocomplete="off" spellcheck="false" placeholder="Paste a key from Google AI Studio"></div>
        <div class="row-between wrap"><a class="btn ghost sm hv" href="https://aistudio.google.com/apikey" target="_blank" rel="noopener">${icon('open_in_new')}Get a free key</a>
          <span class="row-start">${src === 'yours' ? `<button type="button" class="btn sm ghost hv" data-act="gemini-key-remove">Remove my key</button>` : ''}<button class="btn primary hv" type="submit">${icon('key')}Save key</button></span></div>
      </div></form>`;
  }
  function settingsPanel(sec) {
    const p = S.profile, g = S.gemini || {}, st = S.stats || {}, au = S.automation || {};
    const f = (name, label, opts = {}) => {
      const v = p[name] ?? '';
      const type = opts.type || 'text';
      const val = Array.isArray(v) ? v.join(', ') : v;
      return `<div class="field ${opts.full ? 'full' : ''}"><label for="f-${name}">${label}</label><input class="input ${type === 'number' ? 'tnum' : ''}" id="f-${name}" name="${name}" type="${type}" ${opts.step ? `step="${opts.step}"` : ''} ${opts.min !== undefined ? `min="${opts.min}"` : ''} ${opts.max !== undefined ? `max="${opts.max}"` : ''} value="${esc(val)}" data-kind="${Array.isArray(v) ? 'list' : type}">${opts.hint ? `<span class="hint">${opts.hint}</span>` : ''}</div>`;
    };
    const tg = (name, label, hint) => `<label class="set-row hv"><div class="grow">${label}${hint ? `<small>${hint}</small>` : ''}</div><span class="toggle"><input type="checkbox" name="${name}" ${p[name] ? 'checked' : ''}><i></i></span></label>`;
    const save = (label) => `<div class="full row-end"><button class="btn primary hv" type="submit">${label}</button></div>`;
    const card = (title, aside, body) => `<section class="card"><div class="card-h"><span class="card-t">${title}</span><span class="aside">${aside || ''}</span></div>${body}</section>`;

    if (sec === 'appearance') return `<div class="stack">${appearancePanel(true)}</div>`;
    if (sec === 'facts') return factsEditor();
    if (sec === 'profile') return `<div class="stack">
      <div class="card"><div class="profile-hero">
        <label class="avatar-pick" title="Change profile picture">${me('lg')}<span class="avatar-edit">${icon('photo_camera')}</span>
          <input type="file" id="avatar-file" accept="image/png,image/jpeg,image/webp,image/gif" hidden></label>
        <div class="min0 grow"><h2>${esc(p.full_name)}</h2><div class="muted small">${esc(p.education)}${p.cgpa ? ` · CGPA ${esc(p.cgpa)}` : ''}</div>
          <div class="row-start mt-2"><label class="btn sm hv" for="avatar-file">${icon('add_a_photo')}${S.avatar && S.avatar.has_avatar ? 'Change photo' : 'Add photo'}</label>
          ${S.avatar && S.avatar.has_avatar ? `<button class="btn sm ghost hv" data-act="avatar-remove">Remove</button>` : ''}</div></div></div></div>
      ${appearancePanel()}
      <form class="card" data-profile-form="contact"><div class="card-h"><span class="card-t">Contact & credentials</span><span class="aside">Used exactly as written on forms</span></div>
        <div class="card-b form-grid">
          ${f('full_name', 'Full name')}${f('email', 'Email', { type: 'email' })}
          ${f('phone', 'Phone')}${f('cgpa', 'CGPA')}
          ${f('education', 'Education', { full: true })}
          ${f('linkedin', 'LinkedIn', { full: true })}${f('github', 'GitHub', { full: true })}
          ${f('graduation_date', 'Graduation date')}${f('notice_period', 'Notice period')}
          ${f('work_authorization', 'Work authorization')}${f('relocation_preference', 'Relocation')}
          ${save('Save profile')}
        </div></form></div>`;

    if (sec === 'resume') {
      const r = S.resume || {};
      return `<div class="stack">
        <section class="card"><div class="card-h"><span class="card-t">Your resume</span><span class="aside">One file · each upload replaces the last</span></div>
          <div class="card-b stack">
            ${r.uploaded ? `<div class="file-row"><span class="art plain lg">${icon('description')}</span><div class="grow"><div class="strong ellipsis">${esc(r.filename)}</div>
              <div class="muted small tnum">${fmt(Math.round((r.size_bytes || 0) / 1024))} KB · ${fmt(r.chars || 0)} characters read · uploaded ${esc(rel(r.uploaded_at))}</div></div>
              ${r.path ? `<a class="btn sm hv" href="${esc(r.path)}" target="_blank" rel="noopener">${icon('open_in_new')}View</a>` : ''}</div>` : ''}
            <label class="dropzone hv" data-dropzone>
              <input type="file" id="resume-file" accept=".pdf,.docx,.txt,application/pdf,text/plain,application/vnd.openxmlformats-officedocument.wordprocessingml.document" hidden>
              ${icon('upload_file')}<span class="strong">${r.uploaded ? 'Upload a new version' : 'Upload your resume'}</span>
              <span class="muted small">PDF, Word or text · up to 10 MB${r.uploaded ? ' · replaces the current file' : ''}</span></label>
            ${r.preview ? `<details class="collapse plain"><summary class="small muted">What ApplyPilot read ${icon('expand_more', 'chev')}</summary><p class="preview-text small">${esc(r.preview)}…</p></details>` : ''}
          </div></section>
        ${card('Tailored versions', `${S.resumes.length}`, `<div class="list">${S.resumes.map(v => `<div class="row"><span class="art plain">${icon('description')}</span>
          <div class="grow"><div class="main-t">${esc(v.version_name)}</div><div class="sub-t">${esc(v.target_role)} · ATS ${Math.round(v.ats_score)}</div></div>
          <div class="end">${v.is_master ? '<span class="chip">Master</span>' : ''}</div></div>`).join('') || '<div class="empty tight">No tailored versions yet</div>'}</div>`)}</div>`;
    }

    if (sec === 'preferences') return `<form class="card" data-profile-form="targeting"><div class="card-h"><span class="card-t">Job preferences</span><span class="aside">What autopilot looks for</span></div>
        <div class="card-b form-grid">
          ${f('target_roles', 'Target roles', { full: true, hint: 'Comma separated' })}
          ${f('locations', 'Locations', { full: true, hint: 'Comma separated' })}
          ${f('excluded_companies', 'Never apply to', { full: true, hint: 'Comma separated' })}
          ${f('min_salary_inr', 'Minimum salary (₹ / year)', { type: 'number', min: 0 })}${f('min_stipend_inr', 'Minimum stipend (₹ / month)', { type: 'number', min: 0 })}
          ${f('preferred_work_mode', 'Work mode', { full: true })}
        </div>
        <div class="set-list card-sep">${tg('allow_unknown_salary', 'Apply when pay is not listed')}${tg('allow_unpaid_internships', 'Allow unpaid internships')}</div>
        <div class="card-b row-end">${save('Save preferences')}</div></form>`;

    if (sec === 'autopilot') {
      const ap = S.autopilot || {}, cfg = ap.config || {}, sta = ap.state || {}, es = engineStatus();
      const opt = (vals, cur, unit) => vals.map(v => `<option value="${v}" ${Number(cur) === v ? 'selected' : ''}>${v} ${unit}</option>`).join('');
      return `<div class="stack">
        <form class="card" data-ap-form><div class="card-h"><span class="card-t">Autopilot</span><span class="aside"><span class="dot ${es.dot}"></span>${esc(es.label)}</span></div>
          <div class="set-list"><label class="set-row hv"><span class="grow">Apply automatically<small>Find, score and apply in the background, within your limits.</small></span>
            <span class="toggle"><input type="checkbox" name="enabled" ${cfg.enabled !== false ? 'checked' : ''}><i></i></span></label></div>
          <div class="card-b form-grid card-sep">
            <div class="field"><label for="ap-disc">Look for new roles every</label><select class="select" id="ap-disc" name="discovery_hours">${opt([2, 4, 6, 12, 24], cfg.discovery_hours, 'hours')}</select></div>
            <div class="field"><label for="ap-proof">Check email every</label><select class="select" id="ap-proof" name="proof_sync_minutes">${opt([10, 20, 30, 60], cfg.proof_sync_minutes, 'minutes')}</select></div>
            <div class="full facts-list small">
              <div><span class="faint">Last search</span><span>${sta.last_discovery_at ? `${esc(rel(sta.last_discovery_at))} · ${fmt(sta.last_discovered || 0)} new` : 'Not yet'}</span></div>
              <div><span class="faint">Last application</span><span class="ellipsis">${sta.last_apply_at ? `${esc(rel(sta.last_apply_at))} · ${esc(sta.last_apply_job || '')}` : 'Not yet'}</span></div>
              <div><span class="faint">Pace</span><span>One application every ${fmt(ap.apply_gap_minutes || 6)} min while active</span></div>
            </div>
            <div class="full row-between"><button type="button" class="btn hv" data-act="ap-run">${icon('bolt')}Run a cycle now</button><button class="btn primary hv" type="submit">Save</button></div>
          </div></form>
        <section class="card"><div class="set-list">
          <div class="set-row"><div class="grow">Live submissions<small>${st.go_live ? 'Applications are really submitted to employers.' : 'Dry run: forms are filled and screenshotted, never submitted.'}</small></div>
            <button type="button" class="btn sm hv ${st.go_live ? 'danger' : 'primary'}" data-act="${st.go_live ? 'mode-dry' : 'mode-live'}">${st.go_live ? 'Switch to dry run' : 'Go live…'}</button></div>
          <div class="set-row"><div class="grow">Queue<small>${esc(engineLabel(st)[0])}${au.affected_queue_count ? ` · ${au.affected_queue_count} waiting` : ''}</small></div>
            <button type="button" class="btn sm hv" data-act="${st.is_paused ? 'resume' : 'pause'}">${st.is_paused ? 'Resume' : 'Pause'}</button></div>
        </div></section>
        <form class="card" data-profile-form="engine"><div class="card-h"><span class="card-t">Limits & schedule</span></div>
          <div class="card-b form-grid">
            ${f('daily_cap', 'Daily limit', { type: 'number', min: 0 })}${f('hourly_cap', 'Hourly limit', { type: 'number', min: 1 })}
            ${f('daily_target', 'Daily goal', { type: 'number', min: 0 })}${f('timezone', 'Timezone')}
            ${f('active_hours_start', 'Active from (hour, 0–23)', { type: 'number', min: 0, max: 23 })}${f('active_hours_end', 'Active until (hour, 0–24)', { type: 'number', min: 0, max: 24 })}
            ${f('min_fit_score', 'Auto-apply at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Roles at or above this are applied to automatically' })}${f('maybe_fit_score', 'Ask me at score ≥', { type: 'number', step: '0.1', min: 0, max: 5, hint: 'Between the two goes to Needs you › Triage' })}
            ${save('Save limits')}
          </div></form></div>`;
    }

    if (sec === 'email') {
      const ps = S.proofStatus || {}, c = ps.counts || {};
      return `<div class="stack">${ps.connected
        ? card('Email proof', '<span class="dot teal"></span>Connected', `<div class="set-list">
            <div class="set-row"><span class="grow">${esc(ps.address)}<small>${ps.source === 'env' ? 'From the server’s .env file' : 'Read-only · app password stored encrypted on your PC'}</small></span></div>
            <div class="set-row"><span class="grow">Last checked<small>${ps.last_sync ? esc(rel(ps.last_sync)) : 'Not yet'}${ps.last_error ? ` · <span class="bad">${esc(ps.last_error)}</span>` : ''}</small></span><button class="btn sm hv" data-act="proof-sync">${icon('refresh')}Check now</button></div>
            <div class="set-row"><span class="grow">Found so far<small class="tnum">${fmt(c.confirmation || 0)} confirmations · ${fmt(c.interview || 0)} interviews · ${fmt(c.rejection || 0)} decisions</small></span><button class="btn sm ghost hv" data-nav="proof">View ${icon('chevron_right')}</button></div>
            ${ps.source === 'app' ? `<div class="set-row"><span class="grow">Disconnect<small>Stops reading your inbox and deletes the stored app password</small></span><button class="btn sm danger hv" data-act="proof-disconnect">Disconnect</button></div>` : ''}
          </div>`)
        : card('Connect your inbox', 'Read-only', `<div class="card-b">${emailConnectForm()}</div>`)}
        <details class="card collapse" ${ps.connected ? '' : 'open'}><summary class="card-h"><span class="card-t">How to create a Gmail app password</span>${icon('expand_more', 'chev ml-auto')}</summary>
          <div class="card-b"><ol class="steps">${TUTORIALS.find(t => t.id === 'email').steps.map(s => `<li>${esc(s)}</li>`).join('')}</ol></div></details></div>`;
    }

    if (sec === 'ai') return `<div class="stack">${freeAICard()}${geminiKeyCard()}<form class="card" data-gemini-form><div class="card-h"><span class="card-t">AI answers</span><span class="aside tnum">${fmt(g.gemini_answers_today || 0)} today · ~${fmt(g.saved_minutes || 0)} min saved</span></div>
        <div class="set-list"><label class="set-row hv"><div class="grow">Draft answers for new questions<small>Grounded only in your verified facts. Drafts wait in Needs you › AI drafts.</small></div><span class="toggle"><input type="checkbox" name="gemini_auto_answer_enabled" ${g.gemini_auto_answer_enabled ? 'checked' : ''}><i></i></span></label></div>
        <div class="card-b form-grid card-sep">
          <div class="field"><label for="g-conf">Minimum confidence</label><div class="range-row"><input type="range" id="g-conf" name="gemini_min_confidence" min="0.5" max="1" step="0.01" value="${g.gemini_min_confidence ?? 0.85}"><output>${Math.round((g.gemini_min_confidence ?? 0.85) * 100)}%</output></div></div>
          <div class="field"><label for="g-cap">Daily answer limit</label><input class="input tnum" id="g-cap" type="number" name="gemini_daily_cap" min="0" value="${g.gemini_daily_cap ?? 30}"></div>
          <div class="field full"><label>Always asks you about</label><div class="tags">${(g.gemini_sensitive_categories || []).map(c => `<span class="chip">${esc(c.replace(/_/g, ' '))}</span>`).join('')}</div></div>
          <div class="full row-between"><span class="faint small">${esc(g.model_name || '')}${g.circuit_breaker_active ? ' · <span class="bad">rate-limit pause active</span>' : ''}</span><button class="btn primary hv" type="submit">Save</button></div>
        </div></form></div>`;

    if (sec === 'answers') return answersBody();
    if (sec === 'help') return helpPanel();

    // data & privacy
    return `<div class="stack">
      ${card('Your data', '', `<div class="set-list">
        <div class="set-row"><span class="grow">Export applications<small>Every tracked role, its status, score and notes as a spreadsheet (CSV)</small></span><button class="btn sm hv" data-act="export-csv">${icon('download')}Export</button></div>
        <div class="set-row"><span class="grow">Back up now<small>Saves the database and Answer bank to the backups folder on your PC</small></span><button class="btn sm hv" data-act="backup">${icon('backup')}Back up</button></div>
      </div>`)}
      ${card('Privacy', '', `<div class="card-b small muted stack">
        <p>Everything is stored on your own PC. Data leaves it only to: the job sites you apply to, Google Gemini (questions and job text, to draft answers), and Gmail (read-only) if you connect it.</p>
        <p>Your email app password is encrypted on disk. Your access token is kept in a secure, script-proof cookie and never shown in the address bar.</p></div>`)}
      ${IN_SHELL ? card('Phone app', '', `<div class="set-list"><div class="set-row"><div class="grow">Connected to<small>${esc(location.host)}</small></div><button type="button" class="btn sm hv" data-act="shell-server">Change server</button></div></div>`) : ''}
    </div>`;
  }
  afterRender.settings = () => {
    const r = $('#g-conf');
    r && r.addEventListener('input', () => { r.nextElementSibling.value = Math.round(r.value * 100) + '%'; });
    if (S.set.section === 'answers') afterRender.answers();
    const preset = $('[data-cloud-preset]');
    if (preset) preset.addEventListener('change', () => { const p = CLOUD_PRESETS.find(x => x[0] === preset.value); if (p && p[0]) { $('#la-curl').value = p[0]; $('#la-cmodel').value = p[2]; } });
    if (S.set.section === 'ai') watchLocalPull();
    const pic = $('#avatar-file');
    if (pic) pic.addEventListener('change', () => pic.files[0] && uploadAvatar(pic.files[0]));
    const input = $('#resume-file'), zone = $('[data-dropzone]');
    if (input) input.addEventListener('change', () => input.files[0] && uploadResume(input.files[0]));
    if (zone) {
      zone.addEventListener('dragover', (e) => { e.preventDefault(); zone.classList.add('drag'); });
      zone.addEventListener('dragleave', () => zone.classList.remove('drag'));
      zone.addEventListener('drop', (e) => { e.preventDefault(); zone.classList.remove('drag'); const file = e.dataTransfer.files[0]; if (file) uploadResume(file); });
    }
    $$('details[data-collapse]').forEach(d => d.addEventListener('toggle', () => { try { localStorage.setItem(`ap_${d.dataset.collapse}_open`, d.open ? '1' : '0'); } catch (e) {} }));
  };

  async function uploadAvatar(file) {
    if (file.size > 5 * 1024 * 1024) { toast('Choose an image smaller than 5 MB', true); return; }
    const fd = new FormData(); fd.append('file', file);
    const headers = TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {};
    try {
      const r = await fetch('/api/v1/profile/avatar', { method: 'POST', headers, body: fd });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.detail || `Upload failed (${r.status})`);
      S.avatar = data; toast('Profile picture updated'); S.lastHtml = ''; render();
    } catch (e) { toast(e.message, true); }
  }

  async function uploadResume(file) {
    const zone = $('[data-dropzone]');
    if (zone) zone.classList.add('busy-zone');
    const fd = new FormData(); fd.append('file', file);
    const headers = TOKEN ? { Authorization: `Bearer ${TOKEN}` } : {};
    try {
      const r = await fetch('/api/v1/profile/resume', { method: 'POST', headers, body: fd });
      const data = await r.json().catch(() => ({}));
      if (!r.ok) throw new Error(data.detail || `Upload failed (${r.status})`);
      S.resume = data; toast(`Resume uploaded · ${file.name}`); S.lastHtml = ''; render();
    } catch (e) { toast(e.message, true); if (zone) zone.classList.remove('busy-zone'); }
  }

  // ───────────────────────── Welcome tour ─────────────────────────
  const TOUR_KEY = 'ap_tour_done';
  const TOUR = [
    { icon: 'waving_hand', title: 'Welcome to ApplyPilot', text: 'It finds roles that fit you, applies on your behalf and keeps proof of every application — while you get on with your day.' },
    { icon: 'smart_toy', title: 'Autopilot does the work', text: 'Every few hours it searches job boards, scores each role against your profile and applies to the best ones, within the daily and hourly limits you set.' },
    { icon: 'inbox', title: 'Only what needs you', text: 'If a form asks something new, it waits in Needs you. Answer once and it’s remembered. Home shows only what needs your attention.' },
    { icon: 'mark_email_read', title: 'Proof in your inbox', text: 'Connect Gmail (read-only) and each employer confirmation — “Thanks for applying” — is linked to its application in Proof.' },
    { icon: 'shield', title: 'You stay in control', text: 'It starts in dry run: forms are filled but not sent. Turn on Live submissions in Settings › Autopilot when you’re ready.' },
    { icon: 'palette', title: 'Make it yours', text: 'Pick a theme, text size and font in Settings › Profile › Appearance. Replay this tour any time from Help & tutorials.' },
  ];
  // The backdrop and card stay put between steps; only the content slides, so nothing blinks.
  const tourBody = (st) => `<div class="tour-ic">${icon(st.icon, 'fill')}</div><h3 id="tour-t">${esc(st.title)}</h3><p>${esc(st.text)}</p>`;
  const tourActs = (step, last) => `<button class="btn ghost hv" data-tour="skip">${last ? '' : 'Skip'}</button><span class="grow"></span>
        ${step ? `<button class="btn hv" data-tour="back">Back</button>` : ''}
        <button class="btn primary hv" data-tour="${last ? 'done' : 'next'}" data-step="${step}">${last ? 'Get started' : 'Next'}</button>`;
  function openTour(step = 0, dir = 1) {
    const st = TOUR[step], last = step === TOUR.length - 1;
    const card = $('#overlay .tour');
    if (!card) {
      $('#overlay').innerHTML = `<div class="modal-wrap" data-tour-wrap><div class="modal tour" role="dialog" aria-modal="true" aria-labelledby="tour-t">
      <div class="tour-body" aria-live="polite">${tourBody(st)}</div>
      <div class="tour-dots" aria-label="Step ${step + 1} of ${TOUR.length}">${TOUR.map((_, i) => `<i class="${i === step ? 'on' : ''}"></i>`).join('')}</div>
      <div class="acts">${tourActs(step, last)}</div></div></div>`;
    } else {
      const body = $('.tour-body', card);
      body.style.setProperty('--dir', dir);
      body.classList.remove('swap'); void body.offsetWidth; // restart the slide
      body.innerHTML = tourBody(st);
      body.classList.add('swap');
      $$('.tour-dots i', card).forEach((d, i) => d.classList.toggle('on', i === step));
      $('.tour-dots', card).setAttribute('aria-label', `Step ${step + 1} of ${TOUR.length}`);
      $('.acts', card).innerHTML = tourActs(step, last);
    }
    $('#overlay [data-tour="' + (last ? 'done' : 'next') + '"]').focus({ preventScroll: true });
  }
  function closeTour(goStart) {
    try { localStorage.setItem(TOUR_KEY, '1'); } catch (e) {}
    $('#overlay').innerHTML = '';
    if (goStart) go('home');
  }
  document.addEventListener('click', (e) => {
    const b = e.target.closest('[data-tour]'); if (!b) return;
    const cur = Number(($('#overlay [data-step]') || {}).dataset?.step || 0);
    const a = b.dataset.tour;
    if (a === 'next') openTour(cur + 1, 1); else if (a === 'back') openTour(Math.max(0, cur - 1), -1); else closeTour(a === 'done');
  });
  document.addEventListener('keydown', (e) => {
    if (!$('#overlay .tour')) return;
    const cur = Number(($('#overlay [data-step]') || {}).dataset?.step || 0);
    if (e.key === 'Escape') { e.stopImmediatePropagation(); closeTour(false); }
    else if (e.key === 'ArrowRight' && cur < TOUR.length - 1) openTour(cur + 1, 1);
    else if (e.key === 'ArrowLeft' && cur > 0) openTour(cur - 1, -1);
  }, true);

  const PROFILE_SECTIONS = {
    engine: ['daily_cap', 'daily_target', 'hourly_cap', 'timezone', 'active_hours_start', 'active_hours_end', 'min_fit_score', 'maybe_fit_score'],
    targeting: ['target_roles', 'locations', 'excluded_companies', 'min_salary_inr', 'min_stipend_inr', 'preferred_work_mode', 'allow_unknown_salary', 'allow_unpaid_internships'],
    contact: ['full_name', 'email', 'phone', 'cgpa', 'education', 'linkedin', 'github', 'graduation_date', 'notice_period', 'work_authorization', 'relocation_preference'],
  };

  // ───────────────────────── Actions ─────────────────────────
  async function refreshAfterJobChange() {
    loadStats();
    if (S.view === 'pipeline') { S.jobs = await api('/jobs', { query: { compact: 1 } }); $('#pipe-body') ? ($('#pipe-body').innerHTML = S.pipe.mode === 'table' ? pipeTable() : pipeBoard()) : render(); }
    else if (['inbox', 'home', 'proof'].includes(S.view)) { await loaders[S.view](); render(); }
  }

  async function setMode(live) {
    const st = S.stats; if (!st || st.go_live === live) return;
    if (live) {
      const ok = await confirmModal({ title: 'Turn on live submissions?', body: 'ApplyPilot will <b>really submit</b> applications to employers within your caps and rules. Submissions can’t be withdrawn from here. You can switch back to dry run at any time.', ok: 'Go live', danger: true });
      if (!ok) return;
    }
    await run(null, () => api('/profile/toggle-go-live', { method: 'POST' }), r => r.go_live ? 'Live submissions on' : 'Back to dry run');
    await loadStats(); if (['settings', 'home'].includes(S.view)) go(S.view, { silent: true });
  }

  const actions = {
    reload: () => go(S.view),
    'close-insp': closeJob,
    'mode-dry': () => setMode(false),
    'mode-live': () => setMode(true),
    async pause(btn) {
      await run(btn, () => api('/automation/pause', { method: 'POST', query: { reason: 'paused_by_user', details: 'Paused from command center' } }), 'Engine paused');
      await loadStats(); if (['home', 'settings'].includes(S.view)) go(S.view, { silent: true });
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
      await loadStats(); if (['home', 'settings'].includes(S.view)) go(S.view, { silent: true });
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
      const status = $('#insp-status').value, notes = $('#insp-notes').value, recruiter_info = $('#insp-contact').value.trim();
      const follow = $('#insp-follow').value, follow_up_date = follow ? `${follow}T09:00:00` : null;
      await run(btn, () => api(`/jobs/${btn.dataset.id}/status`, { method: 'PUT', body: { status, notes, recruiter_info, follow_up_date } }), 'Saved');
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
    async 'local-ai-pull'(btn) {
      try { await api('/ai/local/pull', { method: 'POST', body: {} }); S.localAI = await api('/ai/local'); S.lastHtml = ''; render(); watchLocalPull(); toast('Downloading the free model — you can keep using the app'); }
      catch (e) { toast(e.message, true); }
    },
    async 'local-ai-refresh'() {
      try { S.localAI = await api('/ai/local'); S.lastHtml = ''; render(); toast(S.localAI.installed ? 'Ollama found' : "Ollama isn't running yet — open it after installing", !S.localAI.installed); }
      catch (e) { toast(e.message, true); }
    },
    async 'gemini-key-remove'() {
      const ok = await confirmModal({ title: 'Stop using your key?', body: "AI features will use this computer's key if it has one, otherwise simple built-in fallbacks.", ok: 'Remove key', danger: true });
      if (!ok) return;
      try { await api('/profile/gemini-key', { method: 'DELETE' }); S.gemini = await api('/profile/gemini-settings'); toast('Your key was removed'); S.lastHtml = ''; render(); }
      catch (e) { toast(e.message, true); }
    },
    'proj-add'() { const l = $('#proj-list'); if (l) { l.insertAdjacentHTML('beforeend', projRow()); $('.proj-row:last-child input', l).focus(); } },
    'proj-del'(btn) { const row = btn.closest('.proj-row'); if (row) row.remove(); },
    async 'avatar-remove'() {
      const ok = await confirmModal({ title: 'Remove your profile picture?', body: 'Your initials will show instead. You can add a photo again any time.', ok: 'Remove', danger: true });
      if (!ok) return;
      try { S.avatar = await api('/profile/avatar', { method: 'DELETE' }); toast('Profile picture removed'); S.lastHtml = ''; render(); }
      catch (e) { toast(e.message, true); }
    },
    'hide-checklist'() { try { localStorage.setItem(CHECK_KEY, '1'); } catch (e) {} S.lastHtml = ''; render(); },
    tour() { openTour(0); },
    async 'ap-run'(btn) {
      await run(btn, () => api('/autopilot/run-now', { method: 'POST' }), 'Autopilot cycle started — results appear in a minute');
      setTimeout(() => { if (['home', 'settings'].includes(S.view)) go(S.view, { silent: true }); }, 8000);
    },
    async 'proof-sync'(btn) {
      const r = await run(btn, () => api('/proofs/sync', { method: 'POST' }), (r) => r.status === 'error' ? `Inbox check failed: ${r.error}` : `Inbox checked · ${fmt(r.new || 0)} new`);
      if (r) go(S.view, { silent: true });
    },
    async 'proof-disconnect'(btn) {
      const ok = await confirmModal({ title: 'Disconnect your inbox?', body: 'ApplyPilot stops checking for employer emails and deletes the stored app password. Proof already found is kept.', ok: 'Disconnect', danger: true });
      if (!ok) return;
      const r = await run(btn, () => api('/proofs/connection', { method: 'DELETE' }), 'Inbox disconnected');
      if (r) { S.proofStatus = r; S.lastHtml = ''; render(); }
    },
    'export-csv'() {
      // Server builds the CSV. In the phone app the shell hands this URL to the phone's browser.
      if (IN_SHELL) { location.href = '/api/v1/jobs/export.csv'; return; }
      const a = document.createElement('a');
      a.href = '/api/v1/jobs/export.csv'; a.download = '';
      document.body.appendChild(a); a.click(); a.remove();
      toast('Exporting applications…');
    },
    async 'cover-letter'(btn) {
      const r = await run(btn, () => api('/ai/cover-letter', { method: 'POST', body: { job_id: Number(btn.dataset.id) } }));
      if (r) textSheet('Cover letter', r.cover_letter, r.source === 'gemini' ? 'Written by Gemini from your verified facts. Review before sending.' : (r.note || 'Template built from your verified facts (AI unavailable).'));
    },
    async 'interview-prep'(btn) {
      const j = S.job || {};
      const r = await run(btn, () => api('/ai/interview-prep', { method: 'POST', body: { job_id: Number(btn.dataset.id), title: j.title, company: j.company, location: j.location } }));
      if (!r) return;
      const qs = (r.technical_questions || []).map(q => `• ${q.question}\n  ${q.hint ? 'Tests: ' + q.hint + '\n  ' : ''}${q.model_answer || ''}`).join('\n\n');
      const bs = (r.behavioral_questions || []).map(q => `• ${q.question}\n  Situation: ${q.star_situation || ''}\n  Action: ${q.star_action || ''}\n  Result: ${q.star_result || ''}`).join('\n\n');
      textSheet(`Interview prep · ${j.company || ''}`, [r.company_overview, qs && `Technical\n\n${qs}`, bs && `Behavioural\n\n${bs}`, r.candidate_edge && `Your edge: ${r.candidate_edge}`].filter(Boolean).join('\n\n'), 'Generated from your verified facts and the role.');
    },
    async 'copy-text'() {
      const t = $('#sheet-text'); if (!t) return;
      try { await navigator.clipboard.writeText(t.value); toast('Copied'); } catch (e) { t.select(); document.execCommand('copy'); toast('Copied'); }
    },
    'shell-server'() { if (IN_SHELL) window.ApplyPilotShell.postMessage('change-server'); },
  };

  // ───────────────────────── Events ─────────────────────────
  document.addEventListener('click', (e) => {
    const t = e.target;
    const nav = t.closest('[data-nav]');
    if (nav) {
      e.preventDefault();
      const [base, sub] = nav.dataset.nav.split('/');
      if (nav.dataset.stage) { S.pipe.stage = nav.dataset.stage; S.pipe.limit = 100; }
      if (nav.dataset.tab) S.inbox.tab = nav.dataset.tab;
      if (base === 'inbox' && sub) S.inbox.tab = sub;
      if (nav.dataset.tut) S.helpOpen = nav.dataset.tut;
      closeJob(); go(nav.dataset.nav, { silent: S.view === base }); return;
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
    const sec = t.closest('[data-section]');
    if (sec) { S.set.section = sec.dataset.section; history.replaceState(null, '', `#/settings/${S.set.section}`); S.anim = false; render(); $('#content').scrollTop = 0; return; }
    const ins = t.closest('[data-ins-tab]');
    if (ins) { S.ins.tab = ins.dataset.insTab; go(`insights/${S.ins.tab}`, { silent: true }); return; }
    const pk = t.closest('[data-proof-kind]');
    if (pk) { S.proof.kind = pk.dataset.proofKind; render(); return; }
    const pr = t.closest('[data-proof]');
    if (pr) { openProof(Number(pr.dataset.proof)); return; }
    const fs = t.closest('[data-font-size]');
    if (fs) {
      setFont({ size: fs.dataset.fontSize });
      $$('[data-font-size]').forEach(b => { const on = b.dataset.fontSize === fs.dataset.fontSize; b.classList.toggle('on', on); b.setAttribute('aria-checked', on); });
      const ps = $('#theme-pop .seg'); if (ps) requestAnimationFrame(() => glide(ps, 'pop-size'));
      return;
    }
    const fst = t.closest('[data-font-style]');
    if (fst) { setFont({ style: fst.dataset.fontStyle }); return; }
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
    if (form.hasAttribute('data-local-ai-form')) {
      const el = form.elements, body = { mode: el.mode.value, model: el.model.value, cloud: { url: el.cloud_url.value.trim(), model: el.cloud_model.value.trim() } };
      if (el.cloud_key.value.trim()) body.cloud.key = el.cloud_key.value.trim();
      const r = await run(btn, () => api('/ai/local', { method: 'PUT', body }), 'Saved');
      if (r) { S.localAI = r; S.lastHtml = ''; render(); }
      return;
    }
    if (form.hasAttribute('data-gemini-key-form')) {
      const key = form.elements.api_key.value.trim();
      if (!key) { toast('Paste your key first', true); return; }
      const r = await run(btn, () => api('/profile/gemini-key', { method: 'PUT', body: { api_key: key } }), 'Key saved · AI features now use your key');
      if (r) { form.elements.api_key.value = ''; S.gemini = await api('/profile/gemini-settings'); S.lastHtml = ''; render(); }
      return;
    }
    if (form.hasAttribute('data-facts-form')) {
      const body = { personal: {}, education: {} };
      $$('input[data-sec]', form).forEach(i => { body[i.dataset.sec][i.name] = i.value.trim(); });
      ['patents', 'certifications', 'skills'].forEach(k => {
        const t = form.elements[k]; if (!t) return;
        body[k] = t.value.split(t.dataset.sep === 'comma' ? /[,\n]/ : /\n/).map(x => x.trim()).filter(Boolean);
      });
      ['work_authorization', 'notice_period', 'relocation_preference'].forEach(k => { if (form.elements[k]) body[k] = form.elements[k].value.trim(); });
      body.projects = $$('.proj-row', form).map(r => ({ name: $('[data-proj="name"]', r).value.trim(), description: $('[data-proj="description"]', r).value.trim() })).filter(pr => pr.name);
      const r = await run(btn, () => api('/profile/facts', { method: 'PUT', body }), 'Saved · forms, resumes and the assistant use this now');
      if (r) S.facts = r;
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
    if (form.hasAttribute('data-ap-form')) {
      const body = { enabled: form.elements.enabled.checked, discovery_hours: Number(form.elements.discovery_hours.value), proof_sync_minutes: Number(form.elements.proof_sync_minutes.value) };
      const r = await run(btn, () => api('/autopilot', { method: 'PUT', body }), body.enabled ? 'Autopilot saved' : 'Autopilot switched off');
      if (r) { S.autopilot = r; S.lastHtml = ''; render(); }
      return;
    }
    if (form.hasAttribute('data-email-form')) {
      const body = { address: form.elements.address.value.trim(), app_password: form.elements.app_password.value };
      const r = await run(btn, () => api('/proofs/connection', { method: 'PUT', body }), 'Inbox connected · checking now');
      if (r) { S.proofStatus = r; actions['proof-sync'](null); S.lastHtml = ''; render(); }
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
      { icon: 'play_circle', label: 'Replay the welcome tour', run: () => openTour(0) },
      { icon: 'download', label: 'Export applications (CSV)', run: () => actions['export-csv']() },
      { icon: 'mark_email_read', label: 'Check inbox for proof', run: () => actions['proof-sync']() },
      { icon: 'smart_toy', label: 'Run an autopilot cycle now', run: () => actions['ap-run']() },
      { icon: 'upload_file', label: 'Upload a new resume', run: () => go('settings/resume') },
      { icon: 'text_fields', label: 'Appearance: theme, text size and font', run: () => go('settings/profile') },
      { icon: 'help', label: 'Help & tutorials', run: () => go('settings/help') },
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
    if (!S.jobs) api('/jobs', { query: { compact: 1 } }).then(j => { S.jobs = j; if (pal) drawPalette(); }).catch(() => {});
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
    { id: 'sand', name: 'Sand', note: 'Warm cream · light' },
    { id: 'ocean', name: 'Ocean', note: 'Deep teal · dark' },
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
      <h3>Appearance</h3><p>Saved on this device.</p>${themeSwatches()}
      <div class="eyebrow mt-3 mb-2">Text size</div>
      <div class="seg wide" data-glide="pop-size" role="radiogroup" aria-label="Text size">${FONT_SIZES.map(([id, label]) => `<button role="radio" aria-checked="${fontPrefs().size === id}" class="${fontPrefs().size === id ? 'on' : ''}" data-font-size="${id}" title="${label}"><span class="size-a size-${id}" aria-hidden="true">A</span></button>`).join('')}</div>
      <button class="btn sm ghost hv pop-more" data-nav="settings/appearance">${icon('text_fields')}Fonts and more ${icon('chevron_right')}</button></div>`);
    glide($('#theme-pop .seg'), 'pop-size');
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
    if (e.target.closest('#theme-pop [data-nav]')) { closeThemePop(); return; }
    if ($('#theme-pop') && !e.target.closest('#theme-pop')) closeThemePop();
  });
  document.addEventListener('change', (e) => {
    if (e.target.matches('[data-theme-auto]')) setTheme(e.target.checked ? 'auto' : resolveTheme('auto'));
    if (e.target.matches('[data-reduce-motion]')) setFont({ motion: e.target.checked ? 'reduce' : 'auto' });
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
    if (typeof closeAI === 'function' && closeAI()) return true;
    if ($('#overlay').innerHTML) { if (pal) closePalette(); else $('#overlay').innerHTML = ''; return true; }
    if (S.jobId) { closeJob(); return true; }
    if (S.ans.editing || S.ans.adding) { actions['ans-cancel'](); return true; }
    if (S.view !== 'home') { go('home'); return true; }
    return false;
  };

  window.addEventListener('hashchange', () => { const v = location.hash.replace(/^#\/?/, ''); if (v && v !== S.view) go(v); });

  // ── Last-known snapshot for an instant cold start (small: no job list) ──
  const SNAP_KEY = 'ap_snapshot_v1', SNAP_FIELDS = ['stats', 'analytics', 'autopilot', 'proofStatus', 'proofs', 'profile', 'avatar', 'resume', 'needs', 'aiAnswers'];
  function hydrate() {
    try {
      const snap = JSON.parse(localStorage.getItem(SNAP_KEY) || 'null');
      if (!snap || Date.now() - snap.at > 3 * 86400000) return false;
      SNAP_FIELDS.forEach(k => { if (snap[k] != null && (S[k] == null || (Array.isArray(S[k]) && !S[k].length))) S[k] = snap[k]; });
      return !!snap.stats;
    } catch (e) { return false; }
  }
  let persistT = 0;
  function persist() {
    clearTimeout(persistT);
    persistT = setTimeout(() => {
      try { localStorage.setItem(SNAP_KEY, JSON.stringify({ at: Date.now(), ...Object.fromEntries(SNAP_FIELDS.map(k => [k, S[k]])) })); } catch (e) {}
    }, 1500);
  }


  // ───────────────────────── Assistant (always one tap away) ─────────────────────────
  // A floating ✦ button on every screen opens a chat that knows your facts, live numbers and
  // what you are looking at (Home, a job, Proof…). Ctrl/⌘ + I toggles it on desktop.
  S.chat = S.chat || [];
  const md = (text) => {
    const lines = esc(String(text || '')).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').split(/\n/);
    let html = '', list = false;
    for (const raw of lines) {
      const line = raw.trim();
      const li = line.match(/^(?:[-*•]|\d+\.)\s+(.*)$/);
      if (li) { if (!list) { html += '<ul>'; list = true; } html += `<li>${li[1]}</li>`; continue; }
      if (list) { html += '</ul>'; list = false; }
      if (!line) continue;
      const h = line.match(/^#{1,4}\s+(.*)$/);
      html += h ? `<p class="ai-h">${h[1]}</p>` : `<p>${line}</p>`;
    }
    return html + (list ? '</ul>' : '');
  };
  const aiSuggestions = () => {
    if (S.job) return [`Should I apply to ${S.job.company}?`, `Prep me for a ${S.job.title} interview`, 'What could make this application stronger?'];
    return ({
      inbox: ['Help me answer these questions', 'Which triage roles are worth a yes?'],
      pipeline: ['Which roles should I prioritise?', 'Why were some jobs skipped?'],
      proof: ['Summarise what employers sent me', 'Who should I follow up with?'],
      settings: ['How do I turn on live applying?', 'How do I connect my email?'],
    }[S.view] || []).concat(['What needs me today?', 'How is my search going this week?']).slice(0, 4);
  };
  const fab = document.createElement('button');
  fab.className = 'ai-fab'; fab.id = 'ai-fab'; fab.setAttribute('aria-label', 'Ask the assistant'); fab.title = 'Ask the assistant (Ctrl+I)';
  fab.innerHTML = icon('auto_awesome', 'fill');
  document.body.appendChild(fab);
  const panel = document.createElement('section');
  panel.className = 'ai-panel'; panel.id = 'ai-panel'; panel.setAttribute('role', 'dialog'); panel.setAttribute('aria-label', 'Assistant'); panel.hidden = true;
  document.body.appendChild(panel);
  let aiBusy = false;
  function drawChat() {
    const msgs = S.chat.map(m => `<div class="ai-msg ${m.role}">${m.role === 'user' ? `<p>${esc(m.content)}</p>` : md(m.content)}</div>`).join('');
    const empty = `<div class="ai-empty"><div class="ai-orb">${icon('auto_awesome', 'fill')}</div><b>${esc(greeting())}</b><span>Ask anything about your search. I only use your verified facts and the app's live data.</span></div>`;
    panel.innerHTML = `<header class="ai-head"><span class="ai-title">${icon('auto_awesome', 'fill')}Assistant</span>
        ${S.chat.length ? `<button class="btn sm ghost hv" data-ai="clear">New chat</button>` : ''}
        <button class="btn icon ghost hv" data-ai="close" aria-label="Close">${icon('close')}</button></header>
      <div class="ai-body" id="ai-body">${S.chat.length ? msgs : empty}${aiBusy ? '<div class="ai-msg assistant typing"><i></i><i></i><i></i></div>' : ''}</div>
      ${aiBusy ? '' : `<div class="ai-chips">${aiSuggestions().map(q => `<button class="chip-btn hv" data-ai-q="${esc(q)}">${esc(q)}</button>`).join('')}</div>`}
      <form class="ai-compose" data-ai-form><textarea id="ai-input" rows="1" placeholder="Ask the assistant…" aria-label="Message"></textarea>
        <button class="btn primary icon hv" type="submit" aria-label="Send" ${aiBusy ? 'disabled' : ''}>${icon('arrow_upward')}</button></form>`;
    const body = $('#ai-body'); body.scrollTop = body.scrollHeight;
  }
  function openAI() {
    if (!panel.hidden) return;
    drawChat(); panel.hidden = false; fab.classList.add('open');
    requestAnimationFrame(() => panel.classList.add('on'));
    setTimeout(() => { const i = $('#ai-input'); i && matchMedia('(pointer: fine)').matches && i.focus(); }, 180);
  }
  function closeAI() {
    if (panel.hidden) return false;
    panel.classList.remove('on'); fab.classList.remove('open');
    setTimeout(() => { if (!panel.classList.contains('on')) panel.hidden = true; }, 260);
    return true;
  }
  async function askAI(text) {
    text = String(text || '').trim();
    if (!text || aiBusy) return;
    S.chat.push({ role: 'user', content: text }); aiBusy = true; drawChat();
    try {
      const timeout = new Promise((_, no) => setTimeout(() => no(new Error('it took too long — please try again')), 25000));
      const r = await Promise.race([timeout, api('/ai/chat', { method: 'POST', body: { message: text, history: S.chat.slice(-9, -1), view: S.view, job_id: S.job ? S.job.id : null } })]);
      S.chat.push({ role: 'assistant', content: r.response || 'No answer this time.' });
    } catch (e) { S.chat.push({ role: 'assistant', content: `Couldn't reach the assistant: ${e.message}` }); }
    aiBusy = false; drawChat();
    const i = $('#ai-input'); i && matchMedia('(pointer: fine)').matches && i.focus();
  }
  fab.addEventListener('click', () => (panel.hidden ? openAI() : closeAI()));
  panel.addEventListener('click', (e) => {
    const a = e.target.closest('[data-ai]'); const q = e.target.closest('[data-ai-q]');
    if (q) { askAI(q.dataset.aiQ); return; }
    if (!a) return;
    if (a.dataset.ai === 'close') closeAI();
    if (a.dataset.ai === 'clear') { S.chat = []; drawChat(); }
  });
  panel.addEventListener('submit', (e) => { e.preventDefault(); e.stopPropagation(); const i = $('#ai-input'); askAI(i.value); });
  panel.addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.shiftKey && e.target.id === 'ai-input') { e.preventDefault(); askAI(e.target.value); }
    if (e.key === 'Escape') { e.stopPropagation(); closeAI(); fab.focus(); }
  });
  panel.addEventListener('input', (e) => { if (e.target.id === 'ai-input') { e.target.style.height = 'auto'; e.target.style.height = Math.min(120, e.target.scrollHeight) + 'px'; } });
  document.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'i') { e.preventDefault(); panel.hidden ? openAI() : closeAI(); } });

  // ───────────────────────── Live polling ─────────────────────────
  async function poll() {
    if (document.hidden) return;
    await loadStats();
    const editing = isTyping() || $('#overlay').innerHTML || S.ans.editing || S.ans.adding;
    if (editing) return;
    // render({ poll: true }) skips the DOM entirely when nothing changed, so hovers are never interrupted.
    if (S.view === 'home') { try { await settle({ autopilot: api('/autopilot'), proofStatus: api('/proofs/status'), proofs: api('/proofs', { query: { limit: 5 } }) }); if (S.view === 'home') render({ poll: true }); persist(); } catch (e) {} }
    if (S.view === 'proof') { try { await loaders.proof(); if (S.view === 'proof') render({ poll: true }); } catch (e) {} }
    if (S.view === 'insights' && S.ins.tab === 'log') { try { await settle({ logs: api('/logs', { query: { limit: 250 } }) }); if (S.view === 'insights') render({ poll: true }); } catch (e) {} }
  }

  // ───────────────────────── Boot ─────────────────────────
  (async () => {
    applyTheme(themePref(), false);   // pre-paint script set the theme; this syncs the browser chrome colour
    applyFont();
    initLiquidGlass();
    renderChrome();
    const start = location.hash.replace(/^#\/?/, '') || 'home';
    // Open instantly with the last Home you saw (kept on this device), then refresh everything at once.
    if (hydrate()) S.fresh.home = 1;
    await Promise.allSettled([loadStats(), loaders.inbox(), go(start)]);
    render({ poll: true });
    persist();
    let toured = false; try { toured = localStorage.getItem(TOUR_KEY) === '1'; } catch (e) {}
    if (!toured) openTour(0);
    setInterval(poll, 15000);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) poll(); });
  })();
})();
