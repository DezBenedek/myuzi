import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import {
  getUserById,
  getUserFamily,
  hasPaidPlan,
  isConversationMember,
  isFamilyMember,
} from "../lib/db";
import { createLiveKitToken } from "../lib/livekit";
import { sendPush } from "../lib/push";
import { readLimitedJson } from "../lib/body";
import { requireAuth } from "../middleware/auth";

const calls = new Hono<{ Bindings: Env; Variables: Variables }>();
calls.use("*", requireAuth);

const MAX_CALL_PARTICIPANTS = 6;

type CallRow = {
  id: string;
  family_id: string;
  conversation_id: string | null;
  room_name: string;
  call_type: "audio" | "video";
  initiated_by: string;
  status: "ringing" | "active" | "ended";
  created_at: string;
};

async function expireStaleCalls(db: D1Database): Promise<void> {
  await db
    .prepare(
      `UPDATE calls
       SET status = 'ended', ended_at = datetime('now')
       WHERE status IN ('ringing', 'active')
         AND created_at < datetime('now', '-2 hours')`,
    )
    .run();
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

  await expireStaleCalls(c.env.DB);
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

  const existing = await c.env.DB.prepare(
    `SELECT * FROM calls
     WHERE family_id = ? AND conversation_id = ? AND initiated_by = ?
       AND status IN ('ringing', 'active')
     ORDER BY created_at DESC LIMIT 1`,
  )
    .bind(family.id, conversationId, me.id)
    .first<CallRow>();
  if (existing) {
    const token = await tokenForCall(c.env, existing, me);
    return c.json({
      call: {
        id: existing.id,
        roomName: existing.room_name,
        callType: existing.call_type,
        livekitUrl: c.env.LIVEKIT_URL,
        token,
        status: existing.status,
      },
    });
  }

  const callId = id("call");
  const roomName = `myuzi-${family.id}-${callId}`;

  await c.env.DB.prepare(
    `INSERT INTO calls (id, family_id, conversation_id, room_name, call_type, initiated_by, status)
     VALUES (?, ?, ?, ?, ?, ?, 'ringing')`,
  )
    .bind(callId, family.id, conversationId, roomName, callType, me.id)
    .run();

  const call: CallRow = {
    id: callId,
    family_id: family.id,
    conversation_id: conversationId,
    room_name: roomName,
    call_type: callType,
    initiated_by: me.id,
    status: "ringing",
    created_at: new Date().toISOString(),
  };
  const token = await tokenForCall(c.env, call, me);

  // Soft push: store ringing state; clients poll / ring via push tokens
  const callees = [...participantIds].filter((id) => id !== me.id);
  for (const uid of callees) {
    const u = await getUserById(c.env.DB, uid);
    if (u?.push_token) {
      c.executionCtx.waitUntil(
        sendPush(c.env, {
          token: u.push_token,
          title: "Bejövő hívás",
          body: `${me.name} hív (${callType === "video" ? "videó" : "hang"})`,
          kind: "call",
          data: {
            type: "incoming_call",
            callId,
            callType,
            roomName,
            fromName: me.name,
          },
        }),
      );
    }
  }

  return c.json({
    call: {
      id: callId,
      roomName,
      callType,
      livekitUrl: c.env.LIVEKIT_URL,
      token,
      status: "ringing",
    },
  });
});

calls.post("/:id/join", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env.DB);
  const call = await c.env.DB.prepare("SELECT * FROM calls WHERE id = ?")
    .bind(callId)
    .first<CallRow>();

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

  if (call.status === "ringing") {
    await c.env.DB.prepare("UPDATE calls SET status = 'active' WHERE id = ?")
      .bind(callId)
      .run();
  }

  const user = c.get("user");
  const token = await tokenForCall(c.env, call, user);

  return c.json({
    call: {
      id: call.id,
      roomName: call.room_name,
      callType: call.call_type,
      livekitUrl: c.env.LIVEKIT_URL,
      token,
      status: "active",
    },
  });
});

calls.post("/:id/end", async (c) => {
  const callId = c.req.param("id");
  await expireStaleCalls(c.env.DB);
  const call = await c.env.DB.prepare("SELECT * FROM calls WHERE id = ?")
    .bind(callId)
    .first<Pick<CallRow, "family_id" | "conversation_id" | "status">>();

  if (!call) return c.json({ error: "Nem található" }, 404);
  const allowed = call.conversation_id
    ? await isConversationMember(c.env.DB, call.conversation_id, c.get("userId"))
    : await isFamilyMember(c.env.DB, call.family_id, c.get("userId"));
  if (!allowed) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  await c.env.DB.prepare(
    `UPDATE calls SET status = 'ended', ended_at = datetime('now') WHERE id = ?`,
  )
    .bind(callId)
    .run();

  return c.json({ ok: true });
});

calls.get("/active", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ calls: [] });

  const rows = await c.env.DB.prepare(
    `SELECT c.* FROM calls c
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
    .all();

  return c.json({ calls: rows.results ?? [] });
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
    `SELECT * FROM calls
     WHERE room_name = ? AND family_id = ? AND status != 'ended'`,
  )
    .bind(roomName, family.id)
    .first<CallRow>();
  if (!call) return c.json({ error: "A hívás nem elérhető" }, 404);
  if (!call.conversation_id) {
    return c.json({ error: "A hívás beszélgetése már nem elérhető" }, 410);
  }

  const user = c.get("user");
  const allowed = await isConversationMember(c.env.DB, call.conversation_id, user.id);
  if (!allowed) return c.json({ error: "Nincs jogosultság" }, 403);

  const token = await tokenForCall(c.env, call, user);

  return c.json({ token, livekitUrl: c.env.LIVEKIT_URL });
});

export default calls;
