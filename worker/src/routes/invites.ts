import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { addDays, id, inviteToken, isExpired, normalizeEmail } from "../lib/crypto";
import {
  canAddMember,
  getFamily,
  getUserById,
  getUserFamily,
  hasPaidPlan,
  isFamilyMember,
  leaveCurrentFamily,
  memberCount,
  publicFamily,
} from "../lib/db";
import { inviteEmail, sendEmail } from "../lib/email";
import { sendPush } from "../lib/push";
import { publicBaseUrl } from "../lib/urls";
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
        error: hasPaidPlan(family.plan)
          ? `Elérted a ${family.max_members} fős limittet. Válts nagyobb csomagra.`
          : "Ingyenes csomag: max 3 fő. Több taghoz fizess elő.",
        softPaywall: true,
      },
      403,
    );
  }

  const email = body.email ? normalizeEmail(body.email) : null;
  if (!email || !email.includes("@")) {
    return c.json({ error: "Meghívóhoz email cím kell" }, 400);
  }
  const token = inviteToken();
  const inviteId = id("inv");

  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(inviteId, family.id, email, token, c.get("userId"), addDays(14))
    .run();

  const inviteUrl = `${publicBaseUrl(c.req.url, c.env)}/invite/${token}`;
  let emailSent = false;
  let emailWarning: string | undefined;

  try {
    const mail = inviteEmail(c.env.APP_NAME, family.name, c.get("user").name, inviteUrl);
    await sendEmail(c.env, { to: email, ...mail });
    emailSent = true;
  } catch (err) {
    console.error("[invite email]", err);
    emailWarning =
      "A meghívó link elkészült, de az email küldése nem sikerült. Másold ki a linket.";
  }

  return c.json({
    invite: {
      id: inviteId,
      token,
      url: inviteUrl,
      email,
      expiresAt: addDays(14),
      emailSent,
      emailWarning,
    },
  });
});

/** Invite an existing user (e.g. via QR) into the caller's family. */
invites.post("/user", requireAuth, async (c) => {
  const body = await c.req.json<{ userId?: string }>();
  const targetId = (body.userId ?? "").trim();
  if (!targetId) return c.json({ error: "userId kell" }, 400);

  const me = c.get("user");
  if (targetId === me.id) {
    return c.json({ error: "Saját magadat nem hívhatod meg" }, 400);
  }

  const family = await getUserFamily(c.env.DB, me.id);
  if (!family) return c.json({ error: "Előbb hozz létre családot" }, 400);

  const target = await getUserById(c.env.DB, targetId);
  if (!target) return c.json({ error: "Felhasználó nem található" }, 404);

  if (await isFamilyMember(c.env.DB, family.id, targetId)) {
    return c.json({ error: "Már a családodban van" }, 400);
  }

  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) {
    return c.json(
      {
        error: hasPaidPlan(family.plan)
          ? `Elérted a ${family.max_members} fős limittet.`
          : "Ingyenes csomag: max 3 fő. Több taghoz fizess elő.",
        softPaywall: true,
      },
      403,
    );
  }

  const targetFamily = await getUserFamily(c.env.DB, targetId);
  const token = inviteToken();
  const inviteId = id("inv");

  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(inviteId, family.id, target.email, token, me.id, addDays(14))
    .run();

  const inviteUrl = `${publicBaseUrl(c.req.url, c.env)}/invite/${token}`;

  if (target.push_token) {
    c.executionCtx.waitUntil(
      sendPush(c.env, {
        token: target.push_token,
        title: "Családi meghívó",
        body: `${me.name} meghívott a(z) ${family.name} családba`,
        kind: "message",
        data: {
          type: "family_invite",
          token,
          familyName: family.name,
          fromName: me.name,
        },
      }),
    );
  }

  try {
    const mail = inviteEmail(c.env.APP_NAME, family.name, me.name, inviteUrl);
    await sendEmail(c.env, { to: target.email, ...mail });
  } catch (err) {
    console.error("[invite-by-user email]", err);
  }

  return c.json({
    invite: {
      id: inviteId,
      token,
      url: inviteUrl,
      targetUserId: targetId,
      targetName: target.name,
      targetHasFamily: !!targetFamily,
      targetFamilyName: targetFamily?.name ?? null,
    },
    message: targetFamily
      ? `${target.name} meghívva. Elfogadáskor ki kell lépnie a(z) ${targetFamily.name} családból.`
      : `${target.name} meghívva a családodba.`,
  });
});

/** Pending invites addressed to the current user. */
invites.get("/inbox", requireAuth, async (c) => {
  const user = c.get("user");
  const rows = await c.env.DB.prepare(
    `SELECT i.token, i.expires_at, i.created_at,
            f.name AS family_name, f.id AS family_id,
            u.name AS invited_by_name
     FROM invites i
     JOIN families f ON f.id = i.family_id
     JOIN users u ON u.id = i.invited_by
     WHERE i.status = 'pending'
       AND i.email IS NOT NULL AND lower(i.email) = lower(?)
       AND i.expires_at > datetime('now')
     ORDER BY i.created_at DESC
     LIMIT 20`,
  )
    .bind(user.email)
    .all<{
      token: string;
      expires_at: string;
      created_at: string;
      family_name: string;
      family_id: string;
      invited_by_name: string;
    }>();

  const myFamily = await getUserFamily(c.env.DB, user.id);

  return c.json({
    invites: (rows.results ?? []).map((r) => ({
      token: r.token,
      familyId: r.family_id,
      familyName: r.family_name,
      invitedByName: r.invited_by_name,
      expiresAt: r.expires_at,
      createdAt: r.created_at,
      needsLeave: !!myFamily && myFamily.id !== r.family_id,
      currentFamilyName: myFamily && myFamily.id !== r.family_id ? myFamily.name : null,
    })),
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
      target_user_id: string | null;
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
  const user = c.get("user");

  let confirmLeave = false;
  try {
    const body = await c.req.json<{ confirmLeave?: boolean }>();
    confirmLeave = body.confirmLeave === true;
  } catch {
    // empty body ok
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

  if (!invite.email || invite.email.toLowerCase() !== user.email.toLowerCase()) {
    return c.json({ error: "Ez a meghívó másik emailcímre szól" }, 403);
  }

  const family = await getFamily(c.env.DB, invite.family_id);
  if (!family) return c.json({ error: "Család nem található" }, 404);

  const existing = await getUserFamily(c.env.DB, userId);
  if (existing && existing.id === family.id) {
    await c.env.DB.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`)
      .bind(invite.id)
      .run();
    return c.json({ family: publicFamily({ ...family, role: existing.role }) });
  }

  if (existing && existing.id !== family.id) {
    if (!confirmLeave) {
      return c.json(
        {
          error: `Már a(z) ${existing.name} család tagja vagy. Elfogadáshoz ki kell lépned.`,
          needsLeaveConfirmation: true,
          currentFamilyName: existing.name,
          targetFamilyName: family.name,
        },
        409,
      );
    }
    const left = await leaveCurrentFamily(c.env.DB, userId);
    if (!left.ok) return c.json({ error: left.error }, 400);
  }

  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) {
    return c.json(
      {
        error: hasPaidPlan(family.plan)
          ? "A család megtelt"
          : "Ingyenes csomag: max 3 fő. A tulajdonosnak elő kell fizetnie.",
        softPaywall: true,
      },
      403,
    );
  }

  if (!(await isFamilyMember(c.env.DB, family.id, userId))) {
    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'member')`,
      ).bind(family.id, userId),
      c.env.DB.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id),
    ]);
  } else {
    await c.env.DB.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`)
      .bind(invite.id)
      .run();
  }

  return c.json({ family: publicFamily({ ...family, role: "member" }) });
});

export default invites;
