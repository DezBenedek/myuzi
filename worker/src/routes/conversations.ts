import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import { getUserFamily, isConversationMember, isFamilyMember } from "../lib/db";
import { requireAuth } from "../middleware/auth";

const conversations = new Hono<{ Bindings: Env; Variables: Variables }>();
conversations.use("*", requireAuth);

async function familyPeople(
  db: D1Database,
  userId: string,
): Promise<Array<{ id: string; name: string; email: string; role: string }>> {
  const family = await getUserFamily(db, userId);
  if (!family) return [];
  const members = await db
    .prepare(
      `SELECT u.id, u.name, u.email, fm.role
       FROM family_members fm JOIN users u ON u.id = fm.user_id
       WHERE fm.family_id = ? ORDER BY u.name`,
    )
    .bind(family.id)
    .all<{ id: string; name: string; email: string; role: string }>();
  return members.results ?? [];
}

conversations.get("/", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ conversations: [] });

  const rows = await c.env.DB.prepare(
    `SELECT c.*,
      (SELECT COUNT(*) FROM conversation_members cm WHERE cm.conversation_id = c.id) AS member_count,
      (SELECT vm.created_at FROM voice_messages vm
         WHERE vm.conversation_id = c.id ORDER BY vm.created_at DESC LIMIT 1) AS last_message_at
     FROM conversations c
     JOIN conversation_members cm ON cm.conversation_id = c.id
     WHERE cm.user_id = ? AND c.family_id = ?
     ORDER BY COALESCE(last_message_at, c.created_at) DESC`,
  )
    .bind(c.get("userId"), family.id)
    .all<{
      id: string;
      family_id: string;
      type: string;
      name: string | null;
      created_by: string;
      created_at: string;
      updated_at: string;
      member_count: number;
      last_message_at: string | null;
    }>();

  const list = [];
  for (const row of rows.results ?? []) {
    const members = await c.env.DB.prepare(
      `SELECT u.id, u.name, u.email
       FROM conversation_members cm JOIN users u ON u.id = cm.user_id
       WHERE cm.conversation_id = ?`,
    )
      .bind(row.id)
      .all<{ id: string; name: string; email: string }>();

    let title = row.name;
    if (row.type === "direct") {
      const other = (members.results ?? []).find((m) => m.id !== c.get("userId"));
      title = other?.name ?? "Beszélgetés";
    }

    list.push({
      id: row.id,
      type: row.type,
      name: title,
      memberCount: row.member_count,
      lastMessageAt: row.last_message_at,
      members: members.results ?? [],
    });
  }

  return c.json({ conversations: list, familyMembers: await familyPeople(c.env.DB, c.get("userId")) });
});


conversations.post("/direct", async (c) => {
  const body = await c.req.json<{ userId?: string }>();
  const otherId = body.userId;
  if (!otherId) return c.json({ error: "userId kell" }, 400);

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);
  if (!(await isFamilyMember(c.env.DB, family.id, otherId))) {
    return c.json({ error: "Nem családtag" }, 403);
  }

  const me = c.get("userId");
  const existing = await c.env.DB.prepare(
    `SELECT c.id FROM conversations c
     JOIN conversation_members a ON a.conversation_id = c.id AND a.user_id = ?
     JOIN conversation_members b ON b.conversation_id = c.id AND b.user_id = ?
     WHERE c.family_id = ? AND c.type = 'direct'
     LIMIT 1`,
  )
    .bind(me, otherId, family.id)
    .first<{ id: string }>();

  if (existing) return c.json({ conversationId: existing.id });

  const conversationId = id("con");
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO conversations (id, family_id, type, name, created_by)
       VALUES (?, ?, 'direct', NULL, ?)`,
    ).bind(conversationId, family.id, me),
    c.env.DB.prepare(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)`,
    ).bind(conversationId, me),
    c.env.DB.prepare(
      `INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)`,
    ).bind(conversationId, otherId),
  ]);

  return c.json({ conversationId }, 201);
});

conversations.post("/group", async (c) => {
  const body = await c.req.json<{ name?: string; memberIds?: string[] }>();
  const name = (body.name ?? "").trim();
  const memberIds = body.memberIds ?? [];
  if (name.length < 2) return c.json({ error: "Adj nevet a csoportnak" }, 400);

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);

  const me = c.get("userId");
  const unique = [...new Set([me, ...memberIds])];
  for (const uid of unique) {
    if (!(await isFamilyMember(c.env.DB, family.id, uid))) {
      return c.json({ error: "Minden tagnak családtagjának kell lennie" }, 403);
    }
  }

  const conversationId = id("con");
  const stmts = [
    c.env.DB.prepare(
      `INSERT INTO conversations (id, family_id, type, name, created_by)
       VALUES (?, ?, 'group', ?, ?)`,
    ).bind(conversationId, family.id, name, me),
    ...unique.map((uid) =>
      c.env.DB.prepare(
        `INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)`,
      ).bind(conversationId, uid),
    ),
  ];
  await c.env.DB.batch(stmts);

  return c.json({ conversationId }, 201);
});

conversations.get("/:id", async (c) => {
  const conversationId = c.req.param("id");
  if (!(await isConversationMember(c.env.DB, conversationId, c.get("userId")))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }

  const row = await c.env.DB.prepare("SELECT * FROM conversations WHERE id = ?")
    .bind(conversationId)
    .first();
  const members = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.email FROM conversation_members cm
     JOIN users u ON u.id = cm.user_id WHERE cm.conversation_id = ?`,
  )
    .bind(conversationId)
    .all();

  return c.json({ conversation: row, members: members.results ?? [] });
});

export default conversations;
