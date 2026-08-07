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
  hasPaidPlan,
  isFamilyMember,
  memberCount,
} from "../lib/db";
import { inviteEmail, loginCodeEmail, sendEmail } from "../lib/email";
import { getStripe, changePaidPlan, cancelAtPeriodEnd, resumeSubscription } from "../lib/stripe";
import { applyPlan } from "./billing";
import { publicBaseUrl } from "../lib/urls";
import { optionalAuth } from "../middleware/auth";
import {
  accountPage,
  billingPage,
  inviteAcceptPage,
  inviteEmailPage,
  landingPage,
  loginPage,
  plansPage,
  verifyPage,
} from "../web/pages";
import type { UserRow } from "../types";

const web = new Hono<{ Bindings: Env; Variables: Variables }>();

type InviteRow = {
  id: string;
  family_id: string;
  status: string;
  expires_at: string;
  email: string | null;
  family_name?: string;
};

async function sendLoginPin(
  env: Env,
  email: string,
  visionAssist = 0,
): Promise<void> {
  const existing = await getUserByEmail(env.DB, email);
  const displayName = existing?.name || "Felhasználó";
  const code = sixDigitCode();
  const codeHash = await sha256(`${email}:${code}:${env.SESSION_SECRET}`);
  await env.DB.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email).run();
  await env.DB.prepare(
    `INSERT INTO auth_codes (id, email, name, vision_assist, code_hash, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(
      id("ac"),
      email,
      existing?.name ?? "",
      visionAssist || existing?.vision_assist || 0,
      codeHash,
      new Date(Date.now() + 10 * 60_000).toISOString(),
    )
    .run();
  const mail = loginCodeEmail(env.APP_NAME, displayName, code);
  await sendEmail(env, { to: email, ...mail });
}

async function acceptInviteForUser(
  db: D1Database,
  invite: InviteRow,
  user: UserRow,
): Promise<{ ok: true } | { ok: false; error: string; familyName: string }> {
  const family = await getFamily(db, invite.family_id);
  if (!family) return { ok: false, error: "A család nem található.", familyName: "" };
  if (invite.email && invite.email !== user.email) {
    return {
      ok: false,
      error: `Ez a meghívó a(z) ${invite.email} címre szól.`,
      familyName: family.name,
    };
  }
  const existingFamily = await getUserFamily(db, user.id);
  if (existingFamily && existingFamily.id !== family.id) {
    return {
      ok: false,
      error: "Már egy másik családban vagy.",
      familyName: family.name,
    };
  }
  if (existingFamily?.id === family.id) {
    await db.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id).run();
    return { ok: true };
  }
  const count = await memberCount(db, family.id);
  if (!canAddMember(family, count)) {
    return {
      ok: false,
      error: hasPaidPlan(family.plan)
        ? "A család megtelt."
        : "Ingyenes: max 3 fő. A tulajdonosnak elő kell fizetnie.",
      familyName: family.name,
    };
  }
  if (!(await isFamilyMember(db, family.id, user.id))) {
    await db.batch([
      db
        .prepare(
          `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'member')`,
        )
        .bind(family.id, user.id),
      db.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id),
    ]);
  } else {
    await db.prepare(`UPDATE invites SET status = 'accepted' WHERE id = ?`).bind(invite.id).run();
  }
  return { ok: true };
}

function setSessionCookie(c: { header: (k: string, v: string) => void }, token: string) {
  c.header(
    "Set-Cookie",
    `myuzi_session=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`,
  );
}

web.get("/", (c) => c.html(landingPage()));

web.get("/login", (c) => c.html(loginPage()));

/** App → web SSO: one-time token becomes cookie session. */
web.get("/auth/bridge", async (c) => {
  const raw = (c.req.query("t") ?? "").trim();
  if (!raw) return c.redirect("/login");

  const tokenHash = await sha256(raw);
  const row = await c.env.DB.prepare(
    "SELECT id, user_id, expires_at FROM web_bridge_tokens WHERE token_hash = ?",
  )
    .bind(tokenHash)
    .first<{ id: string; user_id: string; expires_at: string }>();

  if (!row || isExpired(row.expires_at)) {
    if (row) {
      await c.env.DB.prepare("DELETE FROM web_bridge_tokens WHERE id = ?").bind(row.id).run();
    }
    return c.redirect("/login");
  }

  await c.env.DB.prepare("DELETE FROM web_bridge_tokens WHERE id = ?").bind(row.id).run();

  const token = sessionToken();
  const sessionHash = await hmacSha256(c.env.SESSION_SECRET, token);
  await c.env.DB.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`,
  )
    .bind(id("ses"), row.user_id, sessionHash, addDays(60))
    .run();

  c.header(
    "Set-Cookie",
    `myuzi_session=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`,
  );
  return c.redirect("/account");
});

web.post("/login", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const visionAssist = form.visionAssist === "1" ? 1 : 0;

  if (!email.includes("@")) {
    return c.html(loginPage("Érvényes email kell."), 400);
  }

  try {
    await sendLoginPin(c.env, email, visionAssist);
  } catch (err) {
    console.error("[login email]", err);
    return c.html(loginPage("A kód küldése nem sikerült. Próbáld újra."), 500);
  }

  return c.html(verifyPage(email));
});

web.post("/login/verify", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const code = String(form.code ?? "").trim();
  const name = String(form.name ?? "").trim();
  const inviteToken = String(form.inviteToken ?? "").trim();

  const inviteOpts = inviteToken
    ? await (async () => {
        const inv = await c.env.DB.prepare(
          `SELECT i.*, f.name AS family_name FROM invites i
           JOIN families f ON f.id = i.family_id WHERE i.token = ?`,
        )
          .bind(inviteToken)
          .first<InviteRow & { family_name: string }>();
        if (!inv || inv.status !== "pending" || isExpired(inv.expires_at)) return undefined;
        return { inviteToken, familyName: inv.family_name };
      })()
    : undefined;

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
    return c.html(
      verifyPage(email, "A kód lejárt vagy túl sok próbálkozás.", false, "", inviteOpts),
      400,
    );
  }

  const expected = await sha256(`${email}:${code}:${c.env.SESSION_SECRET}`);
  if (!timingSafeEqual(expected, row.code_hash)) {
    await c.env.DB.prepare("UPDATE auth_codes SET attempts = attempts + 1 WHERE id = ?")
      .bind(row.id)
      .run();
    return c.html(verifyPage(email, "Hibás kód.", false, "", inviteOpts), 400);
  }

  let user = await getUserByEmail(c.env.DB, email);
  if (!user) {
    if (name.length < 2) {
      return c.html(
        verifyPage(
          email,
          name ? "A becenév legalább 2 karakter legyen." : "",
          true,
          code,
          inviteOpts,
        ),
        name ? 400 : 200,
      );
    }
    await c.env.DB.prepare(
      `INSERT INTO users (id, email, name, vision_assist) VALUES (?, ?, ?, ?)`,
    )
      .bind(id("usr"), email, name, row.vision_assist)
      .run();
    user = await getUserByEmail(c.env.DB, email);
  }

  await c.env.DB.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email).run();

  const token = sessionToken();
  const tokenHash = await hmacSha256(c.env.SESSION_SECRET!, token);
  await c.env.DB.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`,
  )
    .bind(id("ses"), user!.id, tokenHash, addDays(60))
    .run();

  setSessionCookie(c, token);

  if (inviteToken) {
    const invite = await c.env.DB.prepare("SELECT * FROM invites WHERE token = ?")
      .bind(inviteToken)
      .first<InviteRow>();
    if (invite && invite.status === "pending" && !isExpired(invite.expires_at)) {
      const result = await acceptInviteForUser(c.env.DB, invite, user!);
      if (!result.ok) {
        return c.html(
          inviteAcceptPage(result.familyName || "család", inviteToken, true, result.error),
        );
      }
    }
  }

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
      : billing === "scheduled"
        ? "A csomagváltás a jelenlegi hónap végén lép életbe."
        : billing === "canceled"
          ? "Az előfizetés lemondva — a hónap végéig még érvényes."
          : billing === "resumed"
            ? "Az előfizetés folytatódik."
            : billing === "cancel"
              ? "A fizetés megszakítva."
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
      `INSERT INTO families (id, name, owner_id, plan, max_members) VALUES (?, ?, ?, 'none', 3)`,
    ).bind(familyId, name, user.id),
    c.env.DB.prepare(
      `INSERT INTO family_members (family_id, user_id, role) VALUES (?, ?, 'owner')`,
    ).bind(familyId, user.id),
  ]);
  return c.redirect("/account");
});

web.post("/account/members/remove", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family) return c.redirect("/account");

  const form = await c.req.parseBody();
  const targetUserId = String(form.userId ?? "").trim();
  if (!targetUserId) return c.redirect("/account");

  const isOwner = family.owner_id === user.id;
  if (!isOwner && targetUserId !== user.id) {
    return c.redirect("/account");
  }
  if (targetUserId === family.owner_id) {
    return c.redirect("/account");
  }

  await c.env.DB.prepare(
    "DELETE FROM family_members WHERE family_id = ? AND user_id = ?",
  )
    .bind(family.id, targetUserId)
    .run();

  return c.redirect("/account");
});

web.post("/account/invite", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family) return c.redirect("/account");

  const membersRows = await c.env.DB.prepare(
    `SELECT u.id, u.name, u.email, fm.role
     FROM family_members fm JOIN users u ON u.id = fm.user_id
     WHERE fm.family_id = ?`,
  )
    .bind(family.id)
    .all<{ id: string; name: string; email: string; role: string }>();
  const members = membersRows.results ?? [];

  if (!canAddMember(family, members.length)) {
    return c.html(
      accountPage({
        user,
        family,
        members,
        error: hasPaidPlan(family.plan)
          ? "Elérted a létszámlimitet."
          : "Ingyenes: max 3 fő. Több taghoz fizess elő.",
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

  const inviteUrl = `${publicBaseUrl(c.req.url, c.env)}/invite/${token}`;
  let message = email ? "Meghívó elküldve emailben." : "Meghívó link kész.";
  if (email) {
    try {
      const mail = inviteEmail(c.env.APP_NAME, family.name, user.name, inviteUrl);
      await sendEmail(c.env, { to: email, ...mail });
    } catch (err) {
      console.error("[invite email]", err);
      message =
        "A meghívó link elkészült, de az email küldése nem sikerült. Másold ki a linket lent.";
    }
  }

  return c.html(
    accountPage({
      user,
      family,
      members,
      inviteUrl,
      message,
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

web.get("/account/plans", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family || family.owner_id !== user.id) return c.redirect("/account");
  return c.html(plansPage({ user, currentPlan: family.plan }));
});

web.get("/account/billing", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family || family.owner_id !== user.id) return c.redirect("/account");

  const plan = String(c.req.query("plan") ?? "");
  if (plan !== "family" && plan !== "family_plus") return c.redirect("/account/plans");

  return c.html(billingPage({ user, plan, billing: family, currentPlan: family.plan }));
});

web.post("/account/checkout", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family || family.owner_id !== user.id) return c.redirect("/account");

  const form = await c.req.parseBody();
  const plan = String(form.plan ?? "");
  if (plan !== "family" && plan !== "family_plus") return c.redirect("/account/plans");

  const billingType = String(form.billingType ?? "individual");
  const billingName = String(form.billingName ?? "").trim();
  const taxId = String(form.taxId ?? "").trim();
  const addressLine1 = String(form.addressLine1 ?? "").trim();
  const city = String(form.city ?? "").trim();
  const postalCode = String(form.postalCode ?? "").trim();
  const country = String(form.country ?? "HU").trim().toUpperCase() || "HU";

  const billingDraft = {
    billing_type: billingType === "company" ? "company" : "individual",
    billing_name: billingName,
    billing_tax_id: taxId || null,
    billing_address_line1: addressLine1,
    billing_city: city,
    billing_postal_code: postalCode,
    billing_country: country,
  };

  if (billingName.length < 2 || !addressLine1 || !city || !postalCode) {
    return c.html(
      billingPage({
        user,
        plan,
        billing: billingDraft,
        currentPlan: family.plan,
        error: "Töltsd ki a számlázási adatokat (név, cím, város, irányítószám).",
      }),
      400,
    );
  }
  if (billingType === "company" && taxId.length < 5) {
    return c.html(
      billingPage({
        user,
        plan,
        billing: billingDraft,
        currentPlan: family.plan,
        error: "Cégnél adószám is kell.",
      }),
      400,
    );
  }

  // Persist for the owner — used for manual invoicing, not Stripe Checkout forms.
  await c.env.DB.prepare(
    `UPDATE families SET
      billing_type = ?, billing_name = ?, billing_tax_id = ?,
      billing_address_line1 = ?, billing_city = ?, billing_postal_code = ?,
      billing_country = ?, updated_at = datetime('now')
     WHERE id = ?`,
  )
    .bind(
      billingDraft.billing_type,
      billingName,
      taxId || null,
      addressLine1,
      city,
      postalCode,
      country,
      family.id,
    )
    .run();

  try {
    const stripe = getStripe(c.env);

    // Already subscribed → change plan (upgrade now / downgrade at period end).
    if (family.stripe_subscription_id && hasPaidPlan(family.plan)) {
      if (family.plan === plan) {
        return c.redirect("/account?billing=success");
      }
      const result = await changePaidPlan(stripe, c.env, {
        subscriptionId: family.stripe_subscription_id,
        currentPlan: family.plan,
        newPlan: plan,
        familyId: family.id,
      });
      if (result === "immediate") {
        await applyPlan(c.env, family.id, plan, {
          subscriptionId: family.stripe_subscription_id,
          customerId: family.stripe_customer_id,
          status: "active",
        });
        return c.redirect("/account?billing=success");
      }
      await c.env.DB.prepare(
        `UPDATE families SET stripe_status = ?, updated_at = datetime('now') WHERE id = ?`,
      )
        .bind(`pending:${plan}`, family.id)
        .run();
      return c.redirect("/account?billing=scheduled");
    }

    let customerId = family.stripe_customer_id;
    if (!customerId) {
      const customer = await stripe.customers.create({
        email: user.email,
        metadata: {
          familyId: family.id,
          userId: user.id,
        },
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
    const base = publicBaseUrl(c.req.url, c.env);
    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      line_items: [{ price: priceId, quantity: 1 }],
      success_url: `${base}/account?billing=success`,
      cancel_url: `${base}/account/billing?plan=${plan}`,
      metadata: {
        familyId: family.id,
        plan,
        billingType: billingDraft.billing_type,
      },
      subscription_data: { metadata: { familyId: family.id, plan } },
      allow_promotion_codes: true,
      billing_address_collection: "auto",
    });

    return c.redirect(session.url ?? "/account");
  } catch (err) {
    console.error("[checkout]", err);
    const msg = err instanceof Error ? err.message : "Fizetés indítása sikertelen";
    return c.html(
      billingPage({
        user,
        plan,
        billing: { ...family, ...billingDraft },
        currentPlan: family.plan,
        error: msg,
      }),
      500,
    );
  }
});

web.post("/account/cancel-subscription", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family?.stripe_subscription_id || family.owner_id !== user.id) {
    return c.redirect("/account");
  }
  try {
    const stripe = getStripe(c.env);
    await cancelAtPeriodEnd(stripe, family.stripe_subscription_id);
    await c.env.DB.prepare(
      `UPDATE families SET stripe_status = 'canceling', updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(family.id)
      .run();
    return c.redirect("/account?billing=canceled");
  } catch (err) {
    console.error("[cancel-subscription]", err);
    return c.redirect("/account");
  }
});

web.post("/account/resume-subscription", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const family = await getUserFamily(c.env.DB, user.id);
  if (!family?.stripe_subscription_id || family.owner_id !== user.id) {
    return c.redirect("/account");
  }
  try {
    const stripe = getStripe(c.env);
    await resumeSubscription(stripe, family.stripe_subscription_id);
    await c.env.DB.prepare(
      `UPDATE families SET stripe_status = 'active', updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(family.id)
      .run();
    return c.redirect("/account?billing=resumed");
  } catch (err) {
    console.error("[resume-subscription]", err);
    return c.redirect("/account");
  }
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
    return_url: `${publicBaseUrl(c.req.url, c.env)}/account`,
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
    .first<InviteRow & { family_name: string }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.html(landingPage());
  }

  const user = c.get("user");
  if (user) {
    const result = await acceptInviteForUser(c.env.DB, invite, user);
    if (!result.ok) {
      return c.html(inviteAcceptPage(result.familyName || invite.family_name, token, true, result.error));
    }
    return c.redirect("/account");
  }

  // Not logged in: send PIN immediately when invite has an email.
  if (invite.email) {
    try {
      await sendLoginPin(c.env, invite.email);
    } catch (err) {
      console.error("[invite pin]", err);
      return c.html(
        inviteAcceptPage(
          invite.family_name,
          token,
          false,
          "A belépési kód küldése nem sikerült. Frissítsd az oldalt.",
        ),
        500,
      );
    }
    return c.html(
      verifyPage(invite.email, "", false, "", {
        inviteToken: token,
        familyName: invite.family_name,
      }),
    );
  }

  return c.html(inviteEmailPage(invite.family_name, token));
});

web.post("/invite/:token/start", async (c) => {
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.*, f.name AS family_name FROM invites i
     JOIN families f ON f.id = i.family_id WHERE i.token = ?`,
  )
    .bind(token)
    .first<InviteRow & { family_name: string }>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.html(landingPage());
  }

  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? invite.email ?? ""));
  if (!email.includes("@")) {
    return c.html(inviteEmailPage(invite.family_name, token, "Érvényes email kell."), 400);
  }

  // Lock invite to this email if it was open.
  if (!invite.email) {
    await c.env.DB.prepare(`UPDATE invites SET email = ? WHERE id = ?`)
      .bind(email, invite.id)
      .run();
  } else if (invite.email !== email) {
    return c.html(
      inviteEmailPage(invite.family_name, token, `Ez a meghívó a(z) ${invite.email} címre szól.`),
      400,
    );
  }

  try {
    await sendLoginPin(c.env, email);
  } catch (err) {
    console.error("[invite start pin]", err);
    return c.html(
      inviteEmailPage(invite.family_name, token, "A kód küldése nem sikerült."),
      500,
    );
  }

  return c.html(
    verifyPage(email, "", false, "", {
      inviteToken: token,
      familyName: invite.family_name,
    }),
  );
});

web.post("/invite/:token/accept", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect(`/invite/${c.req.param("token")}`);
  const token = c.req.param("token");

  const invite = await c.env.DB.prepare("SELECT * FROM invites WHERE token = ?")
    .bind(token)
    .first<InviteRow>();

  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.redirect("/");
  }

  const result = await acceptInviteForUser(c.env.DB, invite, user);
  if (!result.ok) {
    return c.html(
      inviteAcceptPage(result.familyName || "család", token, true, result.error),
    );
  }

  return c.redirect("/account");
});

export default web;
