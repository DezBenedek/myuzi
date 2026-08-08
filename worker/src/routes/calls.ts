import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import {
  getUserFamily,
  hasPaidPlan,
  isConversationMember,
  isFamilyMember,
} from "../lib/db";
import { createLiveKitToken } from "../lib/livekit";
import {
  countLiveKitParticipants,
  deleteLiveKitRoom,
  ensureLiveKitRoom,
  removeLiveKitParticipant,
} from "../lib/livekit_rooms";
import { notifyConversationMembers } from "../lib/push";
import { publishToConversation } from "../lib/realtime";
import { readLimitedJson } from "../lib/body";
import { requireAuth } from "../middleware/auth";

const calls = new Hono<{ Bindings: Env; Variables: Variables }>();
calls.use("*", requireAuth);

const MAX_CALL_PARTICIPANTS = 6;

type CallMode = "direct" | "group";

type CallRow = {
  id: string;
  family_id: string;
  conversation_id: string | null;
  room_name: string;
  call_type: "audio" | "video";
  mode: CallMode;
  initiated_by: string;
  status: "ringing" | "active" | "ended";
  created_at: string;
  answered_at: string | null;
  event_message_id: string | null;
  ended_at?: string | null;
};

async function modeForConversation(
  db: D1Database,
  conversationId: string | null | undefined,
): Promise<CallMode> {
  if (!conversationId) return "group";
  const row = await db
    .prepare(
      `SELECT c.type AS type,
              (SELECT COUNT(*) FROM conversation_members cm WHERE cm.conversation_id = c.id) AS members
       FROM conversations c WHERE c.id = ?`,
    )
    .bind(conversationId)
    .first<{ type: string; members: number }>();
  if (!row) return "group";
  if (row.type === "direct" || Number(row.members) <= 2) return "direct";
  return "group";
}

function parseSqlTime(value: string): number {
  const raw = value.trim();
  if (!raw) return Date.now();
  if (raw.includes("T") || raw.endsWith("Z")) {
    const ms = Date.parse(raw);
    return Number.isFinite(ms) ? ms : Date.now();
  }
  const ms = Date.parse(raw.replace(" ", "T") + "Z");
  return Number.isFinite(ms) ? ms : Date.now();
}

function callDurationMs(answeredAt: string | null | undefined, endedAt?: string): number {
  if (!answeredAt) return 0;
  const start = parseSqlTime(answeredAt);
  const end = endedAt ? parseSqlTime(endedAt) : Date.now();
  return Math.max(0, Math.min(end - start, 12 * 60 * 60 * 1000));
}

function normalizeMode(value: unknown): CallMode {
  return value === "direct" ? "direct" : "group";
}

function publicCall(
  env: Env,
  call: CallRow,
  extra?: { token?: string; status?: string },
) {
  return {
    id: call.id,
    roomName: call.room_name,
    callType: call.call_type,
    mode: normalizeMode(call.mode),
    livekitUrl: env.LIVEKIT_URL,
    status: extra?.status ?? call.status,
    answeredAt: call.answered_at,
    ...(extra?.token ? { token: extra.token } : {}),
  };
}

async function createCallChatMessage(
  db: D1Database,
  opts: {
    conversationId: string;
    senderId: string;
    callId: string;
    callType: "audio" | "video";
  },
): Promise<string> {
  const messageId = id("msg");
  await db
    .prepare(
      `INSERT INTO voice_messages
         (id, conversation_id, sender_id, r2_key, duration_ms, wave_bars, kind, call_id, call_status, call_type)
       VALUES (?, ?, ?, '', 0, NULL, 'call', ?, 'ringing', ?)`,
    )
    .bind(messageId, opts.conversationId, opts.senderId, opts.callId, opts.callType)
    .run();
  await db
    .prepare(`UPDATE conversations SET updated_at = datetime('now') WHERE id = ?`)
    .bind(opts.conversationId)
    .run();
  return messageId;
}

async function setCallMessageStatus(
  db: D1Database,
  opts: {
    messageId: string | null | undefined;
    status: "ringing" | "active" | "missed" | "ended";
    durationMs?: number;
  },
): Promise<void> {
  if (!opts.messageId) return;
  await db
    .prepare(
      `UPDATE voice_messages
       SET call_status = ?, duration_ms = ?
       WHERE id = ? AND kind = 'call'`,
    )
    .bind(opts.status, opts.durationMs ?? 0, opts.messageId)
    .run();
}

async function finalizeCall(
  env: Env,
  call: CallRow,
): Promise<"missed" | "ended"> {
  const wasAnswered = call.status === "active" || !!call.answered_at;
  const outcome = wasAnswered ? "ended" : "missed";
  const durationMs = wasAnswered ? callDurationMs(call.answered_at) : 0;
  const endedAt = new Date().toISOString();

  await env.DB.prepare(
    `UPDATE calls
     SET status = 'ended', ended_at = ?
     WHERE id = ? AND status != 'ended'`,
  )
    .bind(endedAt, call.id)
    .run();

  await setCallMessageStatus(env.DB, {
    messageId: call.event_message_id,
    status: outcome,
    durationMs,
  });

  if (call.conversation_id) {
    await env.DB.prepare(`UPDATE conversations SET updated_at = datetime('now') WHERE id = ?`)
      .bind(call.conversation_id)
      .run();
  }

  // Tear down LiveKit so peers disconnect instead of lingering.
  await deleteLiveKitRoom(env, call.room_name);

  return outcome;
}

async function publishEnded(env: Env, call: CallRow, outcome: "missed" | "ended") {
  if (!call.conversation_id) return;
  await publishToConversation(env, {
    conversationId: call.conversation_id,
    event: {
      type: "call_ended",
      callId: call.id,
      outcome,
      mode: normalizeMode(call.mode),
      conversationId: call.conversation_id,
    },
  });
}

async function expireStaleCalls(env: Env): Promise<void> {
  const stale = await env.DB.prepare(
    `SELECT id, family_id, conversation_id, room_name, call_type, initiated_by,
            status, created_at, answered_at, event_message_id
     FROM calls
     WHERE status IN ('ringing', 'active')
       AND created_at < datetime('now', '-2 hours')`,
  ).all<Omit<CallRow, "mode">>();

  for (const row of stale.results ?? []) {
    const mode = await modeForConversation(env.DB, row.conversation_id);
    await finalizeCall(env, { ...row, mode });
  }
}

async function tokenForCall(
  env: Env,
  call: CallRow,
  user: { id: string; name: string },
): Promise<string> {
  return createLiveKitToken(env, {
    identity: user.id,
    name: user.name,
    roomName: call.room_name,
  });
}

async function resolveCallMode(
  db: D1Database,
  conversationId: string,
  memberCount: number,
): Promise<CallMode> {
  const conv = await db
    .prepare(`SELECT type FROM conversations WHERE id = ?`)
    .bind(conversationId)
    .first<{ type: string }>();
  if (conv?.type === "direct" || memberCount <= 2) return "direct";
  return "group";
}

async function notifyIncomingCall(
  env: Env,
  opts: {
    conversationId: string;
    excludeUserId: string;
    callId: string;
    callType: "audio" | "video";
    mode: CallMode;
    roomName: string;
    fromName: string;
  },
): Promise<void> {
  const event = {
    type: "incoming_call",
    callId: opts.callId,
    callType: opts.callType,
    mode: opts.mode,
    roomName: opts.roomName,
    conversationId: opts.conversationId,
    fromName: opts.fromName,
  };
  await Promise.all([
    publishToConversation(env, {
      conversationId: opts.conversationId,
      excludeUserId: opts.excludeUserId,
      event,
    }),
    notifyConversationMembers(env, {
      conversationId: opts.conversationId,
      excludeUserId: opts.excludeUserId,
      title: "Bejövő hívás",
      body: `${opts.fromName} hív (${opts.callType === "video" ? "videó" : "hang"})`,
      kind: "call",
      data: {
        type: "incoming_call",
        callId: opts.callId,
        callType: opts.callType,
        mode: opts.mode,
        roomName: opts.roomName,
        conversationId: opts.conversationId,
        fromName: opts.fromName,
      },
    }),
  ]);
}

async function loadCall(db: D1Database, callId: string): Promise<CallRow | null> {
  const call = await db
    .prepare(
      `SELECT id, family_id, conversation_id, room_name, call_type, initiated_by,
              status, created_at, answered_at, event_message_id, ended_at
       FROM calls WHERE id = ?`,
    )
    .bind(callId)
    .first<Omit<CallRow, "mode">>();
  if (!call) return null;
  const mode = await modeForConversation(db, call.conversation_id);
  return { ...call, mode };
}

calls.post("/start", async (c) => {
  const body = await readLimitedJson<{
    conversationId?: string;
    callType?: "audio" | "video";
  }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }

  const callType = body.callType === "video" ? "video" : "audio";
  const conversationId =
    typeof body.conversationId === "string" ? body.conversationId.trim() || null : null;
  if (!conversationId) {
    return c.json({ error: "A hívást egy beszélgetésből kell indítani" }, 400);
  }

  await expireStaleCalls(c.env);
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);
  if (!hasPaidPlan(family.plan)) {
    return c.json(
      {
        error: "Híváshoz előfizetés kell.",
        softPaywall: true,
      },
      403,
    );
  }

  const me = c.get("user");
  if (!(await isConversationMember(c.env.DB, conversationId, me.id))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const members = await c.env.DB.prepare(
    `SELECT cm.user_id
     FROM conversation_members cm
     JOIN family_members fm ON fm.user_id = cm.user_id AND fm.family_id = ?
     WHERE cm.conversation_id = ?`,
  )
    .bind(family.id, conversationId)
    .all<{ user_id: string }>();
  const participantIds = new Set((members.results ?? []).map((m) => m.user_id));
  if (participantIds.size > MAX_CALL_PARTICIPANTS) {
    return c.json(
      { error: `Hívás maximum ${MAX_CALL_PARTICIPANTS} résztvevővel indítható` },
      400,
    );
  }
  if (participantIds.size < 2) {
    return c.json({ error: "Nincs kit hívni" }, 400);
  }

  const mode = await resolveCallMode(c.env.DB, conversationId, participantIds.size);

  const existing = await c.env.DB.prepare(
    `SELECT id, family_id, conversation_id, room_name, call_type, initiated_by,
            status, created_at, answered_at, event_message_id
     FROM calls
     WHERE family_id = ? AND conversation_id = ? AND initiated_by = ?
       AND status IN ('ringing', 'active')
     ORDER BY created_at DESC LIMIT 1`,
  )
    .bind(family.id, conversationId, me.id)
    .first<Omit<CallRow, "mode">>();
  if (existing) {
    const existingCall: CallRow = { ...existing, mode };
    if (!existingCall.event_message_id) {
      const messageId = await createCallChatMessage(c.env.DB, {
        conversationId,
        senderId: me.id,
        callId: existingCall.id,
        callType: existingCall.call_type,
      });
      await c.env.DB.prepare(`UPDATE calls SET event_message_id = ? WHERE id = ?`)
        .bind(messageId, existingCall.id)
        .run();
      existingCall.event_message_id = messageId;
    }
    await ensureLiveKitRoom(c.env, { roomName: existingCall.room_name, mode: existingCall.mode });
    const token = await tokenForCall(c.env, existingCall, me);
    c.executionCtx.waitUntil(
      notifyIncomingCall(c.env, {
        conversationId,
        excludeUserId: me.id,
        callId: existingCall.id,
        callType: existingCall.call_type,
        mode: existingCall.mode,
        roomName: existingCall.room_name,
        fromName: me.name,
      }),
    );
    return c.json({ call: publicCall(c.env, existingCall, { token }) });
  }

  const callId = id("call");
  const roomName = `myuzi-${family.id}-${callId}`;
  const messageId = await createCallChatMessage(c.env.DB, {
    conversationId,
    senderId: me.id,
    callId,
    callType,
  });

  await c.env.DB.prepare(
    `INSERT INTO calls
       (id, family_id, conversation_id, room_name, call_type, initiated_by, status, event_message_id)
     VALUES (?, ?, ?, ?, ?, ?, 'ringing', ?)`,
  )
    .bind(callId, family.id, conversationId, roomName, callType, me.id, messageId)
    .run();

  const call: CallRow = {
    id: callId,
    family_id: family.id,
    conversation_id: conversationId,
    room_name: roomName,
    call_type: callType,
    mode,
    initiated_by: me.id,
    status: "ringing",
    created_at: new Date().toISOString(),
    answered_at: null,
    event_message_id: messageId,
  };

  await ensureLiveKitRoom(c.env, { roomName, mode });
  const token = await tokenForCall(c.env, call, me);

  c.executionCtx.waitUntil(
    notifyIncomingCall(c.env, {
      conversationId,
      excludeUserId: me.id,
      callId,
      callType,
      mode,
      roomName,
      fromName: me.name,
    }),
  );

  return c.json({ call: publicCall(c.env, call, { token, status: "ringing" }) });
});

calls.post("/:id/join", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env);
  const call = await loadCall(c.env.DB, callId);

  if (!call || call.status === "ended") {
    return c.json({ error: "A hívás nem elérhető" }, 404);
  }
  if (!call.conversation_id) {
    return c.json({ error: "A hívás beszélgetése már nem elérhető" }, 410);
  }

  const allowed = await isConversationMember(
    c.env.DB,
    call.conversation_id,
    c.get("userId"),
  );
  if (!allowed) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  // Direct: only initiator + one peer (max 2 LiveKit identities).
  if (call.mode === "direct" && call.initiated_by !== c.get("userId")) {
    const count = await countLiveKitParticipants(c.env, call.room_name);
    if (count != null && count >= 2) {
      return c.json({ error: "A hívás már foglalt" }, 409);
    }
  }

  if (call.status === "ringing" && call.initiated_by !== c.get("userId")) {
    const answeredAt = new Date().toISOString();
    await c.env.DB.prepare(
      `UPDATE calls
       SET status = 'active', answered_at = COALESCE(answered_at, ?)
       WHERE id = ? AND status = 'ringing'`,
    )
      .bind(answeredAt, callId)
      .run();
    call.status = "active";
    call.answered_at = answeredAt;
    await setCallMessageStatus(c.env.DB, {
      messageId: call.event_message_id,
      status: "active",
      durationMs: 0,
    });
    if (call.conversation_id) {
      await c.env.DB.prepare(
        `UPDATE conversations SET updated_at = datetime('now') WHERE id = ?`,
      )
        .bind(call.conversation_id)
        .run();
      c.executionCtx.waitUntil(
        publishToConversation(c.env, {
          conversationId: call.conversation_id,
          event: {
            type: "call_updated",
            callId: call.id,
            status: "active",
            mode: call.mode,
            conversationId: call.conversation_id,
          },
        }),
      );
    }
  }

  await ensureLiveKitRoom(c.env, { roomName: call.room_name, mode: call.mode });
  const user = c.get("user");
  const token = await tokenForCall(c.env, call, user);

  return c.json({
    call: publicCall(c.env, call, {
      token,
      status: call.initiated_by === user.id ? call.status : "active",
    }),
  });
});

/** Leave without ending for group; ends the whole call for direct / last peer. */
calls.post("/:id/leave", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env);
  const call = await loadCall(c.env.DB, callId);
  if (!call) return c.json({ error: "Nem található" }, 404);
  if (call.status === "ended") return c.json({ ok: true, alreadyEnded: true });

  const userId = c.get("userId");
  const allowed = call.conversation_id
    ? await isConversationMember(c.env.DB, call.conversation_id, userId)
    : await isFamilyMember(c.env.DB, call.family_id, userId);
  if (!allowed) return c.json({ error: "Nincs jogosultság" }, 403);

  await removeLiveKitParticipant(c.env, call.room_name, userId);

  // 1:1 — anyone leaving ends the call for both.
  if (call.mode === "direct") {
    const outcome = await finalizeCall(c.env, call);
    c.executionCtx.waitUntil(publishEnded(c.env, call, outcome));
    return c.json({ ok: true, ended: true, outcome, mode: call.mode });
  }

  // Group — end only if room empty / alone after leave.
  const remaining = await countLiveKitParticipants(c.env, call.room_name);
  if (remaining != null && remaining <= 0) {
    const outcome = await finalizeCall(c.env, call);
    c.executionCtx.waitUntil(publishEnded(c.env, call, outcome));
    return c.json({ ok: true, ended: true, outcome, mode: call.mode });
  }

  if (call.conversation_id) {
    c.executionCtx.waitUntil(
      publishToConversation(c.env, {
        conversationId: call.conversation_id,
        event: {
          type: "call_participant_left",
          callId: call.id,
          userId,
          mode: call.mode,
          conversationId: call.conversation_id,
        },
      }),
    );
  }

  return c.json({ ok: true, ended: false, mode: call.mode });
});

/** Decline ringing: direct ends for everyone; group only skips this user. */
calls.post("/:id/decline", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env);
  const call = await loadCall(c.env.DB, callId);
  if (!call) return c.json({ error: "Nem található" }, 404);
  if (call.status === "ended") return c.json({ ok: true, alreadyEnded: true });

  const userId = c.get("userId");
  const allowed = call.conversation_id
    ? await isConversationMember(c.env.DB, call.conversation_id, userId)
    : await isFamilyMember(c.env.DB, call.family_id, userId);
  if (!allowed) return c.json({ error: "Nincs jogosultság" }, 403);

  // 1:1: decline ends the call. Group: only skip this user (others keep ringing).
  if (call.mode === "direct") {
    const outcome = await finalizeCall(c.env, call);
    c.executionCtx.waitUntil(publishEnded(c.env, call, outcome));
    return c.json({ ok: true, ended: true, outcome, mode: call.mode });
  }

  return c.json({ ok: true, ended: false, mode: call.mode });
});

calls.post("/:id/end", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env);
  const call = await loadCall(c.env.DB, callId);

  if (!call) return c.json({ error: "Nem található" }, 404);
  if (call.status === "ended") {
    return c.json({ ok: true, alreadyEnded: true });
  }

  const allowed = call.conversation_id
    ? await isConversationMember(c.env.DB, call.conversation_id, c.get("userId"))
    : await isFamilyMember(c.env.DB, call.family_id, c.get("userId"));
  if (!allowed) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  const outcome = await finalizeCall(c.env, call);
  c.executionCtx.waitUntil(publishEnded(c.env, call, outcome));
  return c.json({ ok: true, outcome, mode: call.mode });
});

calls.get("/active", async (c) => {
  await expireStaleCalls(c.env);
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ calls: [] });

  const rows = await c.env.DB.prepare(
    `SELECT c.id, c.family_id, c.conversation_id, c.room_name, c.call_type, c.initiated_by,
            c.status, c.created_at, c.answered_at, c.event_message_id
     FROM calls c
     WHERE c.family_id = ? AND c.status IN ('ringing', 'active')
       AND c.created_at >= datetime('now', '-2 hours')
       AND EXISTS (
         SELECT 1 FROM conversation_members cm
         WHERE cm.conversation_id = c.conversation_id
           AND cm.user_id = ?
       )
     ORDER BY created_at DESC LIMIT 5`,
  )
    .bind(family.id, c.get("userId"))
    .all<Omit<CallRow, "mode">>();

  const callsOut = [];
  for (const row of rows.results ?? []) {
    const mode = await modeForConversation(c.env.DB, row.conversation_id);
    callsOut.push({ ...row, mode });
  }

  return c.json({ calls: callsOut });
});

calls.post("/token", async (c) => {
  const body = await readLimitedJson<{ roomName?: string }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }
  const roomName = typeof body.roomName === "string" ? body.roomName.trim() : "";
  if (!roomName) {
    return c.json({ error: "Érvénytelen szoba" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  const call = await c.env.DB.prepare(
    `SELECT id, family_id, conversation_id, room_name, call_type, initiated_by,
            status, created_at, answered_at, event_message_id
     FROM calls
     WHERE room_name = ? AND family_id = ? AND status != 'ended'`,
  )
    .bind(roomName, family.id)
    .first<Omit<CallRow, "mode">>();
  if (!call) return c.json({ error: "A hívás nem elérhető" }, 404);
  const mode = await modeForConversation(c.env.DB, call.conversation_id);
  const full: CallRow = { ...call, mode };
  if (!full.conversation_id) {
    return c.json({ error: "A hívás beszélgetése már nem elérhető" }, 410);
  }

  const user = c.get("user");
  const allowed = await isConversationMember(c.env.DB, full.conversation_id, user.id);
  if (!allowed) return c.json({ error: "Nincs jogosultság" }, 403);

  const token = await tokenForCall(c.env, full, user);

  return c.json({ token, livekitUrl: c.env.LIVEKIT_URL, mode: full.mode });
});

export default calls;
