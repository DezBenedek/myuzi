import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import { getUserFamily, isConversationMember } from "../lib/db";
import { notifyConversationMembers } from "../lib/push";
import { voiceMaxMsForPlan } from "../lib/stripe";
import { requireAuth } from "../middleware/auth";

const MAX_BYTES = 20 * 1024 * 1024;
const WAVE_BAR_COUNT = 32;

/** Parse client/server wave bars: ints 1–20, fixed length. */
function parseWaveBars(raw: string | null | undefined): number[] | null {
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return null;
    const bars = parsed
      .map((n) => Math.round(Number(n)))
      .filter((n) => Number.isFinite(n))
      .map((n) => Math.min(20, Math.max(1, n)));
    if (bars.length < 8) return null;
    return bars.slice(0, WAVE_BAR_COUNT);
  } catch {
    return null;
  }
}

function randomWaveBars(): number[] {
  const bars: number[] = [];
  for (let i = 0; i < WAVE_BAR_COUNT; i++) {
    bars.push(1 + Math.floor(Math.random() * 20));
  }
  return bars;
}

const messages = new Hono<{ Bindings: Env; Variables: Variables }>();
messages.use("*", requireAuth);

async function getLastReadAt(
  db: D1Database,
  conversationId: string,
  userId: string,
): Promise<string | null> {
  const row = await db
    .prepare(
      `SELECT last_read_at FROM conversation_members
       WHERE conversation_id = ? AND user_id = ?`,
    )
    .bind(conversationId, userId)
    .first<{ last_read_at: string | null }>();
  return row?.last_read_at ?? null;
}

async function markRead(db: D1Database, conversationId: string, userId: string): Promise<void> {
  await db
    .prepare(
      `UPDATE conversation_members
       SET last_read_at = datetime('now')
       WHERE conversation_id = ? AND user_id = ?`,
    )
    .bind(conversationId, userId)
    .run();
}

messages.delete("/item/:messageId", async (c) => {
  const messageId = c.req.param("messageId");
  const msg = await c.env.DB.prepare("SELECT * FROM voice_messages WHERE id = ?")
    .bind(messageId)
    .first<{
      id: string;
      conversation_id: string;
      sender_id: string;
      r2_key: string;
    }>();

  if (!msg) return c.json({ error: "Nem található" }, 404);
  if (msg.sender_id !== c.get("userId")) {
    return c.json({ error: "Csak a saját üzenetedet törölheted" }, 403);
  }
  if (!(await isConversationMember(c.env.DB, msg.conversation_id, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  await c.env.VOICE.delete(msg.r2_key);
  await c.env.DB.prepare("DELETE FROM voice_messages WHERE id = ?").bind(messageId).run();
  return c.json({ ok: true });
});

messages.post("/:conversationId/read", async (c) => {
  const conversationId = c.req.param("conversationId");
  if (!(await isConversationMember(c.env.DB, conversationId, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }
  await markRead(c.env.DB, conversationId, c.get("userId"));
  return c.json({ ok: true });
});

messages.get("/audio/:messageId", async (c) => {
  const messageId = c.req.param("messageId");
  const msg = await c.env.DB.prepare("SELECT * FROM voice_messages WHERE id = ?")
    .bind(messageId)
    .first<{
      id: string;
      conversation_id: string;
      r2_key: string;
    }>();

  if (!msg) return c.json({ error: "Nem található" }, 404);
  if (!(await isConversationMember(c.env.DB, msg.conversation_id, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const obj = await c.env.VOICE.get(msg.r2_key);
  if (!obj) return c.json({ error: "Fájl hiányzik" }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set("etag", obj.httpEtag);
  headers.set("Cache-Control", "private, max-age=3600");
  return new Response(obj.body, { headers });
});

messages.get("/:conversationId", async (c) => {
  const conversationId = c.req.param("conversationId");
  const userId = c.get("userId");
  if (!(await isConversationMember(c.env.DB, conversationId, userId))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const before = c.req.query("before");
  const limit = Math.min(Number(c.req.query("limit") ?? 50), 100);
  const lastReadAt = await getLastReadAt(c.env.DB, conversationId, userId);

  let sql = `SELECT vm.*, u.name AS sender_name
             FROM voice_messages vm
             JOIN users u ON u.id = vm.sender_id
             WHERE vm.conversation_id = ?`;
  const binds: (string | number)[] = [conversationId];
  if (before) {
    sql += " AND vm.created_at < ?";
    binds.push(before);
  }
  sql += " ORDER BY vm.created_at DESC LIMIT ?";
  binds.push(limit);

  const rows = await c.env.DB.prepare(sql)
    .bind(...binds)
    .all<{
      id: string;
      conversation_id: string;
      sender_id: string;
      sender_name: string;
      r2_key: string;
      duration_ms: number;
      wave_bars: string | null;
      created_at: string;
    }>();

  const cutoff = lastReadAt ?? "1970-01-01T00:00:00.000Z";

  await markRead(c.env.DB, conversationId, userId);

  const memberReads = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.avatar_key, cm.last_read_at
     FROM conversation_members cm
     JOIN users u ON u.id = cm.user_id
     WHERE cm.conversation_id = ?`,
  )
    .bind(conversationId)
    .all<{
      id: string;
      name: string;
      avatar_key: string | null;
      last_read_at: string | null;
    }>();

  return c.json({
    messages: (rows.results ?? []).reverse().map((m) => ({
      id: m.id,
      conversationId: m.conversation_id,
      senderId: m.sender_id,
      senderName: m.sender_name,
      durationMs: m.duration_ms,
      waveBars: parseWaveBars(m.wave_bars),
      createdAt: m.created_at,
      unread: m.sender_id !== userId && m.created_at > cutoff,
      url: `/api/messages/audio/${m.id}`,
    })),
    memberReads: (memberReads.results ?? []).map((m) => ({
      userId: m.id,
      name: m.name,
      avatarUrl: m.avatar_key ? `/api/users/${m.id}/avatar` : null,
      lastReadAt: m.last_read_at,
    })),
  });
});

messages.post("/:conversationId", async (c) => {
  const conversationId = c.req.param("conversationId");
  if (!(await isConversationMember(c.env.DB, conversationId, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  const maxDurationMs = voiceMaxMsForPlan(family?.plan);

  const contentType = c.req.header("Content-Type") ?? "audio/m4a";
  let durationMs = Number(c.req.header("X-Duration-Ms") ?? 0);
  if (!Number.isFinite(durationMs) || durationMs < 0) durationMs = 0;
  if (durationMs > maxDurationMs) durationMs = maxDurationMs;

  const waveBars =
    parseWaveBars(c.req.header("X-Wave-Bars")) ?? randomWaveBars();

  const body = await c.req.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > MAX_BYTES) {
    return c.json({ error: "Érvénytelen hangfájl" }, 400);
  }

  const messageId = id("msg");
  const key = `voice/${conversationId}/${messageId}`;

  await c.env.VOICE.put(key, body, {
    httpMetadata: { contentType },
    customMetadata: {
      senderId: c.get("userId"),
      conversationId,
    },
  });

  await c.env.DB.prepare(
    `INSERT INTO voice_messages (id, conversation_id, sender_id, r2_key, duration_ms, wave_bars)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      messageId,
      conversationId,
      c.get("userId"),
      key,
      durationMs,
      JSON.stringify(waveBars),
    )
    .run();

  await c.env.DB.prepare(
    `UPDATE conversations SET updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(conversationId)
    .run();

  const me = c.get("user");
  c.executionCtx.waitUntil(
    notifyConversationMembers(c.env, {
      conversationId,
      excludeUserId: me.id,
      title: "Új hangüzenet",
      body: `${me.name} hangüzenetet küldött`,
      kind: "message",
      data: {
        type: "new_message",
        conversationId,
        messageId,
        fromName: me.name,
      },
    }),
  );

  return c.json(
    {
      message: {
        id: messageId,
        conversationId,
        senderId: c.get("userId"),
        durationMs,
        waveBars,
        unread: false,
        url: `/api/messages/audio/${messageId}`,
      },
    },
    201,
  );
});

export default messages;
