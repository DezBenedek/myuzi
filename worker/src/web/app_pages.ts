import type { UserRow } from "../types";
import { layout } from "./pages";

function escape(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
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

function appShell(title: string, user: UserRow, body: string, extraHead = ""): string {
  return layout(
    title,
    `
    <style>${appCss}</style>
    ${extraHead}
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
    async function api(path, opts={}) {
      const res = await fetch(path, {
        credentials: 'include',
        headers: { 'Content-Type': 'application/json', 'X-Client': 'web', ...(opts.headers||{}) },
        ...opts,
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || ('Hiba ' + res.status));
      return body;
    }
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
          list.innerHTML = '';
          return;
        }
        status.textContent = '';
        list.innerHTML = chats.map(c => {
          const badge = c.unreadCount > 0 ? '<span class="badge">'+c.unreadCount+'</span>' : '';
          const q = encodeURIComponent(c.name || 'Beszélgetés');
          return '<li><a href="/app/chat/'+c.id+'?name='+q+'"><span><strong>'+
            (c.name||'Beszélgetés')+'</strong><br/><span class="hint">'+(c.lastSenderName? c.lastSenderName+': hangüzenet':'')+
            '</span></span><span class="meta">'+fmt(c.lastMessageAt)+'<br/>'+badge+'</span></a></li>';
        }).join('');
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
  const safeTitle = escape(title);
  return appShell(
    title,
    user,
    `
    <h1 class="brand" style="font-size:1.7rem">${safeTitle}</h1>
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
    const conversationId = ${JSON.stringify(conversationId)};
    const meId = ${JSON.stringify(user.id)};
    const chatTitle = ${JSON.stringify(title)};
    let mediaRecorder = null;
    let chunks = [];
    let recording = false;
    let startedAt = 0;

    async function api(path, opts={}) {
      const headers = { 'X-Client': 'web', ...(opts.headers||{}) };
      if (opts.json) headers['Content-Type'] = 'application/json';
      const res = await fetch(path, {
        credentials: 'include',
        method: opts.method || (opts.json || opts.body ? 'POST' : 'GET'),
        headers,
        body: opts.json ? JSON.stringify(opts.json) : opts.body,
      });
      const body = await res.json().catch(() => ({}));
      if (!res.ok) throw new Error(body.error || ('Hiba ' + res.status));
      return body;
    }

    function fmtDur(ms) {
      const s = Math.max(0, Math.round((ms||0)/1000));
      const m = Math.floor(s/60);
      const r = String(s%60).padStart(2,'0');
      return m+':'+r;
    }

    async function playMsg(url) {
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
        box.innerHTML = msgs.map(m => {
          const mine = m.senderId === meId;
          const cls = 'bubble'+(mine?' mine':'')+(m.unread?' unread':'');
          return '<div class="'+cls+'"><div class="who">'+m.senderName+'</div>'+
            '<button type="button" data-url="'+m.url+'" class="play">▶ '+fmtDur(m.durationMs)+'</button>'+
            '<div class="time">'+new Date(m.createdAt).toLocaleString('hu-HU')+'</div></div>';
        }).join('');
        box.querySelectorAll('button.play').forEach(btn => {
          btn.onclick = () => playMsg(btn.dataset.url).catch(e => alert(e.message || 'Hiba'));
        });
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
        const q = new URLSearchParams({
          url: call.livekitUrl,
          token: call.token,
          type: call.callType,
          title: chatTitle,
        });
        location.href = '/app/call/'+call.id+'?'+q.toString();
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
                  'X-Duration-Ms': String(durationMs),
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
    livekitUrl: string;
    token: string;
    callType: "audio" | "video";
    title: string;
  },
): string {
  return appShell(
    opts.title,
    user,
    `
    <h1 class="brand" style="font-size:1.6rem">${escape(opts.title)}</h1>
    <p class="hint">${opts.callType === "video" ? "Videóhívás" : "Hanghívás"}</p>
    <div id="status" class="hint">Csatlakozás…</div>
    <div class="video-grid" id="grid"></div>
    <div class="call-controls">
      <button type="button" id="micBtn" class="secondary">Mikrofon</button>
      <button type="button" id="camBtn" class="secondary" ${opts.callType === "video" ? "" : "disabled"}>Kamera</button>
      <button type="button" id="endBtn" style="background:var(--danger)">Befejezés</button>
    </div>
    <script src="https://cdn.jsdelivr.net/npm/livekit-client@2.9.1/dist/livekit-client.umd.min.js"></script>
    <script>
    const callId = ${JSON.stringify(opts.callId)};
    const livekitUrl = ${JSON.stringify(opts.livekitUrl)};
    const token = ${JSON.stringify(opts.token)};
    const isVideo = ${opts.callType === "video" ? "true" : "false"};
    const Livekit = window.LivekitClient;
    let room = null;
    let micOn = true;
    let camOn = isVideo;

    function el(tag, attrs={}) {
      const n = document.createElement(tag);
      Object.assign(n, attrs);
      return n;
    }

    function attachTrack(track, container) {
      if (track.kind === 'audio' && track.sid) {
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
        v.muted = track.participant && track.participant.isLocal;
        container.appendChild(v);
      }
    }

    async function connect() {
      const status = document.getElementById('status');
      const grid = document.getElementById('grid');
      if (!token || !Livekit) {
        status.textContent = 'Hiányzó hívási token vagy LiveKit SDK.';
        return;
      }
      try {
        room = new Livekit.Room({ adaptiveStream: true, dynacast: true });
        room.on(Livekit.RoomEvent.TrackSubscribed, (track, pub, participant) => {
          const tile = el('div');
          tile.dataset.identity = participant.identity;
          attachTrack(track, tile);
          grid.appendChild(tile);
        });
        room.on(Livekit.RoomEvent.TrackUnsubscribed, (track) => track.detach().forEach(n => n.remove()));
        room.on(Livekit.RoomEvent.Disconnected, () => { status.textContent = 'Lecsatlakozva'; });
        await room.connect(livekitUrl, token);
        await room.localParticipant.setMicrophoneEnabled(true);
        if (isVideo) await room.localParticipant.setCameraEnabled(true);
        // local video
        room.localParticipant.videoTrackPublications.forEach(pub => {
          if (pub.track) {
            const tile = el('div');
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
        await fetch('/api/calls/'+callId+'/end', {
          method:'POST', credentials:'include',
          headers:{'Content-Type':'application/json','X-Client':'web'},
          body:'{}'
        });
      } catch {}
      try { await room?.disconnect(); } catch {}
      location.href = '/app';
    };
    connect();
    </script>
  `,
  );
}

export function userQrPage(opts: {
  userId: string;
  meId: string | null;
  loggedIn: boolean;
}): string {
  return layout(
    "QR kapcsolat",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">QR kód / felhasználói link</p>
    <div class="panel">
      <p class="hint">Azonosító: <code>${escape(opts.userId)}</code></p>
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
