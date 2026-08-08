import type { UserRow } from "../types";
import { layout } from "./pages";

function escape(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

/** Safe conversation / call id for URLs and JS. */
function safeId(id: string): string {
  return /^[A-Za-z0-9_-]{6,80}$/.test(id) ? id : "";
}

const appCss = `
body.bare { background: var(--bg); }
.app-frame {
  min-height: 100dvh;
  min-height: 100svh;
  display: flex;
  flex-direction: column;
  background:
    radial-gradient(900px 420px at 0% 0%, #d9f2e6 0%, transparent 55%),
    var(--bg);
}
.app-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: calc(12px + var(--safe-top)) 16px 12px;
  border-bottom: 1px solid var(--line);
  background: rgba(238, 244, 240, 0.92);
  backdrop-filter: blur(10px);
  position: sticky;
  top: 0;
  z-index: 5;
}
.app-top .logo {
  font-family: var(--display);
  font-weight: 800;
  font-size: 1.25rem;
  letter-spacing: -0.03em;
  color: var(--ink);
  text-decoration: none;
}
.app-top-nav { display: flex; gap: 8px; flex-wrap: wrap; }
.app-top-nav a { text-decoration: none; }
.app-top-nav button {
  margin: 0; width: auto; padding: 10px 14px; min-height: 44px;
}
.app-main {
  flex: 1;
  display: flex;
  flex-direction: column;
  width: min(920px, 100%);
  margin: 0 auto;
  padding: 18px 16px calc(20px + var(--safe-bottom));
  min-height: 0;
}
.app-main.fill {
  width: 100%;
  max-width: none;
  padding: 0;
}
.app-title {
  font-family: var(--display);
  font-size: clamp(1.7rem, 4vw, 2.2rem);
  letter-spacing: -0.03em;
  margin: 0 0 6px;
}
.app-sub { color: var(--muted); margin: 0 0 18px; }
.chat-list { list-style: none; padding: 0; margin: 0; }
.chat-list li a {
  display: flex; justify-content: space-between; gap: 12px; align-items: center;
  padding: 16px 4px; border-bottom: 1px solid var(--line); color: inherit; text-decoration: none;
}
.chat-list li a:hover { background: rgba(11, 110, 79, 0.04); }
.chat-list .meta { color: var(--muted); font-size: 0.9rem; text-align: right; }
.badge {
  display: inline-block; min-width: 22px; padding: 2px 8px; border-radius: 999px;
  background: var(--brand); color: #fff; font-weight: 800; font-size: 0.8rem; text-align: center;
}
.chat-stage {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  overflow: hidden;
}
.chat-toolbar {
  display: flex; gap: 10px; flex-wrap: wrap; padding: 12px 14px;
  border-bottom: 1px solid var(--line); background: #f7fbf8;
}
.chat-toolbar button { margin: 0; width: auto; flex: 1; min-width: 120px; }
.msgs {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 12px;
  padding: 16px 14px;
  overflow-y: auto;
  min-height: 42vh;
}
.bubble {
  max-width: 85%; padding: 12px 14px; border-radius: 16px; background: #e8f3ee;
  border: 1px solid var(--line);
}
.bubble.mine { align-self: flex-end; background: #d9f2e6; }
.bubble.unread { background: #fff6c8; border-color: #e6d56a; }
.bubble .who { font-weight: 700; margin-bottom: 4px; }
.bubble .time { color: var(--muted); font-size: 0.85rem; margin-top: 6px; }
.composer {
  display: flex; gap: 10px; align-items: center; flex-wrap: wrap;
  padding: 12px 14px calc(12px + var(--safe-bottom));
  border-top: 1px solid var(--line);
  background: #f7fbf8;
}
.composer button { margin: 0; width: auto; min-width: 140px; }
#recHint { color: var(--muted); font-weight: 650; }
.call-frame {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-height: 0;
  background: #0b1a14;
  color: #e8f4ee;
}
.call-head {
  padding: calc(14px + var(--safe-top)) 16px 10px;
  display: flex; flex-direction: column; gap: 4px;
}
.call-head h1 {
  font-family: var(--display);
  font-size: 1.35rem;
  margin: 0;
  letter-spacing: -0.02em;
}
.call-head .hint { color: rgba(232, 244, 238, 0.65); margin: 0; }
.video-grid {
  flex: 1;
  display: grid; gap: 10px;
  min-height: 0;
  padding: 10px 12px;
  grid-template-columns: repeat(2, minmax(0, 1fr));
}
.video-grid.count-1 { grid-template-columns: 1fr; }
.video-grid.count-2 {
  grid-template-columns: 1fr;
  grid-template-rows: 1fr auto;
}
.video-grid.count-2 .lk-tile.remote { min-height: 0; }
.video-grid.count-2 .lk-tile.local {
  width: min(180px, 42vw); min-height: 120px; justify-self: end;
}
.video-grid.count-3, .video-grid.count-4 { grid-template-columns: repeat(2, minmax(0, 1fr)); }
.video-grid.count-5, .video-grid.count-6 { grid-template-columns: repeat(3, minmax(0, 1fr)); }
.video-grid video, .video-grid .lk-tile {
  width: 100%; min-height: 180px; background: #12261c; border-radius: 12px; object-fit: cover;
}
.video-grid .lk-media { width: 100%; height: 100%; min-height: inherit; }
.video-grid .lk-media video, .video-grid .lk-media audio {
  width: 100%; height: 100%; min-height: inherit; object-fit: cover; display: block;
}
.video-grid .lk-tile { position: relative; overflow: hidden; border: 1px solid transparent; }
.video-grid .lk-tile.active { border-color: #3ddc97; }
.video-grid .lk-tile .lk-name {
  position: absolute; left: 8px; bottom: 8px; padding: 4px 8px; border-radius: 8px;
  background: #0009; color: #fff; font-size: .85rem; z-index: 2;
}
.call-controls {
  display: flex; gap: 10px; flex-wrap: wrap;
  padding: 12px 14px calc(16px + var(--safe-bottom));
  background: rgba(0,0,0,0.28);
}
.call-controls button { width: auto; flex: 1; min-width: 110px; margin: 0; }
.inbox-panel {
  flex: 1;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 8px 16px 16px;
  min-height: 50vh;
}
.qr-stage {
  display: flex; flex-direction: column; align-items: center; gap: 16px;
  padding: 28px 16px; text-align: center;
}
.app-top .app-user {
  display: flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
  color: var(--ink);
  text-decoration: none;
}
.app-top .app-user-copy {
  display: flex;
  flex-direction: column;
  min-width: 0;
}
.app-top .app-user-copy strong {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.app-top .app-user-copy small { color: var(--muted); }
.web-avatar {
  display: grid;
  place-items: center;
  flex: 0 0 auto;
  width: 52px;
  height: 52px;
  border-radius: 50%;
  object-fit: cover;
  background: var(--brand-soft);
  color: var(--brand);
  font-family: var(--display);
  font-size: 1.35rem;
  font-weight: 800;
}
.inbox-panel { padding: 10px 16px 16px; }
.chat-list li a {
  min-height: 78px;
  padding: 12px 4px;
  border-radius: 14px;
  transition: background 180ms ease, transform 180ms ease;
}
.chat-list li a:hover { transform: translateX(2px); }
.chat-row-main {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 0;
}
.chat-row-copy { min-width: 0; }
.chat-row-copy strong,
.chat-row-copy .hint {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}
.chat-row-copy .hint { margin-top: 3px; }
.chat-list li.unread a { background: rgba(11, 110, 79, .05); }
.chat-list li.unread .web-avatar {
  box-shadow: 0 0 0 3px rgba(11, 110, 79, .16);
  animation: unreadPulse 1.8s ease-in-out infinite;
}
.chat-list li.unread .chat-row-copy strong { font-weight: 800; }
.chat-toolbar button {
  min-height: 52px;
  border-radius: 16px;
  transition: transform 160ms ease, background 160ms ease;
}
.chat-toolbar button:active,
.composer button:active { transform: scale(.98); }
.voice-bubble {
  display: flex;
  align-items: center;
  gap: 12px;
  min-width: 210px;
  min-height: 58px;
  padding: 9px 12px;
  border-radius: 18px;
}
.voice-bubble .play {
  display: grid;
  place-items: center;
  flex: 0 0 42px;
  width: 42px;
  height: 42px;
  padding: 0;
  margin: 0;
  border-radius: 50%;
  background: var(--brand);
  color: #fff;
  font-size: 1.05rem;
}
.voice-bubble .wave {
  display: flex;
  align-items: center;
  gap: 3px;
  height: 30px;
  flex: 1;
}
.voice-bubble .wave i {
  display: block;
  width: 3px;
  min-height: 5px;
  border-radius: 999px;
  background: currentColor;
  opacity: .45;
}
.voice-bubble.playing .wave i { animation: waveBars 900ms ease-in-out infinite alternate; }
.voice-bubble .duration {
  flex: 0 0 auto;
  color: var(--muted);
  font-size: .82rem;
  font-variant-numeric: tabular-nums;
}
.bubble.mine .voice-bubble { background: transparent; }
.bubble.unread .voice-bubble { color: #8b6b00; }
.bubble.unread .voice-bubble .play { background: #b88700; }
.call-controls {
  align-items: flex-start;
  justify-content: center;
  gap: 14px;
  padding-top: 14px;
}
.call-round-action {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 7px;
  flex: 0 0 76px;
  margin: 0;
  padding: 0;
  background: transparent;
  color: #fff;
  font-size: .78rem;
  font-weight: 700;
}
.call-controls .call-round-action {
  width: auto;
  min-width: 76px;
  flex: 0 0 76px;
}
.call-round-action .round-icon {
  display: grid;
  place-items: center;
  width: 68px;
  height: 68px;
  border-radius: 50%;
  background: rgba(255,255,255,.12);
  font-size: 1.35rem;
  transition: transform 160ms ease, background 160ms ease;
}
.call-round-action:hover .round-icon { background: rgba(255,255,255,.2); }
.call-round-action:active .round-icon { transform: scale(.92); }
.call-round-action.danger .round-icon { background: var(--danger); }
.call-round-action:disabled { opacity: .4; }
.call-head h1 { font-size: clamp(1.35rem, 3vw, 2rem); }
.lk-tile {
  transition: border-color 280ms ease, box-shadow 280ms ease, transform 280ms ease;
}
.lk-tile.active { animation: speakerPulse 1.3s ease-in-out infinite; }
@keyframes unreadPulse {
  0%, 100% { box-shadow: 0 0 0 3px rgba(11, 110, 79, .12); }
  50% { box-shadow: 0 0 0 6px rgba(11, 110, 79, .04); }
}
@keyframes waveBars {
  from { transform: scaleY(.55); opacity: .42; }
  to { transform: scaleY(1.15); opacity: .9; }
}
@keyframes speakerPulse {
  0%, 100% { box-shadow: 0 0 0 0 rgba(61, 220, 151, .18); }
  50% { box-shadow: 0 0 0 5px rgba(61, 220, 151, .08); }
}
@media (max-width: 520px) {
  .app-top { padding-left: 12px; padding-right: 12px; }
  .app-top .app-user-copy { max-width: 130px; }
  .app-top-nav button { padding-left: 10px; padding-right: 10px; }
  .call-controls { gap: 8px; padding-left: 8px; padding-right: 8px; }
  .call-controls .call-round-action {
    min-width: 58px;
    flex-basis: 58px;
    font-size: .68rem;
  }
  .call-round-action .round-icon { width: 54px; height: 54px; }
}
`;

/** Shared client helpers — escape API strings before any HTML use. */
const clientHelpers = `
function esc(s) {
  return String(s ?? '').replace(/[&<>"']/g, (c) => ({
    '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'
  }[c]));
}
async function api(path, opts={}) {
  const headers = { 'X-Client': 'web', ...(opts.headers||{}) };
  if (opts.json !== undefined) headers['Content-Type'] = 'application/json';
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), opts.timeout || (opts.body ? 60000 : 12000));
  try {
    const res = await fetch(path, {
      credentials: 'include',
      method: opts.method || (opts.json !== undefined || opts.body ? 'POST' : 'GET'),
      headers,
      body: opts.json !== undefined ? JSON.stringify(opts.json) : opts.body,
      signal: controller.signal,
    });
    const body = await res.json().catch(() => ({}));
    if (!res.ok) throw new Error(body.error || ('Hiba ' + res.status));
    return body;
  } finally {
    clearTimeout(timer);
  }
}
function connectRealtime(onEvent) {
  let ws = null;
  let backoff = 1000;
  let closed = false;
  let pingTimer = null;
  function open() {
    if (closed) return;
    const proto = location.protocol === 'https:' ? 'wss:' : 'ws:';
    ws = new WebSocket(proto + '//' + location.host + '/api/realtime/ws');
    ws.onopen = () => {
      backoff = 1000;
      clearInterval(pingTimer);
      pingTimer = setInterval(() => {
        try { ws && ws.readyState === 1 && ws.send(JSON.stringify({ type: 'ping' })); } catch (_) {}
      }, 25000);
    };
    ws.onmessage = (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (onEvent) onEvent(data);
      } catch (_) {}
    };
    ws.onclose = () => {
      clearInterval(pingTimer);
      if (closed) return;
      setTimeout(open, backoff);
      backoff = Math.min(backoff * 2, 30000);
    };
    ws.onerror = () => { try { ws.close(); } catch (_) {} };
  }
  open();
  return () => { closed = true; clearInterval(pingTimer); try { ws && ws.close(); } catch (_) {} };
}
`;

function appShell(
  title: string,
  user: UserRow,
  body: string,
  opts?: { fill?: boolean; hideNav?: boolean },
): string {
  const fill = !!opts?.fill;
  const hideNav = !!opts?.hideNav;
  const avatarUrl = user.avatar_key
    ? `/api/users/${encodeURIComponent(user.id)}/avatar`
    : "";
  const initial = escape(user.name.trim().charAt(0).toUpperCase() || "?");
  return layout(
    title,
    `
    <style>${appCss}</style>
    <div class="app-frame">
      ${
        hideNav
          ? ""
          : `<header class="app-top">
        <a class="app-user" href="/account">
          ${
            avatarUrl
              ? `<img class="web-avatar" src="${escape(avatarUrl)}" alt="${escape(user.name)}" />`
              : `<span class="web-avatar" aria-hidden="true">${initial}</span>`
          }
          <span class="app-user-copy">
            <strong>Szia ${escape(user.name)}!</strong>
            <small>MyÜzi</small>
          </span>
        </a>
        <nav class="app-top-nav">
          <a href="/app"><button class="secondary" type="button">Beszélgetések</button></a>
          <a href="/account"><button class="ghost" type="button">Beállítások</button></a>
        </nav>
      </header>`
      }
      <main class="app-main${fill ? " fill" : ""}">${body}</main>
    </div>
  `,
    { vision: !!user.vision_assist, variant: "bare" },
  );
}

export function appInboxPage(user: UserRow): string {
  return appShell(
    "Beszélgetések",
    user,
    `
    <h1 class="app-title">Beszélgetések</h1>
    <p class="app-sub">Hangüzenetek és hívások · ${escape(user.name)}</p>
    <div class="inbox-panel">
      <div id="status" class="hint">Betöltés…</div>
      <ul class="chat-list" id="list"></ul>
    </div>
    <script>
    ${clientHelpers}
    function fmt(iso) {
      if (!iso) return '';
      try { return new Date(iso).toLocaleString('hu-HU', { month:'short', day:'numeric', hour:'2-digit', minute:'2-digit' }); }
      catch { return ''; }
    }
    let loading = false;
    async function load() {
      if (loading) return;
      loading = true;
      const status = document.getElementById('status');
      const list = document.getElementById('list');
      try {
        const data = await api('/api/conversations');
        const chats = data.conversations || [];
        if (!chats.length) {
          status.textContent = 'Még nincs beszélgetés. Nyisd meg az appot, vagy hívj meg valakit.';
          list.replaceChildren();
          return;
        }
        status.textContent = '';
        list.replaceChildren();
        for (const c of chats) {
          const id = String(c.id || '');
          if (!/^[A-Za-z0-9_-]{6,80}$/.test(id)) continue;
          const li = document.createElement('li');
          li.className = c.unreadCount > 0 ? 'unread' : '';
          const a = document.createElement('a');
          a.href = '/app/chat/' + encodeURIComponent(id);
          const left = document.createElement('span');
          left.className = 'chat-row-main';
          const avatar = document.createElement(c.avatarUrl ? 'img' : 'span');
          avatar.className = 'web-avatar';
          if (c.avatarUrl) {
            avatar.src = String(c.avatarUrl);
            avatar.alt = String(c.name || 'Beszélgetés');
          } else {
            avatar.textContent = String(c.name || 'B').trim().charAt(0).toUpperCase() || '?';
          }
          left.appendChild(avatar);
          const copy = document.createElement('span');
          copy.className = 'chat-row-copy';
          const strong = document.createElement('strong');
          strong.textContent = c.name || 'Beszélgetés';
          copy.appendChild(strong);
          const hint = document.createElement('span');
          hint.className = 'hint';
          hint.textContent = c.lastSenderName ? (c.lastSenderName + ': hangüzenet') : '';
          copy.appendChild(hint);
          left.appendChild(copy);
          const meta = document.createElement('span');
          meta.className = 'meta';
          meta.appendChild(document.createTextNode(fmt(c.lastMessageAt)));
          if (c.unreadCount > 0) {
            meta.appendChild(document.createElement('br'));
            const badge = document.createElement('span');
            badge.className = 'badge';
            badge.textContent = String(c.unreadCount);
            meta.appendChild(badge);
          }
          a.appendChild(left);
          a.appendChild(meta);
          li.appendChild(a);
          list.appendChild(li);
        }
      } catch (e) {
        status.textContent = e.message || 'Betöltési hiba';
      } finally {
        loading = false;
      }
    }
    load();
    connectRealtime((ev) => {
      if (ev.type === 'message_created' || ev.type === 'conversation_updated' ||
          ev.type === 'incoming_call' || ev.type === 'call_ended' || ev.type === 'call_updated') {
        load();
      }
    });
    setInterval(load, 30000);
    </script>
  `,
  );
}

export function appChatPage(user: UserRow, conversationId: string, title: string): string {
  const id = safeId(conversationId);
  if (!id) {
    return appShell("Hiba", user, `<div class="inbox-panel"><p class="error">Érvénytelen beszélgetés.</p></div>`);
  }
  const safeTitle = escape(title || "Beszélgetés");
  return appShell(
    title || "Beszélgetés",
    user,
    `
    <h1 class="app-title" id="chatTitle">${safeTitle}</h1>
    <div class="chat-stage">
      <div class="chat-toolbar">
        <button type="button" id="btnAudio" class="secondary">Hanghívás</button>
        <button type="button" id="btnVideo">Videóhívás</button>
      </div>
      <div id="status" class="hint" style="padding:10px 14px 0">Betöltés…</div>
      <div class="msgs" id="msgs"></div>
      <div class="composer">
        <button type="button" id="recBtn">Felvétel</button>
        <span id="recHint"></span>
      </div>
    </div>
    <script>
    ${clientHelpers}
    const conversationId = ${JSON.stringify(id)};
    const meId = ${JSON.stringify(user.id)};
    let mediaRecorder = null;
    let chunks = [];
    let recording = false;
    let startedAt = 0;
    let recordTimer = null;
    let recordedBytes = 0;
    let recordTooLarge = false;
    let sending = false;
    let loadingMsgs = false;
    let startingCall = false;
    let currentAudio = null;
    let currentAudioUrl = null;
    let playGeneration = 0;
    const MAX_RECORD_MS = 20 * 60 * 1000;
    const MAX_RECORD_BYTES = 20 * 1024 * 1024;
    let chatTitle = document.getElementById('chatTitle').textContent || 'Beszélgetés';
    let playingVoice = null;

    function fmtDur(ms) {
      const s = Math.max(0, Math.round((ms||0)/1000));
      const m = Math.floor(s/60);
      const r = String(s%60).padStart(2,'0');
      return m+':'+r;
    }

    function stopAudio() {
      playGeneration++;
      if (playingVoice) {
        playingVoice.classList.remove('playing');
        const play = playingVoice.querySelector('.play');
        if (play) play.textContent = '▶';
        playingVoice = null;
      }
      if (currentAudio) {
        currentAudio.pause();
        currentAudio.src = '';
        currentAudio = null;
      }
      if (currentAudioUrl) {
        URL.revokeObjectURL(currentAudioUrl);
        currentAudioUrl = null;
      }
    }

    async function playMsg(url, messageId, voiceNode) {
      if (!url || !url.startsWith('/api/messages/audio/')) throw new Error('Érvénytelen hang');
      if (playingVoice === voiceNode && currentAudio) {
        stopAudio();
        return;
      }
      stopAudio();
      playingVoice = voiceNode;
      voiceNode.classList.add('playing');
      const playIcon = voiceNode.querySelector('.play');
      if (playIcon) playIcon.textContent = 'Ⅱ';
      const generation = playGeneration;
      const res = await fetch(url, { credentials: 'include', headers: { 'X-Client': 'web' } });
      if (!res.ok) throw new Error('Lejátszás sikertelen');
      const blob = await res.blob();
      const obj = URL.createObjectURL(blob);
      if (generation !== playGeneration) {
        URL.revokeObjectURL(obj);
        return;
      }
      const audio = new Audio(obj);
      currentAudio = audio;
      currentAudioUrl = obj;
      const cleanup = () => {
        if (currentAudio === audio) currentAudio = null;
        if (currentAudioUrl === obj) currentAudioUrl = null;
        if (playingVoice === voiceNode) {
          voiceNode.classList.remove('playing');
          if (playIcon) playIcon.textContent = '▶';
          playingVoice = null;
        }
        URL.revokeObjectURL(obj);
      };
      audio.addEventListener('ended', cleanup, { once: true });
      audio.addEventListener('error', cleanup, { once: true });
      try {
        await audio.play();
        if (generation !== playGeneration) {
          cleanup();
          return;
        }
        await api('/api/messages/'+conversationId+'/read', { method:'POST', json: {} });
      } catch (e) {
        cleanup();
        throw e;
      }
    }

    function callLabel(m) {
      const video = m.callType === 'video';
      const kind = video ? 'Videóhívás' : 'Hanghívás';
      if (m.callStatus === 'ringing') return 'Csengő ' + (video ? 'videó' : 'hang') + 'hívás…';
      if (m.callStatus === 'active') return 'Folyamatban lévő ' + (video ? 'videó' : 'hang') + 'hívás…';
      if (m.callStatus === 'missed') return 'Nem fogadott ' + (video ? 'videó' : 'hang') + 'hívás';
      if (m.callStatus === 'ended') return kind + ' · ' + fmtDur(m.durationMs);
      return kind;
    }

    async function loadMsgs() {
      if (loadingMsgs) return;
      loadingMsgs = true;
      const status = document.getElementById('status');
      const box = document.getElementById('msgs');
      try {
        const data = await api('/api/messages/'+conversationId);
        const msgs = data.messages || [];
        status.textContent = msgs.length ? '' : 'Még nincs hangüzenet.';
        box.replaceChildren();
        for (const m of msgs) {
          const div = document.createElement('div');
          const mine = m.senderId === meId;
          if (m.kind === 'call') {
            div.className = 'bubble'+(mine?' mine':'');
            div.style.textAlign = 'center';
            const label = document.createElement('div');
            label.style.fontWeight = '700';
            label.textContent = (mine ? 'Te' : (m.senderName || '')) + ' · ' + callLabel(m);
            const time = document.createElement('div');
            time.className = 'time';
            time.textContent = new Date(m.createdAt).toLocaleString('hu-HU');
            div.appendChild(label);
            div.appendChild(time);
            box.appendChild(div);
            continue;
          }
          div.className = 'bubble'+(mine?' mine':'')+(m.unread?' unread':'');
          const who = document.createElement('div');
          who.className = 'who';
          who.textContent = m.senderName || '';
          const voice = document.createElement('div');
          voice.className = 'voice-bubble';
          voice.dataset.messageId = String(m.id || '');
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'play';
          btn.textContent = '▶';
          const wave = document.createElement('span');
          wave.className = 'wave';
          const bars = Array.isArray(m.waveBars) && m.waveBars.length
            ? m.waveBars
            : Array.from({ length: 32 }, (_, i) => 0.25 + ((i * 17) % 60) / 100);
          bars.slice(0, 48).forEach((value) => {
            const bar = document.createElement('i');
            const height = Math.max(0.15, Math.min(1, Number(value) || 0.2));
            bar.style.height = Math.round(height * 100) + '%';
            wave.appendChild(bar);
          });
          const duration = document.createElement('span');
          duration.className = 'duration';
          duration.textContent = fmtDur(m.durationMs);
          const url = String(m.url || '');
          btn.onclick = () => playMsg(url, String(m.id || ''), voice)
            .catch(e => alert(e.message || 'Hiba'));
          const time = document.createElement('div');
          time.className = 'time';
          time.textContent = new Date(m.createdAt).toLocaleString('hu-HU');
          div.appendChild(who);
          voice.appendChild(btn);
          voice.appendChild(wave);
          voice.appendChild(duration);
          div.appendChild(voice);
          div.appendChild(time);
          box.appendChild(div);
        }
      } catch (e) {
        status.textContent = e.message || 'Hiba';
      } finally {
        loadingMsgs = false;
      }
    }

    async function startCall(type) {
      if (startingCall) return;
      startingCall = true;
      try {
        const data = await api('/api/calls/start', {
          method: 'POST',
          json: { conversationId, callType: type },
        });
        const call = data.call;
        // Token stays in memory / join API — never put JWT in the URL.
        location.href = '/app/call/' + encodeURIComponent(call.id) +
          '?type=' + encodeURIComponent(call.callType === 'video' ? 'video' : 'audio');
      } catch (e) {
        alert(e.message || 'Hívás indítása sikertelen');
      } finally {
        startingCall = false;
      }
    }

    document.getElementById('btnAudio').onclick = () => startCall('audio');
    document.getElementById('btnVideo').onclick = () => startCall('video');

    const recBtn = document.getElementById('recBtn');
    const recHint = document.getElementById('recHint');
    recBtn.onclick = async () => {
      if (!recording) {
        if (sending) return;
        let stream = null;
        try {
          stream = await navigator.mediaDevices.getUserMedia({ audio: true });
          chunks = [];
          recordedBytes = 0;
          recordTooLarge = false;
          mediaRecorder = new MediaRecorder(stream);
          mediaRecorder.ondataavailable = (e) => {
            if (!e.data.size) return;
            recordedBytes += e.data.size;
            if (recordedBytes > MAX_RECORD_BYTES) {
              recordTooLarge = true;
              if (mediaRecorder && mediaRecorder.state === 'recording') mediaRecorder.stop();
              return;
            }
            chunks.push(e.data);
          };
          mediaRecorder.onstop = async () => {
            clearTimeout(recordTimer);
            recordTimer = null;
            stream.getTracks().forEach(t => t.stop());
            recording = false;
            recBtn.textContent = 'Felvétel';
            if (recordTooLarge) {
              chunks = [];
              recHint.textContent = 'A felvétel túl nagy (max. 20 MB)';
              return;
            }
            const blob = new Blob(chunks, { type: mediaRecorder.mimeType || 'audio/webm' });
            chunks = [];
            mediaRecorder = null;
            if (!blob.size || blob.size > MAX_RECORD_BYTES) {
              recHint.textContent = 'A felvétel túl nagy vagy üres';
              return;
            }
            const durationMs = Date.now() - startedAt;
            sending = true;
            recBtn.disabled = true;
            try {
              await api('/api/messages/'+conversationId, {
                method: 'POST',
                headers: {
                  'Content-Type': blob.type || 'audio/webm',
                  'X-Duration-Ms': String(Math.min(durationMs, 20 * 60 * 1000)),
                },
                body: blob,
              });
              recHint.textContent = 'Elküldve';
              loadMsgs();
            } catch (e) {
              recHint.textContent = e.message || 'Küldés sikertelen';
            } finally {
              sending = false;
              recBtn.disabled = false;
            }
          };
          mediaRecorder.start(1000);
          recordTimer = setTimeout(() => {
            if (mediaRecorder && mediaRecorder.state === 'recording') mediaRecorder.stop();
          }, MAX_RECORD_MS);
          startedAt = Date.now();
          recording = true;
          recBtn.textContent = 'Stop + küldés';
          recHint.textContent = 'Felvétel…';
        } catch (e) {
          if (stream) stream.getTracks().forEach(t => t.stop());
          alert('Mikrofon nem elérhető');
        }
      } else {
        recording = false;
        clearTimeout(recordTimer);
        recordTimer = null;
        recBtn.textContent = 'Felvétel';
        mediaRecorder && mediaRecorder.stop();
      }
    };

    loadMsgs();
    connectRealtime((ev) => {
      if (ev.type === 'message_created' && ev.conversationId === conversationId) loadMsgs();
      if (ev.type === 'call_updated' || ev.type === 'call_ended') loadMsgs();
    });
    setInterval(loadMsgs, 30000);
    </script>
  `,
  );
}

export function appCallPage(
  user: UserRow,
  opts: {
    callId: string;
    callType: "audio" | "video";
    title: string;
  },
): string {
  const callId = safeId(opts.callId);
  if (!callId) {
    return appShell("Hiba", user, `<div class="inbox-panel"><p class="error">Érvénytelen hívás.</p></div>`);
  }
  return appShell(
    opts.title || "Hívás",
    user,
    `
    <div class="call-frame">
      <div class="call-head">
        <h1>${escape(opts.title || "Hívás")}</h1>
        <p class="hint">${opts.callType === "video" ? "Videóhívás" : "Hanghívás"}</p>
        <div id="status" class="hint">Csatlakozás…</div>
      </div>
      <div class="video-grid count-1" id="grid"></div>
      <div class="call-controls">
        <button type="button" id="micBtn" class="call-round-action">
          <span class="round-icon">♩</span><span class="round-label">Mikrofon</span>
        </button>
        <button type="button" id="camBtn" class="call-round-action" ${opts.callType === "video" ? "" : "disabled"}>
          <span class="round-icon">◉</span><span class="round-label">Kamera</span>
        </button>
        <button type="button" id="switchCamBtn" class="call-round-action" ${opts.callType === "video" ? "" : "disabled"}>
          <span class="round-icon">↻</span><span class="round-label">Váltás</span>
        </button>
        <button type="button" id="screenBtn" class="call-round-action">
          <span class="round-icon">▣</span><span class="round-label">Kijelző</span>
        </button>
        <button type="button" id="endBtn" class="call-round-action danger">
          <span class="round-icon">×</span><span class="round-label">Bontás</span>
        </button>
      </div>
    </div>
    <script>
    ${clientHelpers}
    const callId = ${JSON.stringify(callId)};
    const isVideo = ${opts.callType === "video" ? "true" : "false"};
    let room = null;
    let callMode = 'group';
    let micOn = true;
    let camOn = isVideo;
    let screenOn = false;
    let ending = false;
    let talkStartedAt = null;
    let talkTimer = null;
    const participantTiles = new Map();
    const attachedTracks = new WeakSet();
    const grid = document.getElementById('grid');
    const statusEl = document.getElementById('status');

    function setCallLabel(id, icon, label) {
      const button = document.getElementById(id);
      if (!button) return;
      const iconEl = button.querySelector('.round-icon');
      const labelEl = button.querySelector('.round-label');
      if (iconEl) iconEl.textContent = icon;
      if (labelEl) labelEl.textContent = label;
    }

    function fmtTalk(ms) {
      const s = Math.max(0, Math.round(ms/1000));
      return Math.floor(s/60) + ':' + String(s%60).padStart(2,'0');
    }

    function maybeStartTalkTimer() {
      if (talkStartedAt || !room) return;
      if (!room.remoteParticipants || room.remoteParticipants.size < 1) return;
      talkStartedAt = Date.now();
      talkTimer = setInterval(() => {
        statusEl.textContent = 'Kapcsolódva · ' + fmtTalk(Date.now() - talkStartedAt);
      }, 1000);
      statusEl.textContent = 'Kapcsolódva · 0:00';
    }

    function uniqueParticipants() {
      if (!room) return [];
      const byId = new Map();
      const local = room.localParticipant;
      if (local && local.identity) byId.set(String(local.identity), local);
      for (const p of room.remoteParticipants.values()) {
        const id = String(p.identity || '');
        if (!id || byId.has(id)) continue;
        byId.set(id, p);
      }
      return Array.from(byId.values());
    }

    function isDirectCall() {
      return callMode === 'direct' || uniqueParticipants().length <= 2;
    }

    function ensureTile(participant) {
      const id = String(participant?.identity || '');
      if (!id) return null;
      let tile = participantTiles.get(id);
      if (tile) return tile;
      tile = document.createElement('div');
      tile.className = 'lk-tile';
      const media = document.createElement('div');
      media.className = 'lk-media';
      const name = document.createElement('span');
      name.className = 'lk-name';
      const label = participant.name || id;
      const isLocal = participant === room?.localParticipant;
      name.textContent = isLocal ? (label + ' (te)') : label;
      tile.appendChild(media);
      tile.appendChild(name);
      tile.media = media;
      tile.tracks = new Map();
      tile.identity = id;
      participantTiles.set(id, tile);
      return tile;
    }

    function renderGrid() {
      if (!room) return;
      const local = room.localParticipant;
      const localId = local ? String(local.identity) : '';
      let people = uniqueParticipants();
      people.sort((a, b) => {
        const aLocal = a === local;
        const bLocal = b === local;
        if (aLocal !== bLocal) return aLocal ? 1 : -1; // remote first for 1:1 spotlight
        return String(a.identity).localeCompare(String(b.identity));
      });
      if (isDirectCall()) people = people.slice(0, 2);

      const n = Math.max(1, Math.min(6, people.length));
      grid.className = 'video-grid count-' + n;
      const tiles = people.map((p) => {
        const tile = ensureTile(p);
        if (!tile) return null;
        const localTile = p === local || String(p.identity) === localId;
        tile.classList.toggle('local', localTile);
        tile.classList.toggle('remote', !localTile);
        return tile;
      }).filter(Boolean);
      grid.replaceChildren(...tiles);

      const visibleIds = new Set(people.map((p) => String(p.identity)));
      for (const [id, tile] of [...participantTiles.entries()]) {
        if (visibleIds.has(id)) continue;
        tile.tracks.forEach((node, track) => {
          try { track.detach(); } catch {}
          node.remove();
          attachedTracks.delete?.(track);
        });
        participantTiles.delete(id);
      }
    }

    function setActiveSpeakers(speakers) {
      const ids = new Set((speakers || []).map((p) => String(p.identity)));
      participantTiles.forEach((tile) => tile.classList.toggle('active', ids.has(tile.identity)));
    }

    function attachTrack(track, participant) {
      if (!track || !participant) return;
      if (attachedTracks.has(track)) {
        renderGrid();
        return;
      }
      const tile = ensureTile(participant);
      if (!tile) return;
      if (tile.tracks.has(track)) {
        renderGrid();
        return;
      }
      attachedTracks.add(track);
      if (track.kind === 'audio') {
        if (participant === room.localParticipant) {
          renderGrid();
          return; // no local echo
        }
        const a = track.attach();
        a.autoplay = true;
        a.playsInline = true;
        tile.media.appendChild(a);
        tile.tracks.set(track, a);
      } else if (track.kind === 'video') {
        // One video element per tile (camera only — skip duplicate pubs).
        for (const [existing, node] of [...tile.tracks.entries()]) {
          if (existing.kind === 'video') {
            try { existing.detach(); } catch {}
            node.remove();
            tile.tracks.delete(existing);
            attachedTracks.delete?.(existing);
          }
        }
        const v = track.attach();
        v.autoplay = true;
        v.playsInline = true;
        v.muted = participant === room.localParticipant;
        tile.media.appendChild(v);
        tile.tracks.set(track, v);
      }
      renderGrid();
    }

    function detachTrack(track, participant) {
      const id = String(participant?.identity || '');
      const tile = participantTiles.get(id);
      try { track.detach().forEach((node) => node.remove()); } catch {}
      if (tile) tile.tracks.delete(track);
      try { attachedTracks.delete(track); } catch {}
      renderGrid();
    }

    async function endEverywhere() {
      if (ending) return;
      ending = true;
      try {
        await api('/api/calls/'+callId+'/end', { method:'POST', json: {} });
      } catch {}
      try { await room?.disconnect(); } catch {}
      location.href = '/app';
    }

    async function leaveOrEnd() {
      if (ending) return;
      if (isDirectCall()) {
        await endEverywhere();
        return;
      }
      ending = true;
      try {
        await api('/api/calls/'+callId+'/leave', { method:'POST', json: {} });
      } catch {
        try { await api('/api/calls/'+callId+'/end', { method:'POST', json: {} }); } catch {}
      }
      try { await room?.disconnect(); } catch {}
      location.href = '/app';
    }

    function onRemoteLeft() {
      if (!room || ending) return;
      if (room.remoteParticipants.size > 0) return;
      statusEl.textContent = 'A másik fél kilépett';
      endEverywhere();
    }

    function loadSdk(cb) {
      if (window.LivekitClient) return cb();
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/livekit-client@2.10.0/dist/livekit-client.umd.min.js';
      s.crossOrigin = 'anonymous';
      s.onload = cb;
      s.onerror = () => { document.getElementById('status').textContent = 'LiveKit SDK betöltése sikertelen'; };
      document.head.appendChild(s);
    }
    loadSdk(connect);

    async function connect() {
      const status = document.getElementById('status');
      const Livekit = window.LivekitClient;
      if (!Livekit) {
        status.textContent = 'LiveKit SDK hiányzik.';
        return;
      }
      try {
        const data = await api('/api/calls/' + callId + '/join', { method: 'POST', json: {} });
        const call = data.call;
        callMode = call.mode === 'direct' ? 'direct' : 'group';
        const livekitUrl = call.livekitUrl;
        const token = call.token;
        if (!livekitUrl || !token) throw new Error('Hiányzó hívási adatok');

        room = new Livekit.Room({ adaptiveStream: true, dynacast: true });
        room.on(Livekit.RoomEvent.TrackSubscribed, (track, publication, participant) => {
          attachTrack(track, participant || publication?.participant);
        });
        room.on(Livekit.RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
          detachTrack(track, participant || publication?.participant);
        });
        room.on(Livekit.RoomEvent.LocalTrackPublished, (publication, participant) => {
          if (publication?.track) attachTrack(publication.track, participant || room.localParticipant);
        });
        room.on(Livekit.RoomEvent.ParticipantConnected, () => {
          renderGrid();
          maybeStartTalkTimer();
        });
        room.on(Livekit.RoomEvent.ParticipantDisconnected, () => {
          renderGrid();
          onRemoteLeft();
        });
        room.on(Livekit.RoomEvent.ActiveSpeakersChanged, setActiveSpeakers);
        room.on(Livekit.RoomEvent.Disconnected, () => {
          if (talkTimer) clearInterval(talkTimer);
          if (!ending) {
            status.textContent = 'Lecsatlakozva';
            // Room torn down by peer/end — leave the page.
            ending = true;
            location.href = '/app';
            return;
          }
          renderGrid();
        });
        await room.connect(livekitUrl, token);
        await room.localParticipant.setMicrophoneEnabled(true);
        if (isVideo) await room.localParticipant.setCameraEnabled(true);
        // Local tracks come via LocalTrackPublished — do not double-attach here.
        renderGrid();
        if (room.remoteParticipants.size > 0) {
          maybeStartTalkTimer();
        } else {
          status.textContent = 'Cseng…';
        }
      } catch (e) {
        try { await room?.disconnect(); } catch {}
        room = null;
        status.textContent = e.message || 'Csatlakozási hiba';
      }
    }

    window.addEventListener('pagehide', () => {
      try { room?.disconnect(); } catch {}
    });

    document.getElementById('micBtn').onclick = async () => {
      micOn = !micOn;
      try {
        if (room) await room.localParticipant.setMicrophoneEnabled(micOn);
        setCallLabel('micBtn', micOn ? '♩' : '−', micOn ? 'Mikrofon' : 'Némítva');
      } catch {
        micOn = !micOn;
      }
    };
    document.getElementById('camBtn').onclick = async () => {
      if (!isVideo) return;
      camOn = !camOn;
      try {
        if (room) await room.localParticipant.setCameraEnabled(camOn);
        setCallLabel('camBtn', camOn ? '◉' : '−', camOn ? 'Kamera' : 'Kamera ki');
      } catch {
        camOn = !camOn;
      }
    };
    document.getElementById('switchCamBtn').onclick = async () => {
      if (!isVideo || !room) return;
      try {
        const devices = (await navigator.mediaDevices.enumerateDevices())
          .filter((device) => device.kind === 'videoinput' && device.deviceId);
        if (devices.length < 2) return;
        const current = room.localParticipant.getTrackPublication?.('camera')?.track;
        const currentId = current?.mediaStreamTrack?.getSettings?.().deviceId;
        const index = Math.max(0, devices.findIndex((device) => device.deviceId === currentId));
        const next = devices[(index + 1) % devices.length];
        await room.switchActiveDevice('videoinput', next.deviceId);
      } catch {
        statusEl.textContent = 'A kamera váltása nem sikerült';
      }
    };
    document.getElementById('screenBtn').onclick = async () => {
      if (!room) return;
      try {
        await room.localParticipant.setScreenShareEnabled(!screenOn);
        screenOn = !screenOn;
        setCallLabel('screenBtn', screenOn ? '■' : '▣', screenOn ? 'Megosztás be' : 'Kijelző');
      } catch {
        statusEl.textContent = 'A kijelző megosztása nem sikerült';
      }
    };
    document.getElementById('endBtn').onclick = () => leaveOrEnd();
    </script>
  `,
    { fill: true, hideNav: true },
  );
}

export function userQrPage(opts: {
  userId: string;
  meId: string | null;
  loggedIn: boolean;
}): string {
  const id = safeId(opts.userId) || escape(opts.userId);
  return layout(
    "QR kapcsolat",
    `
    <div class="page">
      <header class="page-top">
        <a class="logo" href="/">MyÜzi</a>
        <nav class="page-nav">
          ${
            opts.loggedIn
              ? `<a href="/app"><button class="secondary" type="button">Beszélgetések</button></a>`
              : `<a href="/login"><button type="button">Belépés</button></a>`
          }
        </nav>
      </header>
      <main class="page-body">
        <div class="qr-stage">
          <h1 class="brand-mark">Kapcsolat</h1>
          <p class="sub">QR kód / felhasználói link</p>
          <div class="panel" style="width:min(420px,100%)">
            <p class="hint">Azonosító: <code>${escape(id)}</code></p>
            ${
              opts.loggedIn
                ? opts.meId === opts.userId
                  ? `<p class="ok">Ez a te QR kódod. Mutasd meg családtagodnak az appban.</p>
                     <a href="/app"><button type="button">Beszélgetések</button></a>`
                  : `<p>Nyisd meg a MyÜzi appot, és olvasd be ezt a QR-t a + menüből.</p>
                     <a href="/app"><button type="button">Tovább a beszélgetésekhez</button></a>`
                : `<a href="/login"><button type="button">Belépés</button></a>`
            }
          </div>
        </div>
      </main>
    </div>
  `,
    { variant: "page" },
  );
}
