import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import { isConversationMember } from "../lib/db";
import { requireAuth } from "../middleware/auth";

const messages = new Hono<{ Bindings: Env; Variables: Variables }>();
messages.use("*", requireAuth);

messages.get("/:conversationId", async (c) => {
  const conversationId = c.req.param("conversationId");
  if (!(await isConversationMember(c.env.DB, conversationId, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const before = c.req.query("before");
  const limit = Math.min(Number(c.req.query("limit") ?? 40), 100);

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
      created_at: string;
    }>();

  return c.json({
    messages: (rows.results ?? []).reverse().map((m) => ({
      id: m.id,
      conversationId: m.conversation_id,
      senderId: m.sender_id,
      senderName: m.sender_name,
      durationMs: m.duration_ms,
      createdAt: m.created_at,
      url: `/api/messages/audio/${m.id}`,
    })),
  });
});

messages.post("/:conversationId", async (c) => {
  const conversationId = c.req.param("conversationId");
  if (!(await isConversationMember(c.env.DB, conversationId, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const contentType = c.req.header("Content-Type") ?? "audio/m4a";
  const durationMs = Number(c.req.header("X-Duration-Ms") ?? 0);
  const body = await c.req.arrayBuffer();
  if (body.byteLength === 0 || body.byteLength > 8 * 1024 * 1024) {
    return c.json({ error: "Érvénytelen hangfájl (max 8 MB)" }, 400);
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
    `INSERT INTO voice_messages (id, conversation_id, sender_id, r2_key, duration_ms)
     VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(messageId, conversationId, c.get("userId"), key, durationMs)
    .run();

  await c.env.DB.prepare(
    `UPDATE conversations SET updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(conversationId)
    .run();

  return c.json(
    {
      message: {
        id: messageId,
        conversationId,
        senderId: c.get("userId"),
        durationMs,
        url: `/api/messages/audio/${messageId}`,
      },
    },
    201,
  );
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

export default messages;
