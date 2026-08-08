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
  return layout(
    title,
    `
    <style>${appCss}</style>
    <div class="app-frame">
      ${
        hideNav
          ? ""
          : `<header class="app-top">
        <a class="logo" href="/">MyÜzi</a>
        <nav class="app-top-nav">
          <a href="/app"><button class="secondary" type="button">Beszélgetések</button></a>
          <a href="/account"><button class="ghost" type="button">Fiók</button></a>
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
          const a = document.createElement('a');
          a.href = '/app/chat/' + encodeURIComponent(id);
          const left = document.createElement('span');
          const strong = document.createElement('strong');
          strong.textContent = c.name || 'Beszélgetés';
          left.appendChild(strong);
          left.appendChild(document.createElement('br'));
          const hint = document.createElement('span');
          hint.className = 'hint';
          hint.textContent = c.lastSenderName ? (c.lastSenderName + ': hangüzenet') : '';
          left.appendChild(hint);
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

    function fmtDur(ms) {
      const s = Math.max(0, Math.round((ms||0)/1000));
      const m = Math.floor(s/60);
      const r = String(s%60).padStart(2,'0');
      return m+':'+r;
    }

    function stopAudio() {
      playGeneration++;
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

    async function playMsg(url) {
      if (!url || !url.startsWith('/api/messages/audio/')) throw new Error('Érvénytelen hang');
      stopAudio();
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
          const btn = document.createElement('button');
          btn.type = 'button';
          btn.textContent = '▶ ' + fmtDur(m.durationMs);
          const url = String(m.url || '');
          btn.onclick = () => playMsg(url).catch(e => alert(e.message || 'Hiba'));
          const time = document.createElement('div');
          time.className = 'time';
          time.textContent = new Date(m.createdAt).toLocaleString('hu-HU');
          div.appendChild(who);
          div.appendChild(btn);
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
        <button type="button" id="micBtn" class="secondary">Mikrofon</button>
        <button type="button" id="camBtn" class="secondary" ${opts.callType === "video" ? "" : "disabled"}>Kamera</button>
        <button type="button" id="endBtn" class="danger">Befejezés</button>
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
    let ending = false;
    let talkStartedAt = null;
    let talkTimer = null;
    const participantTiles = new Map();
    const attachedTracks = new WeakSet();
    const grid = document.getElementById('grid');
    const statusEl = document.getElementById('status');

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
        document.getElementById('micBtn').textContent = micOn ? 'Mikrofon' : 'Mikrofon ki';
      } catch {
        micOn = !micOn;
      }
    };
    document.getElementById('camBtn').onclick = async () => {
      if (!isVideo) return;
      camOn = !camOn;
      try {
        if (room) await room.localParticipant.setCameraEnabled(camOn);
        document.getElementById('camBtn').textContent = camOn ? 'Kamera' : 'Kamera ki';
      } catch {
        camOn = !camOn;
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
