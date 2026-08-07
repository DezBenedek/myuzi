import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { addDays, id, inviteToken, isExpired, normalizeEmail } from "../lib/crypto";
import {
  canAddMember,
  getFamily,
  getUserFamily,
  isFamilyMember,
  memberCount,
  publicFamily,
} from "../lib/db";
import { inviteEmail, sendEmail } from "../lib/email";
import { requireAuth } from "../middleware/auth";

const invites = new Hono<{ Bindings: Env; Variables: Variables }>();

invites.post("/", requireAuth, async (c) => {
  const body = await c.req.json<{ email?: string }>();
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Előbb hozz létre családot" }, 400);
  if (family.role !== "owner" && family.owner_id !== c.get("userId")) {
    // any member can invite for simplicity of elderly UX
  }

  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) {
    return c.json(
      {
        error: `Elérted a ${family.max_members} fős limittet. A webes fiókkezelőben válthatsz nagyobb csomagra.`,
        softPaywall: true,
      },
      403,
    );
  }

  const email = body.email ? normalizeEmail(body.email) : null;
  const token = inviteToken();
  const inviteId = id("inv");

  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(inviteId, family.id, email, token, c.get("userId"), addDays(14))
    .run();

  const inviteUrl = `${c.env.APP_URL}/invite/${token}`;

  if (email) {
    const mail = inviteEmail(c.env.APP_NAME, family.name, c.get("user").name, inviteUrl);
    await sendEmail(c.env, { to: email, ...mail });
  }

  return c.json({
    invite: {
      id: inviteId,
      token,
      url: inviteUrl,
      email,
      expiresAt: addDays(14),
    },
  });
});

invites.get("/:token", async (c) => {
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.*, f.name AS family_name
     FROM invites i JOIN families f ON f.id = i.family_id
     WHERE i.token = ?`,
  )
    .bind(token)
    .first<{
      id: string;
      family_id: string;
      family_name: string;
      status: string;
      expires_at: string;
      email: string | null;
    }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.json({ error: "Érvénytelen vagy lejárt meghívó" }, 404);
  }

  return c.json({
    invite: {
      familyId: invite.family_id,
      familyName: invite.family_name,
      email: invite.email,
    },
  });
});

invites.post("/:token/accept", requireAuth, async (c) => {
  const token = c.req.param("token");
  const userId = c.get("userId");

  const existing = await getUserFamily(c.env.DB, userId);
  if (existing) {
    return c.json({ error: "Már van családod" }, 409);
  }

  const invite = await c.env.DB.prepare("SELECT * FROM invites WHERE token = ?")
    .bind(token)
    .first<{
      id: string;
      family_id: string;
      status: string;
      expires_at: string;
      email: string | null;
    }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.json({ error: "Érvénytelen vagy lejárt meghívó" }, 404);
  }

  if (invite.email && invite.email !== c.get("user").email) {
    return c.json({ error: "Ez a meghívó másik emailcímre szól" }, 403);
  }

  const family = await getFamily(c.env.DB, invite.family_id);
  if (!family) return c.json({ error: "Család nem található" }, 404);

  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) {
    return c.json({ error: "A család megtelt", softPaywall: true }, 403);
  }

  if (await isFamilyMember(c.env.DB, family.id, userId)) {
    return c.json({ family: publicFamily({ ...family, role: "member" }) });
  }

  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'member')`,
    ).bind(family.id, userId),
    c.env.DB.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id),
  ]);

  return c.json({ family: publicFamily({ ...family, role: "member" }) });
});

export default invites;
