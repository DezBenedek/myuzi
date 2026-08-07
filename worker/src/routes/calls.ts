import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import {
  getUserById,
  getUserFamily,
  isConversationMember,
  isFamilyMember,
} from "../lib/db";
import { createLiveKitToken } from "../lib/livekit";
import { sendPush } from "../lib/push";
import { requireAuth } from "../middleware/auth";

const calls = new Hono<{ Bindings: Env; Variables: Variables }>();
calls.use("*", requireAuth);

calls.post("/start", async (c) => {
  const body = await c.req.json<{
    conversationId?: string;
    calleeIds?: string[];
    callType?: "audio" | "video";
  }>();

  const callType = body.callType === "video" ? "video" : "audio";
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);

  const me = c.get("user");
  let participantIds = new Set<string>([me.id]);

  if (body.conversationId) {
    if (!(await isConversationMember(c.env.DB, body.conversationId, me.id))) {
      return c.json({ error: "Nincs hozzáférés" }, 403);
    }
    const members = await c.env.DB.prepare(
      "SELECT user_id FROM conversation_members WHERE conversation_id = ?",
    )
      .bind(body.conversationId)
      .all<{ user_id: string }>();
    for (const m of members.results ?? []) participantIds.add(m.user_id);
  }

  for (const uid of body.calleeIds ?? []) {
    if (!(await isFamilyMember(c.env.DB, family.id, uid))) {
      return c.json({ error: "Nem családtag" }, 403);
    }
    participantIds.add(uid);
  }

  const callId = id("call");
  const roomName = `myuzi-${family.id}-${callId}`;

  await c.env.DB.prepare(
    `INSERT INTO calls (id, family_id, conversation_id, room_name, call_type, initiated_by, status)
     VALUES (?, ?, ?, ?, ?, ?, 'ringing')`,
  )
    .bind(callId, family.id, body.conversationId ?? null, roomName, callType, me.id)
    .run();

  const token = await createLiveKitToken(c.env, {
    identity: me.id,
    name: me.name,
    roomName,
  });

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
  const call = await c.env.DB.prepare("SELECT * FROM calls WHERE id = ?")
    .bind(callId)
    .first<{
      id: string;
      family_id: string;
      room_name: string;
      call_type: string;
      status: string;
    }>();

  if (!call || call.status === "ended") {
    return c.json({ error: "A hívás nem elérhető" }, 404);
  }

  if (!(await isFamilyMember(c.env.DB, call.family_id, c.get("userId")))) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  if (call.status === "ringing") {
    await c.env.DB.prepare("UPDATE calls SET status = 'active' WHERE id = ?")
      .bind(callId)
      .run();
  }

  const user = c.get("user");
  const token = await createLiveKitToken(c.env, {
    identity: user.id,
    name: user.name,
    roomName: call.room_name,
  });

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
  const call = await c.env.DB.prepare("SELECT * FROM calls WHERE id = ?")
    .bind(callId)
    .first<{ family_id: string; status: string }>();

  if (!call) return c.json({ error: "Nem található" }, 404);
  if (!(await isFamilyMember(c.env.DB, call.family_id, c.get("userId")))) {
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
    `SELECT * FROM calls
     WHERE family_id = ? AND status IN ('ringing', 'active')
     ORDER BY created_at DESC LIMIT 5`,
  )
    .bind(family.id)
    .all();

  return c.json({ calls: rows.results ?? [] });
});

calls.post("/token", async (c) => {
  const body = await c.req.json<{ roomName?: string }>();
  if (!body.roomName?.startsWith("myuzi-")) {
    return c.json({ error: "Érvénytelen szoba" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family || !body.roomName.includes(family.id)) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }

  const user = c.get("user");
  const token = await createLiveKitToken(c.env, {
    identity: user.id,
    name: user.name,
    roomName: body.roomName,
  });

  return c.json({ token, livekitUrl: c.env.LIVEKIT_URL });
});

export default calls;
