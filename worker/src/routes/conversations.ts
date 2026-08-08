import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { addDays, id, inviteToken, isValidEmail, normalizeEmail } from "../lib/crypto";
import {
  canAddMember,
  getUserByEmail,
  getUserFamily,
  hasPaidPlan,
  isConversationMember,
  isFamilyMember,
  memberCount,
} from "../lib/db";
import { inviteEmail, sendEmail } from "../lib/email";
import { publicBaseUrl } from "../lib/urls";
import { readLimitedJson } from "../lib/body";
import { requireAuth } from "../middleware/auth";

const conversations = new Hono<{ Bindings: Env; Variables: Variables }>();
conversations.use("*", requireAuth);

async function familyPeople(
  db: D1Database,
  userId: string,
): Promise<
  Array<{ id: string; name: string; email: string; role: string; avatarUrl: string | null }>
> {
  const family = await getUserFamily(db, userId);
  if (!family) return [];
  const members = await db
    .prepare(
      `SELECT u.id, u.name, u.email, u.avatar_key, fm.role
       FROM family_members fm JOIN users u ON u.id = fm.user_id
       WHERE fm.family_id = ? ORDER BY u.name`,
    )
    .bind(family.id)
    .all<{ id: string; name: string; email: string; avatar_key: string | null; role: string }>();
  return (members.results ?? []).map((m) => ({
    id: m.id,
    name: m.name,
    email: m.email,
    role: m.role,
    avatarUrl: m.avatar_key ? `/api/users/${m.id}/avatar` : null,
  }));
}

async function openOrCreateDirect(
  db: D1Database,
  familyId: string,
  me: string,
  otherId: string,
): Promise<string> {
  const existing = await db
    .prepare(
      `SELECT c.id FROM conversations c
       JOIN conversation_members a ON a.conversation_id = c.id AND a.user_id = ?
       JOIN conversation_members b ON b.conversation_id = c.id AND b.user_id = ?
       WHERE c.family_id = ? AND c.type = 'direct'
       LIMIT 1`,
    )
    .bind(me, otherId, familyId)
    .first<{ id: string }>();

  if (existing) return existing.id;

  const conversationId = id("con");
  await db.batch([
    db
      .prepare(
        `INSERT INTO conversations (id, family_id, type, name, created_by)
         VALUES (?, ?, 'direct', NULL, ?)`,
      )
      .bind(conversationId, familyId, me),
    db
      .prepare(`INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)`)
      .bind(conversationId, me),
    db
      .prepare(`INSERT INTO conversation_members (conversation_id, user_id) VALUES (?, ?)`)
      .bind(conversationId, otherId),
  ]);
  return conversationId;
}

conversations.get("/", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ conversations: [] });

  const userId = c.get("userId");
  const rows = await c.env.DB.prepare(
    `SELECT c.*,
      cm.last_read_at AS last_read_at,
      cm.pinned_at AS pinned_at,
      (SELECT COUNT(*) FROM conversation_members x WHERE x.conversation_id = c.id) AS member_count,
      (SELECT vm.created_at FROM voice_messages vm
         WHERE vm.conversation_id = c.id ORDER BY vm.created_at DESC LIMIT 1) AS last_message_at,
      (SELECT u.name FROM voice_messages vm
         JOIN users u ON u.id = vm.sender_id
         WHERE vm.conversation_id = c.id ORDER BY vm.created_at DESC LIMIT 1) AS last_sender_name,
      (SELECT COUNT(*) FROM voice_messages vm
         WHERE vm.conversation_id = c.id
           AND vm.sender_id != ?
           AND vm.created_at > COALESCE(cm.last_read_at, '1970-01-01T00:00:00.000Z')
      ) AS unread_count
     FROM conversations c
     JOIN conversation_members cm ON cm.conversation_id = c.id AND cm.user_id = ?
     WHERE c.family_id = ?
     ORDER BY
       CASE WHEN cm.pinned_at IS NULL THEN 1 ELSE 0 END,
       COALESCE(cm.pinned_at, '') DESC,
       COALESCE(last_message_at, c.created_at) DESC
     LIMIT 100`,
  )
    .bind(userId, userId, family.id)
    .all<{
      id: string;
      family_id: string;
      type: string;
      name: string | null;
      created_by: string;
      created_at: string;
      updated_at: string;
      last_read_at: string | null;
      pinned_at: string | null;
      member_count: number;
      last_message_at: string | null;
      last_sender_name: string | null;
      unread_count: number;
    }>();

  const conversationRows = rows.results ?? [];
  const membersByConversation = new Map<
    string,
    Array<{ id: string; name: string; email: string; avatar_key: string | null }>
  >();
  if (conversationRows.length > 0) {
    const placeholders = conversationRows.map(() => "?").join(", ");
    const memberRows = await c.env.DB.prepare(
      `SELECT cm.conversation_id, u.id, u.name, u.email, u.avatar_key
       FROM conversation_members cm JOIN users u ON u.id = cm.user_id
       WHERE cm.conversation_id IN (${placeholders})`,
    )
      .bind(...conversationRows.map((row) => row.id))
      .all<{
        conversation_id: string;
        id: string;
        name: string;
        email: string;
        avatar_key: string | null;
      }>();
    for (const member of memberRows.results ?? []) {
      const list = membersByConversation.get(member.conversation_id) ?? [];
      list.push(member);
      membersByConversation.set(member.conversation_id, list);
    }
  }

  const list = [];
  for (const row of conversationRows) {
    const members = membersByConversation.get(row.id) ?? [];

    let title = row.name;
    let avatarUrl: string | null = null;
    if (row.type === "direct") {
      const other = members.find((m) => m.id !== userId);
      title = other?.name ?? "Beszélgetés";
      avatarUrl = other?.avatar_key ? `/api/users/${other.id}/avatar` : null;
    }

    list.push({
      id: row.id,
      type: row.type,
      name: title,
      memberCount: row.member_count,
      lastMessageAt: row.last_message_at,
      lastSenderName: row.last_sender_name,
      unreadCount: row.unread_count ?? 0,
      pinned: !!row.pinned_at,
      pinnedAt: row.pinned_at,
      avatarUrl,
      members: members.map((m) => ({
        id: m.id,
        name: m.name,
        email: m.email,
        avatarUrl: m.avatar_key ? `/api/users/${m.id}/avatar` : null,
      })),
    });
  }

  return c.json({ conversations: list, familyMembers: await familyPeople(c.env.DB, userId) });
});

conversations.post("/direct", async (c) => {
  const body = await readLimitedJson<{ userId?: string }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }
  const otherId = typeof body.userId === "string" ? body.userId.trim() : "";
  if (!/^[A-Za-z0-9_-]{6,80}$/.test(otherId)) {
    return c.json({ error: "Érvénytelen felhasználóazonosító" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);
  if (otherId === c.get("userId")) {
    return c.json({ error: "Saját magaddal nem nyithatsz beszélgetést" }, 400);
  }
  if (!(await isFamilyMember(c.env.DB, family.id, otherId))) {
    return c.json({ error: "Nem családtag" }, 403);
  }

  const conversationId = await openOrCreateDirect(
    c.env.DB,
    family.id,
    c.get("userId"),
    otherId,
  );
  return c.json({ conversationId }, 201);
});

/** Open chat by email if already family; otherwise create invite (paid). */
conversations.post("/direct-by-email", async (c) => {
  const body = await readLimitedJson<{ email?: string }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }
  const email = normalizeEmail(body.email ?? "");
  if (!isValidEmail(email)) {
    return c.json({ error: "Érvényes email kell" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);

  const me = c.get("userId");
  if (email === c.get("user").email) {
    return c.json({ error: "Saját magadnak nem küldhetsz így üzenetet" }, 400);
  }

  const member = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.email FROM family_members fm
     JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = ? AND u.email = ?`,
  )
    .bind(family.id, email)
    .first<{ id: string; name: string; email: string }>();

  if (member) {
    const conversationId = await openOrCreateDirect(c.env.DB, family.id, me, member.id);
    return c.json({ conversationId, status: "opened" });
  }

  if (!hasPaidPlan(family.plan)) {
    const count = await memberCount(c.env.DB, family.id);
    if (!canAddMember(family, count)) {
      return c.json(
        {
          error: "Ingyenes csomag: max 3 fő. Több taghoz fizess elő.",
          softPaywall: true,
        },
        403,
      );
    }
  } else {
    const count = await memberCount(c.env.DB, family.id);
    if (!canAddMember(family, count)) {
      return c.json(
        {
          error: `Elérted a ${family.max_members} fős limittet.`,
          softPaywall: true,
        },
        403,
      );
    }
  }

  // If registered elsewhere but not in this family — still invite by email
  const existingUser = await getUserByEmail(c.env.DB, email);
  const token = inviteToken();
  const inviteId = id("inv");
  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(inviteId, family.id, email, token, me, addDays(14))
    .run();

  const inviteUrl = `${publicBaseUrl(c.req.url, c.env)}/invite/${token}`;
  try {
    const mail = inviteEmail(c.env.APP_NAME, family.name, c.get("user").name, inviteUrl);
    await sendEmail(c.env, { to: email, ...mail });
  } catch (err) {
    console.error("[direct-by-email invite]", err);
  }

  return c.json({
    status: "invited",
    inviteUrl,
    existingUser: !!existingUser,
    message:
      "Meghívót küldtünk. Amint csatlakozik a családhoz, beszélgethettek hangüzenettel.",
  });
});

conversations.post("/group", async (c) => {
  const body = await readLimitedJson<{ name?: string; memberIds?: string[] }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }
  const name = (typeof body.name === "string" ? body.name : "")
    .trim()
    .replace(/[<>&\u0000-\u001f]/g, "")
    .slice(0, 80)
    .trim();
  if (name.length < 2 || !Array.isArray(body.memberIds)) {
    return c.json({ error: "Adj nevet és tagokat a csoportnak" }, 400);
  }
  const memberIds = body.memberIds
    .filter((uid): uid is string => typeof uid === "string")
    .map((uid) => uid.trim());
  if (memberIds.length > 25 || memberIds.some((uid) => !/^[A-Za-z0-9_-]{6,80}$/.test(uid))) {
    return c.json({ error: "Érvénytelen csoporttag-lista" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);
  if (!hasPaidPlan(family.plan)) {
    return c.json(
      {
        error: "Csoportot csak előfizetéssel lehet létrehozni.",
        softPaywall: true,
      },
      403,
    );
  }

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

conversations.post("/:id/pin", async (c) => {
  const conversationId = c.req.param("id");
  const userId = c.get("userId");
  if (!(await isConversationMember(c.env.DB, conversationId, userId))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }
  await c.env.DB.prepare(
    `UPDATE conversation_members SET pinned_at = datetime('now')
     WHERE conversation_id = ? AND user_id = ?`,
  )
    .bind(conversationId, userId)
    .run();
  return c.json({ ok: true, pinned: true });
});

conversations.delete("/:id/pin", async (c) => {
  const conversationId = c.req.param("id");
  const userId = c.get("userId");
  if (!(await isConversationMember(c.env.DB, conversationId, userId))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }
  await c.env.DB.prepare(
    `UPDATE conversation_members SET pinned_at = NULL
     WHERE conversation_id = ? AND user_id = ?`,
  )
    .bind(conversationId, userId)
    .run();
  return c.json({ ok: true, pinned: false });
});

export default conversations;
