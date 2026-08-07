import { Hono } from "hono";
import type { Env, Variables } from "../types";
import {
  addDays,
  hmacSha256,
  id,
  inviteToken,
  isExpired,
  normalizeEmail,
  sessionToken,
  sha256,
  sixDigitCode,
  timingSafeEqual,
} from "../lib/crypto";
import {
  canAddMember,
  getFamily,
  getUserByEmail,
  getUserFamily,
  isFamilyMember,
  memberCount,
} from "../lib/db";
import { inviteEmail, loginCodeEmail, sendEmail } from "../lib/email";
import { getStripe } from "../lib/stripe";
import { optionalAuth } from "../middleware/auth";
import {
  accountPage,
  inviteAcceptPage,
  landingPage,
  loginPage,
  verifyPage,
} from "../web/pages";

const web = new Hono<{ Bindings: Env; Variables: Variables }>();

web.get("/", (c) => c.html(landingPage()));

web.get("/login", (c) => c.html(loginPage()));

web.post("/login", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const name = String(form.name ?? "").trim();
  const visionAssist = form.visionAssist === "1";

  if (!email.includes("@") || name.length < 2) {
    return c.html(loginPage("Név és érvényes email kell."), 400);
  }

  const code = sixDigitCode();
  const codeHash = await sha256(`${email}:${code}:${c.env.SESSION_SECRET}`);
  await c.env.DB.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email).run();
  await c.env.DB.prepare(
    `INSERT INTO auth_codes (id, email, name, vision_assist, code_hash, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      id("ac"),
      email,
      name,
      visionAssist ? 1 : 0,
      codeHash,
      new Date(Date.now() + 10 * 60_000).toISOString(),
    )
    .run();

  const mail = loginCodeEmail(c.env.APP_NAME, name, code);
  await sendEmail(c.env, { to: email, ...mail });

  return c.html(verifyPage(email));
});

web.post("/login/verify", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const code = String(form.code ?? "").trim();

  const row = await c.env.DB.prepare(
    "SELECT * FROM auth_codes WHERE email = ? ORDER BY created_at DESC LIMIT 1",
  )
    .bind(email)
    .first<{
      id: string;
      name: string;
      vision_assist: number;
      code_hash: string;
      attempts: number;
      expires_at: string;
    }>();

  if (!row || isExpired(row.expires_at) || row.attempts >= 5) {
    return c.html(verifyPage(email, "A kód lejárt vagy túl sok próbálkozás."), 400);
  }

  const expected = await sha256(`${email}:${code}:${c.env.SESSION_SECRET}`);
  if (!timingSafeEqual(expected, row.code_hash)) {
    await c.env.DB.prepare("UPDATE auth_codes SET attempts = attempts + 1 WHERE id = ?")
      .bind(row.id)
      .run();
    return c.html(verifyPage(email, "Hibás kód."), 400);
  }

  await c.env.DB.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email).run();

  let user = await getUserByEmail(c.env.DB, email);
  if (!user) {
    await c.env.DB.prepare(
      `INSERT INTO users (id, email, name, vision_assist) VALUES (?, ?, ?, ?)`,
    )
      .bind(id("usr"), email, row.name, row.vision_assist)
      .run();
    user = await getUserByEmail(c.env.DB, email);
  } else {
    await c.env.DB.prepare(
      `UPDATE users SET name = ?, vision_assist = ?, updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(row.name, row.vision_assist, user.id)
      .run();
    user = await getUserByEmail(c.env.DB, email);
  }

  const token = sessionToken();
  const tokenHash = await hmacSha256(c.env.SESSION_SECRET!, token);
  await c.env.DB.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`,
  )
    .bind(id("ses"), user!.id, tokenHash, addDays(60))
    .run();

  c.header(
    "Set-Cookie",
    `myuzi_session=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`,
  );
  return c.redirect("/account");
});

web.post("/logout", async (c) => {
  c.header("Set-Cookie", "myuzi_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0");
  return c.redirect("/");
});

web.get("/account", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");

  const family = await getUserFamily(c.env.DB, user.id);
  let members: Array<{ id: string; name: string; email: string; role: string }> = [];
  if (family) {
    const rows = await c.env.DB.prepare(
      `SELECT u.id, u.name, u.email, fm.role
       FROM family_members fm JOIN users u ON u.id = fm.user_id
       WHERE fm.family_id = ? ORDER BY fm.joined_at`,
    )
      .bind(family.id)
      .all<{ id: string; name: string; email: string; role: string }>();
    members = rows.results ?? [];
  }

  const billing = c.req.query("billing");
  const message =
    billing === "success"
      ? "Sikeres előfizetés — köszönjük!"
      : billing === "cancel"
        ? "Az előfizetés megszakítva."
        : undefined;

  return c.html(accountPage({ user, family, members, message }));
});

web.post("/account/family", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  if (await getUserFamily(c.env.DB, user.id)) return c.redirect("/account");

  const form = await c.req.parseBody();
  const name = String(form.name ?? "").trim();
  if (name.length < 2) return c.redirect("/account");

  const familyId = id("fam");
  await c.env.DB.batch([
    c.env.DB.prepare(
      `INSERT INTO families (id, name, owner_id, plan, max_members) VALUES (?, ?, ?, 'none', 6)`,
    ).bind(familyId, name, user.id),
    c.env.DB.prepare(
      `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'owner')`,
    ).bind(familyId, user.id),
  ]);
  return c.redirect("/account");
});

web.post("/account/invite", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family) return c.redirect("/account");

  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) {
    return c.html(
      accountPage({
        user,
        family,
        members: [],
        error: "Elérted a létszámlimitet. Válts nagyobb csomagra az előfizetésnél.",
      }),
    );
  }

  const form = await c.req.parseBody();
  const emailRaw = String(form.email ?? "").trim();
  const email = emailRaw ? normalizeEmail(emailRaw) : null;
  const token = inviteToken();
  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(id("inv"), family.id, email, token, user.id, addDays(14))
    .run();

  const inviteUrl = `${c.env.APP_URL}/invite/${token}`;
  if (email) {
    const mail = inviteEmail(c.env.APP_NAME, family.name, user.name, inviteUrl);
    await sendEmail(c.env, { to: email, ...mail });
  }

  const members = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.email, fm.role
     FROM family_members fm JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = ?`,
  )
    .bind(family.id)
    .all<{ id: string; name: string; email: string; role: string }>();

  return c.html(
    accountPage({
      user,
      family,
      members: members.results ?? [],
      inviteUrl,
      message: email ? "Meghívó elküldve emailben." : "Meghívó link kész.",
    }),
  );
});

web.post("/account/vision", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const form = await c.req.parseBody();
  const vision = form.visionAssist === "1" ? 1 : 0;
  await c.env.DB.prepare(
    `UPDATE users SET vision_assist = ?, updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(vision, user.id)
    .run();
  return c.redirect("/account");
});

web.post("/account/checkout", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family || family.owner_id !== user.id) return c.redirect("/account");

  const form = await c.req.parseBody();
  const plan = String(form.plan ?? "");
  if (plan !== "family" && plan !== "family_plus") return c.redirect("/account");

  const stripe = getStripe(c.env);
  let customerId = family.stripe_customer_id;
  if (!customerId) {
    const customer = await stripe.customers.create({
      email: user.email,
      name: user.name,
      metadata: { familyId: family.id, userId: user.id },
    });
    customerId = customer.id;
    await c.env.DB.prepare(
      `UPDATE families SET stripe_customer_id = ?, updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(customerId, family.id)
      .run();
  }

  const priceId =
    plan === "family" ? c.env.STRIPE_PRICE_FAMILY : c.env.STRIPE_PRICE_FAMILY_PLUS;
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer: customerId,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${c.env.APP_URL}/account?billing=success`,
    cancel_url: `${c.env.APP_URL}/account?billing=cancel`,
    metadata: { familyId: family.id, plan },
    subscription_data: { metadata: { familyId: family.id, plan } },
  });

  return c.redirect(session.url ?? "/account");
});

web.post("/account/portal", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family?.stripe_customer_id || family.owner_id !== user.id) {
    return c.redirect("/account");
  }
  const stripe = getStripe(c.env);
  const portal = await stripe.billingPortal.sessions.create({
    customer: family.stripe_customer_id,
    return_url: `${c.env.APP_URL}/account`,
  });
  return c.redirect(portal.url);
});

web.get("/invite/:token", optionalAuth, async (c) => {
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.*, f.name AS family_name FROM invites i
     JOIN families f ON f.id = i.family_id WHERE i.token = ?`,
  )
    .bind(token)
    .first<{ family_name: string; status: string; expires_at: string }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.html(landingPage());
  }

  return c.html(inviteAcceptPage(invite.family_name, token, !!c.get("user")));
});

web.post("/invite/:token/accept", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const token = c.req.param("token");

  if (await getUserFamily(c.env.DB, user.id)) return c.redirect("/account");

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
    return c.redirect("/");
  }
  if (invite.email && invite.email !== user.email) return c.redirect("/account");

  const family = await getFamily(c.env.DB, invite.family_id);
  if (!family) return c.redirect("/");
  const count = await memberCount(c.env.DB, family.id);
  if (!canAddMember(family, count)) return c.redirect("/account");
  if (!(await isFamilyMember(c.env.DB, family.id, user.id))) {
    await c.env.DB.batch([
      c.env.DB.prepare(
        `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'member')`,
      ).bind(family.id, user.id),
      c.env.DB.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id),
    ]);
  }

  return c.redirect("/account");
});

export default web;
