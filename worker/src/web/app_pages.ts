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
  display:grid; grid-template-columns:repeat(2, minmax(0, 1fr)); gap:10px; min-height:50vh;
  background:#0b1a14; border-radius:16px; padding:10px; margin:12px 0;
}
.video-grid video, .video-grid .lk-tile {
  width:100%; min-height:220px; background:#12261c; border-radius:12px; object-fit:cover;
}
.video-grid .lk-tile { position:relative; overflow:hidden; border:1px solid transparent; }
.video-grid .lk-tile.active { border-color:#3ddc97; box-shadow:0 0 0 2px #3ddc9744; }
.video-grid .lk-tile .lk-name {
  position:absolute; left:8px; bottom:8px; padding:4px 8px; border-radius:8px;
  background:#0009; color:#fff; font-size:.85rem;
}
@media (min-width: 760px) {
  .video-grid { grid-template-columns:repeat(3, minmax(0, 1fr)); }
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
    let ending = false;
    const participantTiles = new Map();
    const trackOwners = new Map();
    const grid = document.getElementById('grid');

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
      name.textContent = participant.name || id;
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
      const participants = [
        room.localParticipant,
        ...Array.from(room.remoteParticipants.values()),
      ].filter(Boolean);
      participants.sort((a, b) => {
        if (a === room.localParticipant) return -1;
        if (b === room.localParticipant) return 1;
        return String(a.identity).localeCompare(String(b.identity));
      });
      const visible = participants.slice(0, 6);
      grid.replaceChildren(...visible.map((p) => ensureTile(p)));
      const visibleIds = new Set(visible.map((p) => String(p.identity)));
      for (const [id, tile] of participantTiles) {
        if (!visibleIds.has(id) && !room.remoteParticipants.get(id)) {
          tile.tracks.forEach((node, track) => {
            node.remove();
            trackOwners.delete(track);
          });
          participantTiles.delete(id);
        }
      }
    }

    function setActiveSpeakers(speakers) {
      const ids = new Set((speakers || []).map((p) => String(p.identity)));
      participantTiles.forEach((tile) => tile.classList.toggle('active', ids.has(tile.identity)));
    }

    function attachTrack(track, participant) {
      const tile = ensureTile(participant);
      if (!tile) return;
      trackOwners.set(track, tile.identity);
      if (track.kind === 'audio') {
        const a = track.attach();
        a.autoplay = true;
        a.playsInline = true;
        tile.media.appendChild(a);
        tile.tracks.set(track, a);
      } else if (track.kind === 'video') {
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
      const id = String(participant?.identity || trackOwners.get(track) || '');
      const tile = participantTiles.get(id);
      track.detach().forEach((node) => node.remove());
      if (tile) tile.tracks.delete(track);
      trackOwners.delete(track);
      renderGrid();
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
        room.on(Livekit.RoomEvent.TrackSubscribed, (track, publication, participant) => {
          attachTrack(track, participant || publication?.participant);
        });
        room.on(Livekit.RoomEvent.TrackUnsubscribed, (track, publication, participant) => {
          detachTrack(track, participant || publication?.participant);
        });
        room.on(Livekit.RoomEvent.LocalTrackPublished, (publication, participant) => {
          if (publication?.track) attachTrack(publication.track, participant || room.localParticipant);
        });
        room.on(Livekit.RoomEvent.ParticipantConnected, renderGrid);
        room.on(Livekit.RoomEvent.ParticipantDisconnected, renderGrid);
        room.on(Livekit.RoomEvent.ActiveSpeakersChanged, setActiveSpeakers);
        room.on(Livekit.RoomEvent.Disconnected, () => {
          status.textContent = 'Lecsatlakozva';
          renderGrid();
        });
        await room.connect(livekitUrl, token);
        await room.localParticipant.setMicrophoneEnabled(true);
        if (isVideo) await room.localParticipant.setCameraEnabled(true);
        room.localParticipant.videoTrackPublications.forEach(pub => {
          if (pub.track) {
            attachTrack(pub.track, room.localParticipant);
          }
        });
        renderGrid();
        status.textContent = 'Kapcsolódva';
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
    document.getElementById('endBtn').onclick = async () => {
      if (ending) return;
      ending = true;
      document.getElementById('endBtn').disabled = true;
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
