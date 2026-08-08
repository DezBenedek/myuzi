import { Hono } from "hono";

import type { Env, Variables } from "../types";
import {
  addDays,
  id,
  inviteToken,
  isExpired,
  isValidEmail,
  normalizeEmail,
} from "../lib/crypto";
import {
  getFamily,
  getUserByEmail,
  getUserById,
  getUserFamily,
} from "../lib/db";
import { familyConnectionEmail, sendEmail } from "../lib/email";
import { publicBaseUrl } from "../lib/urls";
import { readLimitedJson } from "../lib/body";
import { requireAuth } from "../middleware/auth";

const connections = new Hono<{ Bindings: Env; Variables: Variables }>();
connections.use("*", requireAuth);

function orderedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

function publicPerson(row: {
  id: string;
  name: string;
  email: string;
  avatar_key?: string | null;
  family_id?: string;
  family_name?: string;
  connection_id?: string;
}) {
  return {
    id: row.id,
    name: row.name,
    email: row.email,
    avatarUrl: row.avatar_key ? `/api/users/${row.id}/avatar` : null,
    familyId: row.family_id ?? null,
    familyName: row.family_name ?? null,
    connectionId: row.connection_id ?? null,
  };
}

connections.get("/", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ connections: [], incoming: [] });

  const active = await c.env.DB.prepare(
    `SELECT fc.id, fc.created_at,
            f.id AS other_family_id, f.name AS other_family_name,
            u.id AS owner_id, u.name AS owner_name, u.email AS owner_email
     FROM family_connections fc
     JOIN families f ON f.id = CASE
       WHEN fc.family_a_id = ? THEN fc.family_b_id
       ELSE fc.family_a_id
     END
     JOIN users u ON u.id = f.owner_id
     WHERE (fc.family_a_id = ? OR fc.family_b_id = ?)
       AND fc.status = 'active'
     ORDER BY f.name`,
  )
    .bind(family.id, family.id, family.id)
    .all<{
      id: string;
      created_at: string;
      other_family_id: string;
      other_family_name: string;
      owner_id: string;
      owner_name: string;
      owner_email: string;
    }>();

  const incoming = await c.env.DB.prepare(
    `SELECT i.id, i.token, i.expires_at, i.created_at,
            f.id AS family_id, f.name AS family_name,
            u.name AS invited_by_name, u.email AS invited_by_email
     FROM family_link_invites i
     JOIN families f ON f.id = i.source_family_id
     JOIN users u ON u.id = i.invited_by
     WHERE lower(i.target_email) = lower(?)
       AND i.status = 'pending'
       AND i.expires_at > datetime('now')
     ORDER BY i.created_at DESC
     LIMIT 20`,
  )
    .bind(c.get("user").email)
    .all<{
      id: string;
      token: string;
      expires_at: string;
      created_at: string;
      family_id: string;
      family_name: string;
      invited_by_name: string;
      invited_by_email: string;
    }>();

  return c.json({
    connections: (active.results ?? []).map((row) => ({
      id: row.id,
      familyId: row.other_family_id,
      familyName: row.other_family_name,
      ownerId: row.owner_id,
      ownerName: row.owner_name,
      ownerEmail: row.owner_email,
      createdAt: row.created_at,
    })),
    incoming: (incoming.results ?? []).map((row) => ({
      id: row.id,
      token: row.token,
      familyId: row.family_id,
      familyName: row.family_name,
      invitedByName: row.invited_by_name,
      invitedByEmail: row.invited_by_email,
      expiresAt: row.expires_at,
      createdAt: row.created_at,
    })),
  });
});

connections.post("/invite", async (c) => {
  const body = await readLimitedJson<{ targetEmail?: string }>(c.req.raw);
  const targetEmail = normalizeEmail(body?.targetEmail ?? "");
  if (!isValidEmail(targetEmail)) {
    return c.json({ error: "Érvényes tulajdonosi email kell" }, 400);
  }

  const source = await getUserFamily(c.env.DB, c.get("userId"));
  if (!source || source.owner_id !== c.get("userId")) {
    return c.json({ error: "Ismerős családot csak a tulajdonos adhat hozzá" }, 403);
  }

  const target = await getUserByEmail(c.env.DB, targetEmail);
  const targetFamily = target ? await getUserFamily(c.env.DB, target.id) : null;
  if (!target || !targetFamily || targetFamily.owner_id !== target.id) {
    return c.json({ error: "Ehhez az emailhez nem tartozik családtulajdonos" }, 404);
  }
  if (targetFamily.id === source.id) {
    return c.json({ error: "A saját családodat nem lehet hozzáadni" }, 400);
  }

  const [familyA, familyB] = orderedPair(source.id, targetFamily.id);
  const existing = await c.env.DB.prepare(
    `SELECT status FROM family_connections
     WHERE family_a_id = ? AND family_b_id = ?`,
  )
    .bind(familyA, familyB)
    .first<{ status: string }>();
  if (existing?.status === "active") {
    return c.json({ error: "A két család már össze van kapcsolva" }, 409);
  }

  const token = inviteToken();
  const inviteId = id("fli");
  await c.env.DB.batch([
    c.env.DB.prepare(
      `UPDATE family_link_invites SET status = 'revoked'
       WHERE source_family_id = ? AND lower(target_email) = lower(?) AND status = 'pending'`,
    ).bind(source.id, targetEmail),
    c.env.DB.prepare(
      `INSERT INTO family_link_invites
       (id, source_family_id, target_email, token, invited_by, expires_at)
       VALUES (?, ?, ?, ?, ?, ?)`,
    ).bind(inviteId, source.id, targetEmail, token, c.get("userId"), addDays(14)),
  ]);

  const url = `${publicBaseUrl(c.req.url, c.env)}/family-link/${token}`;
  let emailSent = false;
  try {
    const mail = familyConnectionEmail(
      c.env.APP_NAME,
      source.name,
      c.get("user").name,
      url,
    );
    await sendEmail(c.env, { to: targetEmail, ...mail });
    emailSent = true;
  } catch (err) {
    console.error("[family connection email]", err);
  }

  return c.json({
    invite: {
      id: inviteId,
      url,
      targetEmail,
      targetFamilyName: targetFamily.name,
      expiresAt: addDays(14),
      emailSent,
    },
  }, 201);
});

connections.get("/invite/:token", async (c) => {
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.id, i.source_family_id, i.target_email, i.status, i.expires_at,
            f.name AS source_family_name, u.name AS inviter_name
     FROM family_link_invites i
     JOIN families f ON f.id = i.source_family_id
     JOIN users u ON u.id = i.invited_by
     WHERE i.token = ?`,
  )
    .bind(token)
    .first<{
      id: string;
      source_family_id: string;
      target_email: string;
      status: string;
      expires_at: string;
      source_family_name: string;
      inviter_name: string;
    }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.json({ error: "Érvénytelen vagy lejárt családi kapcsolat" }, 404);
  }
  return c.json({
    invite: {
      id: invite.id,
      familyId: invite.source_family_id,
      familyName: invite.source_family_name,
      targetEmail: invite.target_email,
      inviterName: invite.inviter_name,
      expiresAt: invite.expires_at,
    },
  });
});

connections.post("/invite/:token/accept", async (c) => {
  const token = c.req.param("token");
  const user = c.get("user");
  const invite = await c.env.DB.prepare(
    `SELECT * FROM family_link_invites WHERE token = ?`,
  )
    .bind(token)
    .first<{
      id: string;
      source_family_id: string;
      target_email: string;
      status: string;
      expires_at: string;
    }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.json({ error: "Érvénytelen vagy lejárt családi kapcsolat" }, 404);
  }
  if (normalizeEmail(user.email) !== normalizeEmail(invite.target_email)) {
    return c.json({ error: "Ez a kapcsolat másik email címre szól" }, 403);
  }

  const source = await getFamily(c.env.DB, invite.source_family_id);
  const target = await getUserFamily(c.env.DB, user.id);
  if (!source || !target || target.owner_id !== user.id) {
    return c.json({ error: "Csak egy család tulajdonosa fogadhatja el" }, 403);
  }
  if (source.id === target.id) {
    return c.json({ error: "A saját családodat nem lehet hozzáadni" }, 400);
  }

  const [familyA, familyB] = orderedPair(source.id, target.id);
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO family_connections
       (id, family_a_id, family_b_id, status, created_by)
       VALUES (?, ?, ?, 'active', ?)
       ON CONFLICT(family_a_id, family_b_id)
       DO UPDATE SET status = 'active', revoked_at = NULL`,
    ).bind(id("fcon"), familyA, familyB, user.id),
    c.env.DB.prepare(
      `UPDATE family_link_invites
       SET status = 'accepted', accepted_by = ?, accepted_at = datetime('now')
       WHERE id = ?`,
    ).bind(user.id, invite.id),
  ]);

  return c.json({
    ok: true,
    family: { id: source.id, name: source.name },
  });
});

connections.delete("/:id", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  const connectionId = c.req.param("id");
  if (!family || family.owner_id !== c.get("userId")) {
    return c.json({ error: "Csak tulajdonos vonhatja vissza" }, 403);
  }
  const connection = await c.env.DB.prepare(
    `SELECT family_a_id, family_b_id FROM family_connections
     WHERE id = ? AND status = 'active'`,
  )
    .bind(connectionId)
    .first<{ family_a_id: string; family_b_id: string }>();
  if (!connection) return c.json({ error: "Kapcsolat nem található" }, 404);
  if (connection.family_a_id !== family.id && connection.family_b_id !== family.id) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }
  await c.env.DB.prepare(
    `UPDATE family_connections SET status = 'revoked', revoked_at = datetime('now')
     WHERE id = ?`,
  ).bind(connectionId).run();
  return c.json({ ok: true });
});

connections.get("/nearby", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ people: [] });
  const query = (c.req.query("q") ?? "").trim().toLowerCase().slice(0, 80);
  const pattern = `%${query}%`;
  const rows = await c.env.DB.prepare(
    `SELECT DISTINCT u.id, u.name, u.email, u.avatar_key,
            f.id AS family_id, f.name AS family_name, fc.id AS connection_id
     FROM family_connections fc
     JOIN families f ON f.id = CASE
       WHEN fc.family_a_id = ? THEN fc.family_b_id
       ELSE fc.family_a_id
     END
     JOIN family_members fm ON fm.family_id = f.id
     JOIN users u ON u.id = fm.user_id
     WHERE (fc.family_a_id = ? OR fc.family_b_id = ?)
       AND fc.status = 'active'
       AND u.id != ?
       AND (? = '' OR lower(u.name) LIKE ? OR lower(u.email) LIKE ?)
     ORDER BY u.name
     LIMIT 100`,
  )
    .bind(family.id, family.id, family.id, c.get("userId"), query, pattern, pattern)
    .all<{
      id: string;
      name: string;
      email: string;
      avatar_key: string | null;
      family_id: string;
      family_name: string;
      connection_id: string;
    }>();

  return c.json({ people: (rows.results ?? []).map(publicPerson) });
});

connections.post("/nearby/contacts", async (c) => {
  const body = await readLimitedJson<{ emails?: unknown }>(c.req.raw);
  const emails = Array.isArray(body?.emails)
    ? [...new Set(
        body.emails
          .filter((email): email is string => typeof email === "string")
          .map(normalizeEmail)
          .filter(isValidEmail),
      )].slice(0, 300)
    : [];

  if (emails.length === 0) return c.json({ people: [] });
  await c.env.DB.prepare(
    `UPDATE users SET contact_discoverable = 1 WHERE id = ?`,
  ).bind(c.get("userId")).run();

  const placeholders = emails.map(() => "?").join(", ");
  const rows = await c.env.DB.prepare(
    `SELECT id, name, email, avatar_key
     FROM users
     WHERE contact_discoverable = 1
       AND id != ?
       AND lower(email) IN (${placeholders})
     ORDER BY name
     LIMIT 100`,
  )
    .bind(c.get("userId"), ...emails)
    .all<{ id: string; name: string; email: string; avatar_key: string | null }>();

  return c.json({
    people: (rows.results ?? []).map((row) => publicPerson(row)),
  });
});

connections.post("/nearby/:userId/request", async (c) => {
  const targetId = c.req.param("userId");
  const me = c.get("userId");
  if (targetId === me) return c.json({ error: "Saját magad nem adható hozzá" }, 400);
  const target = await getUserById(c.env.DB, targetId);
  if (!target || !target.contact_discoverable) {
    return c.json({ error: "Ez a felhasználó nem kereshető" }, 404);
  }
  const ownFamily = await getUserFamily(c.env.DB, me);
  const targetFamily = await getUserFamily(c.env.DB, targetId);
  if (ownFamily && targetFamily && ownFamily.id === targetFamily.id) {
    return c.json({ error: "Már egy családban vagytok" }, 400);
  }

  const [userA, userB] = orderedPair(me, targetId);
  await c.env.DB.prepare(
    `INSERT INTO user_connections
       (id, user_a_id, user_b_id, status, requested_by)
     VALUES (?, ?, ?, 'pending', ?)
     ON CONFLICT(user_a_id, user_b_id)
     DO UPDATE SET status = 'pending', requested_by = ?`,
  )
    .bind(id("ucn"), userA, userB, me, me)
    .run();
  return c.json({ ok: true, status: "pending" }, 201);
});

connections.get("/nearby/requests", async (c) => {
  const me = c.get("userId");
  const rows = await c.env.DB.prepare(
    `SELECT uc.id, uc.status, uc.requested_by, uc.created_at,
            u.id AS other_id, u.name AS other_name, u.email AS other_email,
            u.avatar_key AS other_avatar
     FROM user_connections uc
     JOIN users u ON u.id = CASE WHEN uc.user_a_id = ? THEN uc.user_b_id ELSE uc.user_a_id END
     WHERE (uc.user_a_id = ? OR uc.user_b_id = ?)
       AND uc.status IN ('pending', 'accepted')
     ORDER BY uc.created_at DESC
     LIMIT 100`,
  )
    .bind(me, me, me)
    .all<{
      id: string;
      status: string;
      requested_by: string;
      created_at: string;
      other_id: string;
      other_name: string;
      other_email: string;
      other_avatar: string | null;
    }>();
  return c.json({
    requests: (rows.results ?? []).map((row) => ({
      id: row.id,
      status: row.status,
      incoming: row.requested_by !== me,
      requestedBy: row.requested_by,
      createdAt: row.created_at,
      user: publicPerson({
        id: row.other_id,
        name: row.other_name,
        email: row.other_email,
        avatar_key: row.other_avatar,
      }),
    })),
  });
});

connections.post("/nearby/requests/:id/accept", async (c) => {
  const me = c.get("userId");
  const requestId = c.req.param("id");
  const row = await c.env.DB.prepare(
    `SELECT user_a_id, user_b_id, requested_by, status
     FROM user_connections WHERE id = ?`,
  )
    .bind(requestId)
    .first<{
      user_a_id: string;
      user_b_id: string;
      requested_by: string;
      status: string;
    }>();
  if (!row || row.status !== "pending") {
    return c.json({ error: "Kapcsolatkérés nem található" }, 404);
  }
  if (row.user_a_id !== me && row.user_b_id !== me || row.requested_by === me) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }
  await c.env.DB.prepare(
    `UPDATE user_connections SET status = 'accepted', accepted_at = datetime('now')
     WHERE id = ?`,
  ).bind(requestId).run();
  return c.json({ ok: true });
});

connections.patch("/discoverability", async (c) => {
  const body = await readLimitedJson<{ enabled?: boolean }>(c.req.raw);
  await c.env.DB.prepare(
    `UPDATE users SET contact_discoverable = ?, updated_at = datetime('now') WHERE id = ?`,
  ).bind(body?.enabled === true ? 1 : 0, c.get("userId")).run();
  return c.json({ enabled: body?.enabled === true });
});

export default connections;
