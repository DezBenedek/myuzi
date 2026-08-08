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
.nav { display:flex; gap:10px; flex-wrap:wrap; margin:0 0 18px; }
.nav a { text-decoration:none; }
.chat-list { list-style:none; padding:0; margin:0; }
.chat-list li a {
  display:flex; justify-content:space-between; gap:12px; align-items:center;
  padding:14px 0; border-bottom:1px solid var(--line); color:inherit; text-decoration:none;
}
.chat-list .meta { color:var(--muted); font-size:0.9rem; text-align:right; }
.badge {
  display:inline-block; min-width:22px; padding:2px 8px; border-radius:999px;
  background:var(--brand); color:#fff; font-weight:800; font-size:0.8rem; text-align:center;
}
.msgs { display:flex; flex-direction:column; gap:12px; min-height:40vh; margin:12px 0 18px; }
.bubble {
  max-width:85%; padding:12px 14px; border-radius:16px; background:#e8f3ee;
  border:1px solid var(--line);
}
.bubble.mine { align-self:flex-end; background:#d9f2e6; }
.bubble.unread { background:#fff6c8; border-color:#e6d56a; }
.bubble .who { font-weight:700; margin-bottom:4px; }
.bubble .time { color:var(--muted); font-size:0.85rem; margin-top:6px; }
.composer { display:flex; gap:10px; align-items:center; flex-wrap:wrap; }
.composer button { margin-top:0; width:auto; min-width:120px; }
#recHint { color:var(--muted); font-weight:650; }
.video-grid {
  display:grid; grid-template-columns:1fr; gap:10px; min-height:50vh;
  background:#0b1a14; border-radius:16px; padding:10px; margin:12px 0;
}
.video-grid video, .video-grid .lk-tile {
  width:100%; min-height:220px; background:#12261c; border-radius:12px; object-fit:cover;
}
.call-controls { display:flex; gap:10px; flex-wrap:wrap; }
.call-controls button { width:auto; flex:1; min-width:110px; margin-top:0; }
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
  const res = await fetch(path, {
    credentials: 'include',
    method: opts.method || (opts.json !== undefined || opts.body ? 'POST' : 'GET'),
    headers,
    body: opts.json !== undefined ? JSON.stringify(opts.json) : opts.body,
  });
  const body = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(body.error || ('Hiba ' + res.status));
  return body;
}
`;

function appShell(title: string, user: UserRow, body: string): string {
  return layout(
    title,
    `
    <style>${appCss}</style>
    <div class="nav">
      <a href="/app"><button class="secondary" type="button" style="margin:0;width:auto;padding:10px 14px">Beszélgetések</button></a>
      <a href="/account"><button class="ghost" type="button" style="margin:0;width:auto;padding:10px 14px">Fiók</button></a>
    </div>
    <p class="hint" style="margin-top:0">Bejelentkezve: ${escape(user.name)}</p>
    ${body}
  `,
    !!user.vision_assist,
  );
}

export function appInboxPage(user: UserRow): string {
  return appShell(
    "Beszélgetések",
    user,
    `
    <h1 class="brand" style="font-size:2rem">Beszélgetések</h1>
    <p class="sub">Hangüzenetek és hívások a böngészőben.</p>
    <div class="panel">
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
    async function load() {
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
      }
    }
    load();
    setInterval(load, 8000);
    </script>
  `,
  );
}

export function appChatPage(user: UserRow, conversationId: string, title: string): string {
  const id = safeId(conversationId);
  if (!id) {
    return appShell("Hiba", user, `<div class="panel"><p class="error">Érvénytelen beszélgetés.</p></div>`);
  }
  const safeTitle = escape(title || "Beszélgetés");
  return appShell(
    title || "Beszélgetés",
    user,
    `
    <h1 class="brand" style="font-size:1.7rem" id="chatTitle">${safeTitle}</h1>
    <div class="row" style="margin-bottom:10px">
      <button type="button" id="btnAudio" class="secondary">Hanghívás</button>
      <button type="button" id="btnVideo">Videóhívás</button>
    </div>
    <div class="panel">
      <div id="status" class="hint">Betöltés…</div>
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
    let chatTitle = document.getElementById('chatTitle').textContent || 'Beszélgetés';

    function fmtDur(ms) {
      const s = Math.max(0, Math.round((ms||0)/1000));
      const m = Math.floor(s/60);
      const r = String(s%60).padStart(2,'0');
      return m+':'+r;
    }

    async function playMsg(url) {
      if (!url || !url.startsWith('/api/messages/audio/')) throw new Error('Érvénytelen hang');
      const res = await fetch(url, { credentials: 'include', headers: { 'X-Client': 'web' } });
      if (!res.ok) throw new Error('Lejátszás sikertelen');
      const blob = await res.blob();
      const obj = URL.createObjectURL(blob);
      const audio = new Audio(obj);
      await audio.play();
      await api('/api/messages/'+conversationId+'/read', { method:'POST', json: {} });
    }

    async function loadMsgs() {
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
      }
    }

    async function startCall(type) {
      try {
        const data = await api('/api/calls/start', {
          method: 'POST',
          json: { conversationId, callType: type },
        });
        const call = data.call;
        // Token stays in memory / join API — never put JWT in the URL.
        sessionStorage.setItem('myuzi_call_' + call.id, JSON.stringify({
          callType: call.callType,
          title: chatTitle,
        }));
        location.href = '/app/call/' + encodeURIComponent(call.id) +
          '?type=' + encodeURIComponent(call.callType === 'video' ? 'video' : 'audio');
      } catch (e) {
        alert(e.message || 'Hívás indítása sikertelen');
      }
    }

    document.getElementById('btnAudio').onclick = () => startCall('audio');
    document.getElementById('btnVideo').onclick = () => startCall('video');

    const recBtn = document.getElementById('recBtn');
    const recHint = document.getElementById('recHint');
    recBtn.onclick = async () => {
      if (!recording) {
        try {
          const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
          chunks = [];
          mediaRecorder = new MediaRecorder(stream);
          mediaRecorder.ondataavailable = (e) => { if (e.data.size) chunks.push(e.data); };
          mediaRecorder.onstop = async () => {
            stream.getTracks().forEach(t => t.stop());
            const blob = new Blob(chunks, { type: mediaRecorder.mimeType || 'audio/webm' });
            const durationMs = Date.now() - startedAt;
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
            }
          };
          mediaRecorder.start();
          startedAt = Date.now();
          recording = true;
          recBtn.textContent = 'Stop + küldés';
          recHint.textContent = 'Felvétel…';
        } catch (e) {
          alert('Mikrofon nem elérhető');
        }
      } else {
        recording = false;
        recBtn.textContent = 'Felvétel';
        mediaRecorder && mediaRecorder.stop();
      }
    };

    loadMsgs();
    setInterval(loadMsgs, 5000);
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
    return appShell("Hiba", user, `<div class="panel"><p class="error">Érvénytelen hívás.</p></div>`);
  }
  return appShell(
    opts.title || "Hívás",
    user,
    `
    <h1 class="brand" style="font-size:1.6rem">${escape(opts.title || "Hívás")}</h1>
    <p class="hint">${opts.callType === "video" ? "Videóhívás" : "Hanghívás"}</p>
    <div id="status" class="hint">Csatlakozás…</div>
    <div class="video-grid" id="grid"></div>
    <div class="call-controls">
      <button type="button" id="micBtn" class="secondary">Mikrofon</button>
      <button type="button" id="camBtn" class="secondary" ${opts.callType === "video" ? "" : "disabled"}>Kamera</button>
      <button type="button" id="endBtn" style="background:var(--danger)">Befejezés</button>
    </div>
    <script>
    ${clientHelpers}
    const callId = ${JSON.stringify(callId)};
    const isVideo = ${opts.callType === "video" ? "true" : "false"};
    let room = null;
    let micOn = true;
    let camOn = isVideo;

    function loadSdk(cb) {
      if (window.LivekitClient) return cb();
      const s = document.createElement('script');
      s.src = 'https://cdn.jsdelivr.net/npm/livekit-client@2.9.1/dist/livekit-client.umd.min.js';
      s.crossOrigin = 'anonymous';
      s.onload = cb;
      s.onerror = () => { document.getElementById('status').textContent = 'LiveKit SDK betöltése sikertelen'; };
      document.head.appendChild(s);
    }
    loadSdk(connect);

    function attachTrack(track, container) {
      if (track.kind === 'audio') {
        const a = track.attach();
        a.autoplay = true;
        a.playsInline = true;
        container.appendChild(a);
        return;
      }
      if (track.kind === 'video') {
        const v = track.attach();
        v.autoplay = true;
        v.playsInline = true;
        container.appendChild(v);
      }
    }

    async function connect() {
      const status = document.getElementById('status');
      const grid = document.getElementById('grid');
      const Livekit = window.LivekitClient;
      if (!Livekit) {
        status.textContent = 'LiveKit SDK hiányzik.';
        return;
      }
      try {
        const data = await api('/api/calls/' + callId + '/join', { method: 'POST', json: {} });
        const call = data.call;
        const livekitUrl = call.livekitUrl;
        const token = call.token;
        if (!livekitUrl || !token) throw new Error('Hiányzó hívási adatok');

        room = new Livekit.Room({ adaptiveStream: true, dynacast: true });
        room.on(Livekit.RoomEvent.TrackSubscribed, (track) => {
          const tile = document.createElement('div');
          attachTrack(track, tile);
          grid.appendChild(tile);
        });
        room.on(Livekit.RoomEvent.TrackUnsubscribed, (track) => {
          track.detach().forEach(n => n.remove());
        });
        room.on(Livekit.RoomEvent.Disconnected, () => { status.textContent = 'Lecsatlakozva'; });
        await room.connect(livekitUrl, token);
        await room.localParticipant.setMicrophoneEnabled(true);
        if (isVideo) await room.localParticipant.setCameraEnabled(true);
        room.localParticipant.videoTrackPublications.forEach(pub => {
          if (pub.track) {
            const tile = document.createElement('div');
            attachTrack(pub.track, tile);
            grid.appendChild(tile);
          }
        });
        status.textContent = 'Kapcsolódva';
      } catch (e) {
        status.textContent = e.message || 'Csatlakozási hiba';
      }
    }

    document.getElementById('micBtn').onclick = async () => {
      micOn = !micOn;
      if (room) await room.localParticipant.setMicrophoneEnabled(micOn);
      document.getElementById('micBtn').textContent = micOn ? 'Mikrofon' : 'Mikrofon ki';
    };
    document.getElementById('camBtn').onclick = async () => {
      if (!isVideo) return;
      camOn = !camOn;
      if (room) await room.localParticipant.setCameraEnabled(camOn);
      document.getElementById('camBtn').textContent = camOn ? 'Kamera' : 'Kamera ki';
    };
    document.getElementById('endBtn').onclick = async () => {
      try {
        await api('/api/calls/'+callId+'/end', { method:'POST', json: {} });
      } catch {}
      try { await room?.disconnect(); } catch {}
      location.href = '/app';
    };
    </script>
  `,
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
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">QR kód / felhasználói link</p>
    <div class="panel">
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
  `,
  );
}
