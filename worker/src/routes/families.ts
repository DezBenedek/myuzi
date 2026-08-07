import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { id } from "../lib/crypto";
import {
  canAddMember,
  getFamily,
  getUserFamily,
  memberCount,
  publicFamily,
  publicUser,
} from "../lib/db";
import { requireAuth } from "../middleware/auth";

const families = new Hono<{ Bindings: Env; Variables: Variables }>();

families.use("*", requireAuth);

families.get("/mine", async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ family: null, members: [] });

  const members = await c.env.DB.prepare(
    `SELECT u.*, fm.role AS member_role
     FROM family_members fm
     JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = ?
     ORDER BY fm.joined_at ASC`,
  )
    .bind(family.id)
    .all<{
      id: string;
      email: string;
      name: string;
      vision_assist: number;
      push_token: string | null;
      push_platform: string | null;
      created_at: string;
      updated_at: string;
      member_role: string;
    }>();

  return c.json({
    family: publicFamily(family),
    members: (members.results ?? []).map((m) => ({
      ...publicUser(m),
      role: m.member_role,
    })),
  });
});

families.post("/", async (c) => {
  const existing = await getUserFamily(c.env.DB, c.get("userId"));
  if (existing) {
    return c.json({ error: "Már van családod. Egy személy csak egy családhoz tartozhat." }, 409);
  }

  const body = await c.req.json<{ name?: string }>();
  const name = (body.name ?? "").trim();
  if (name.length < 2) return c.json({ error: "Adj nevet a családnak" }, 400);

  const familyId = id("fam");
  const userId = c.get("userId");

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO families (id, name, owner_id, plan, max_members) VALUES (?, ?, ?, 'none', 3)`,
    ).bind(familyId, name, userId),
    c.env.DB.prepare(
      `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'owner')`,
    ).bind(familyId, userId),
  ]);

  const family = await getFamily(c.env.DB, familyId);
  return c.json({ family: publicFamily({ ...family!, role: "owner" }) }, 201);
});

families.patch("/:id", async (c) => {
  const familyId = c.req.param("id");
  const family = await getFamily(c.env.DB, familyId);
  if (!family) return c.json({ error: "Nem található" }, 404);
  if (family.owner_id !== c.get("userId")) {
    return c.json({ error: "Csak a tulajdonos módosíthatja" }, 403);
  }

  const body = await c.req.json<{ name?: string }>();
  const name = (body.name ?? "").trim();
  if (name.length < 2) return c.json({ error: "Érvénytelen név" }, 400);

  await c.env.DB.prepare(
    `UPDATE families SET name = ?, updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(name, familyId)
    .run();

  const updated = await getFamily(c.env.DB, familyId);
  return c.json({ family: publicFamily({ ...updated!, role: "owner" }) });
});

families.delete("/:id/members/:userId", async (c) => {
  const familyId = c.req.param("id");
  const targetUserId = c.req.param("userId");
  const family = await getFamily(c.env.DB, familyId);
  if (!family) return c.json({ error: "Nem található" }, 404);

  const me = c.get("userId");
  if (family.owner_id !== me && targetUserId !== me) {
    return c.json({ error: "Nincs jogosultság" }, 403);
  }
  if (targetUserId === family.owner_id) {
    return c.json({ error: "A tulajdonos nem távolítható el" }, 400);
  }

  await c.env.DB.prepare(
    "DELETE FROM family_members WHERE family_id = ? AND user_id = ?",
  )
    .bind(familyId, targetUserId)
    .run();

  return c.json({ ok: true });
});

families.get("/:id/capacity", async (c) => {
  const family = await getFamily(c.env.DB, c.req.param("id"));
  if (!family) return c.json({ error: "Nem található" }, 404);
  const count = await memberCount(c.env.DB, family.id);
  return c.json({
    count,
    max: family.max_members,
    canAdd: canAddMember(family, count),
    plan: family.plan,
  });
});

export default families;
