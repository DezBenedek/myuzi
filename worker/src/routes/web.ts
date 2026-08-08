import { Hono } from "hono";
import type { Env, Variables } from "../types";
import {
  addDays,
  hmacSha256,
  id,
  inviteToken,
  isValidEmail,
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
  leaveCurrentFamily,
  memberCount,
  pruneUserSessions,
  removeFamilyMember,
} from "../lib/db";
import { inviteEmail, loginCodeEmail, sendEmail } from "../lib/email";
import {
  getStripe,
  changePaidPlan,
  cancelAtPeriodEnd,
  resumeSubscription,
} from "../lib/stripe";
import { applyPlan, normalizeBillingDetails } from "./billing";
import { isSuperadmin } from "./admin";
import { publicBaseUrl } from "../lib/urls";
import { optionalAuth } from "../middleware/auth";
import {
  accountPage,
  adminInvoicesPage,
  billingPage,
  familyConnectionPage,
  inviteAcceptPage,
  inviteEmailPage,
  landingPage,
  loginPage,
  plansPage,
  subscriptionPortalPage,
  verifyPage,
} from "../web/pages";
import { appCallPage, appChatPage, appInboxPage, userQrPage } from "../web/app_pages";
import type { UserRow } from "../types";

const web = new Hono<{ Bindings: Env; Variables: Variables }>();
web.use("*", async (c, next) => {
  const declared = c.req.header("Content-Length");
  if (declared) {
    const length = Number(declared);
    if (!Number.isFinite(length) || length < 0 || length > 64 * 1024) {
      return c.text("A kérés túl nagy", 413);
    }
  }
  await next();
});

type InviteRow = {
  id: string;
  family_id: string;
  status: string;
  expires_at: string;
  email: string | null;
  target_user_id?: string | null;
  family_name?: string;
};

function cleanDisplayName(value: string): string {
  return value
    .trim()
    .replace(/[<>&\u0000-\u001f]/g, "")
    .slice(0, 80)
    .trim();
}

async function sendLoginPin(
  env: Env,
  email: string,
  visionAssist = 0,
): Promise<"ok" | "rate_limited"> {
  const recent = await env.DB.prepare(
    `SELECT 1 AS ok FROM auth_codes
     WHERE email = ? AND created_at > datetime('now', '-30 seconds')`,
  )
    .bind(email)
    .first<{ ok: number }>();
  if (recent) return "rate_limited";

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
  return "ok";
}

async function acceptInviteForUser(
  db: D1Database,
  invite: InviteRow,
  user: UserRow,
  opts: { confirmLeave?: boolean } = {},
): Promise<
  | { ok: true }
  | {
      ok: false;
      error: string;
      familyName: string;
      needsLeaveConfirmation?: boolean;
      currentFamilyName?: string;
    }
> {
  const family = await getFamily(db, invite.family_id);
  if (!family) return { ok: false, error: "A család nem található.", familyName: "" };
  if (!invite.email || invite.email.toLowerCase() !== user.email.toLowerCase()) {
    return {
      ok: false,
      error: invite.email
        ? `Ez a meghívó a(z) ${invite.email} címre szól.`
        : "Érvénytelen meghívó (nincs emailhez kötve).",
      familyName: family.name,
    };
  }
  const existingFamily = await getUserFamily(db, user.id);
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
  if (existingFamily && existingFamily.id !== family.id) {
    if (!opts.confirmLeave) {
      return {
        ok: false,
        error: `Már a(z) ${existingFamily.name} család tagja vagy. Elfogadáshoz ki kell lépned.`,
        familyName: family.name,
        needsLeaveConfirmation: true,
        currentFamilyName: existingFamily.name,
      };
    }
    const left = await leaveCurrentFamily(db, user.id);
    if (!left.ok) {
      return { ok: false, error: left.error, familyName: family.name };
    }
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

web.get("/", optionalAuth, (c) => {
  const user = c.get("user");
  return c.html(
    landingPage({
      loggedIn: !!user,
      userName: user?.name,
    }),
  );
});

web.get("/app", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login?next=/app");
  return c.html(appInboxPage(user));
});

web.get("/app/chat/:id", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const id = c.req.param("id");
  if (!/^[A-Za-z0-9_-]{6,80}$/.test(id)) {
    return c.html(appInboxPage(user));
  }
  return c.html(appChatPage(user, id, "Beszélgetés"));
});

web.get("/app/call/:id", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  const callId = c.req.param("id");
  if (!/^[A-Za-z0-9_-]{6,80}$/.test(callId)) {
    return c.html(appInboxPage(user));
  }
  const callType = c.req.query("type") === "video" ? "video" : "audio";
  return c.html(
    appCallPage(user, {
      callId,
      callType,
      title: callType === "video" ? "Videóhívás" : "Hanghívás",
    }),
  );
});

web.get("/u/:userId", optionalAuth, async (c) => {
  const userId = c.req.param("userId");
  if (!/^[A-Za-z0-9_-]{6,80}$/.test(userId)) {
    return c.redirect("/");
  }
  const me = c.get("user");
  return c.html(userQrPage({ userId, meId: me?.id ?? null, loggedIn: !!me }));
});

web.get("/login", (c) =>
  c.html(loginPage("", String(c.req.query("connection") ?? "").trim())),
);

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
  await pruneUserSessions(c.env.DB, row.user_id);

  c.header(
    "Set-Cookie",
    `myuzi_session=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`,
  );
  return c.redirect("/account/subscription");
});

web.post("/login", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const visionAssist = form.visionAssist === "1" ? 1 : 0;
  const connectionToken = String(form.connectionToken ?? "").trim();

  if (!isValidEmail(email)) {
    return c.html(loginPage("Érvényes email kell.", connectionToken), 400);
  }

  try {
    const sent = await sendLoginPin(c.env, email, visionAssist);
    if (sent === "rate_limited") {
      return c.html(
        verifyPage(email, "Kérj új kódot 30 másodperc múlva.", false, "", {
          connectionToken,
        }),
        429,
      );
    }
  } catch (err) {
    console.error("[login email]", err);
    return c.html(
      loginPage("A kód küldése nem sikerült. Próbáld újra.", connectionToken),
      500,
    );
  }

  return c.html(verifyPage(email, "", false, "", { connectionToken }));
});

web.post("/login/verify", async (c) => {
  const form = await c.req.parseBody();
  const email = normalizeEmail(String(form.email ?? ""));
  const code = String(form.code ?? "").trim();
  const name = cleanDisplayName(String(form.name ?? ""));
  const inviteToken = String(form.inviteToken ?? "").trim();
  const connectionToken = String(form.connectionToken ?? "").trim();
  if (!isValidEmail(email)) {
    return c.html(loginPage("Érvénytelen email cím."), 400);
  }

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
  const connectionOpts = connectionToken
    ? await (async () => {
        const connection = await c.env.DB.prepare(
          `SELECT f.name AS family_name FROM family_link_invites i
           JOIN families f ON f.id = i.source_family_id
           WHERE i.token = ? AND i.status = 'pending' AND i.expires_at > datetime('now')`,
        )
          .bind(connectionToken)
          .first<{ family_name: string }>();
        return connection
          ? { connectionToken, familyName: connection.family_name }
          : undefined;
      })()
    : undefined;
  const authFlowOpts =
    inviteOpts || connectionOpts
      ? { ...(inviteOpts ?? {}), ...(connectionOpts ?? {}) }
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
      verifyPage(email, "A kód lejárt vagy túl sok próbálkozás.", false, "", authFlowOpts),
      400,
    );
  }

  const expected = await sha256(`${email}:${code}:${c.env.SESSION_SECRET}`);
  if (!timingSafeEqual(expected, row.code_hash)) {
    await c.env.DB.prepare("UPDATE auth_codes SET attempts = attempts + 1 WHERE id = ?")
      .bind(row.id)
      .run();
    return c.html(verifyPage(email, "Hibás kód.", false, "", authFlowOpts), 400);
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
          authFlowOpts,
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
  await pruneUserSessions(c.env.DB, user!.id);

  setSessionCookie(c, token);

  if (inviteToken) {
    const invite = await c.env.DB.prepare("SELECT * FROM invites WHERE token = ?")
      .bind(inviteToken)
      .first<InviteRow>();
    if (invite && invite.status === "pending" && !isExpired(invite.expires_at)) {
      const result = await acceptInviteForUser(c.env.DB, invite, user!);
      if (!result.ok) {
        return c.html(
          inviteAcceptPage(result.familyName || "család", inviteToken, true, result.error, {
            needsLeaveConfirmation: result.needsLeaveConfirmation,
            currentFamilyName: result.currentFamilyName,
          }),
        );
      }
      return c.redirect("/app");
    }
  }
  if (connectionToken) {
    return c.redirect(`/family-link/${encodeURIComponent(connectionToken)}`);
  }

  return c.redirect("/app");
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

web.get("/admin/invoices", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  if (!isSuperadmin(user.email, c.env.SUPERADMIN_EMAILS ?? "")) {
    return c.text("Superadmin jogosultság szükséges", 403);
  }

  const rows = await c.env.DB.prepare(
    `SELECT i.id, i.invoice_number, i.issued_at, i.amount, i.currency,
            i.period_label, f.name AS family_name, u.email AS owner_email
     FROM manual_invoices i
     JOIN families f ON f.id = i.family_id
     JOIN users u ON u.id = f.owner_id
     WHERE i.voided_at IS NULL
     ORDER BY i.issued_at DESC, i.created_at DESC
     LIMIT 200`,
  )
    .all<{
      id: string;
      invoice_number: string;
      issued_at: string;
      amount: number;
      currency: string;
      period_label: string | null;
      family_name: string;
      owner_email: string;
    }>();

  return c.html(
    adminInvoicesPage({
      user,
      invoices: rows.results ?? [],
    }),
  );
});

web.get("/account/subscription", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");

  const family = await getUserFamily(c.env.DB, user.id);
  const isOwner = !!family && family.owner_id === user.id;
  let invoices: Array<{
    id: string;
    number: string;
    issuedAt: string;
    amount: number;
    currency: string;
    periodLabel: string | null;
  }> = [];
  let invoiceError: string | undefined;
  if (isOwner && family) {
    try {
      const rows = await c.env.DB.prepare(
        `SELECT id, invoice_number, issued_at, amount, currency, period_label
         FROM manual_invoices
         WHERE family_id = ? AND voided_at IS NULL
         ORDER BY issued_at DESC, created_at DESC
         LIMIT 100`,
      )
        .bind(family.id)
        .all<{
          id: string;
          invoice_number: string;
          issued_at: string;
          amount: number;
          currency: string;
          period_label: string | null;
        }>();
      invoices = (rows.results ?? []).map((invoice) => ({
        id: invoice.id,
        number: invoice.invoice_number,
        issuedAt: invoice.issued_at,
        amount: invoice.amount,
        currency: invoice.currency,
        periodLabel: invoice.period_label,
      }));
    } catch (err) {
      console.error("[web subscription invoices]", err);
      invoiceError = "A számlák most nem tölthetők be.";
    }
  }

  const billing = c.req.query("billing");
  const message =
    billing === "saved"
      ? "A számlázási adatok elmentve."
      : billing === "success"
        ? "Sikeres csomagváltás — köszönjük!"
        : billing === "scheduled"
          ? "A csomagváltás a jelenlegi hónap végén lép életbe."
          : billing === "canceled"
            ? "Az előfizetés lemondva — a hónap végéig még érvényes."
            : billing === "resumed"
              ? "Az előfizetés folytatódik."
              : undefined;

  return c.html(
    subscriptionPortalPage({
      user,
      family,
      billing: family,
      invoices,
      isOwner,
      message,
      error: c.req.query("error") || invoiceError,
    }),
  );
});

web.post("/account/subscription/billing", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");

  const family = await getUserFamily(c.env.DB, user.id);
  if (!family || family.owner_id !== user.id) {
    return c.redirect("/account/subscription?error=Nincs jogosultság");
  }

  const form = await c.req.parseBody();
  const normalized = normalizeBillingDetails({
    billingType: String(form.billingType ?? ""),
    billingName: String(form.billingName ?? ""),
    taxId: String(form.taxId ?? ""),
    addressLine1: String(form.addressLine1 ?? ""),
    city: String(form.city ?? ""),
    postalCode: String(form.postalCode ?? ""),
    country: String(form.country ?? "HU"),
  });
  if ("error" in normalized) {
    return c.redirect(
      `/account/subscription?error=${encodeURIComponent(normalized.error ?? "Érvénytelen számlázási adatok")}`,
    );
  }

  const details = normalized.value;
  await c.env.DB.prepare(
    `UPDATE families SET
      billing_type = ?, billing_name = ?, billing_tax_id = ?,
      billing_address_line1 = ?, billing_city = ?, billing_postal_code = ?,
      billing_country = ?, updated_at = datetime('now')
     WHERE id = ?`,
  )
    .bind(
      details.billing_type,
      details.billing_name,
      details.billing_tax_id,
      details.billing_address_line1,
      details.billing_city,
      details.billing_postal_code,
      details.billing_country,
      family.id,
    )
    .run();

  return c.redirect("/account/subscription?billing=saved");
});

web.post("/account/family", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect("/login");
  if (await getUserFamily(c.env.DB, user.id)) return c.redirect("/account");

  const form = await c.req.parseBody();
  const name = cleanDisplayName(String(form.name ?? ""));
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

  await removeFamilyMember(c.env.DB, family.id, targetUserId);

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
  const email = normalizeEmail(emailRaw);
  if (!isValidEmail(email)) {
    return c.html(
      accountPage({
        user,
        family,
        members,
        error: "Meghívóhoz érvényes email cím kell.",
      }),
    );
  }
  const token = inviteToken();
  await c.env.DB.prepare(
    `INSERT INTO invites (id, family_id, email, token, invited_by, expires_at)
     VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(id("inv"), family.id, email, token, user.id, addDays(14))
    .run();

  const inviteUrl = `${publicBaseUrl(c.req.url, c.env)}/invite/${token}`;
  let message = "Meghívó elküldve emailben.";
  try {
    const mail = inviteEmail(c.env.APP_NAME, family.name, user.name, inviteUrl);
    await sendEmail(c.env, { to: email, ...mail });
  } catch (err) {
    console.error("[invite email]", err);
    message =
      "A meghívó link elkészült, de az email küldése nem sikerült. Másold ki a linket lent.";
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
        return c.redirect("/account/subscription?billing=success");
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
        return c.redirect("/account/subscription?billing=success");
      }
      await c.env.DB.prepare(
        `UPDATE families SET stripe_status = ?, updated_at = datetime('now') WHERE id = ?`,
      )
        .bind(`pending:${plan}`, family.id)
        .run();
      return c.redirect("/account/subscription?billing=scheduled");
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
      success_url: `${base}/account/subscription?billing=success`,
      cancel_url: `${base}/account/subscription?billing=cancel`,
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
    return c.redirect("/account/subscription?billing=canceled");
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
    return c.redirect("/account/subscription?billing=resumed");
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
    return_url: `${publicBaseUrl(c.req.url, c.env)}/account/subscription`,
  });
  return c.redirect(portal.url);
});

web.get("/family-link/:token", optionalAuth, async (c) => {
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.target_email, i.status, i.expires_at,
            f.name AS family_name, u.name AS inviter_name
     FROM family_link_invites i
     JOIN families f ON f.id = i.source_family_id
     JOIN users u ON u.id = i.invited_by
     WHERE i.token = ?`,
  )
    .bind(token)
    .first<{
      target_email: string;
      status: string;
      expires_at: string;
      family_name: string;
      inviter_name: string;
    }>();
  const user = c.get("user");
  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.html(
      familyConnectionPage({
        familyName: "ismeretlen",
        inviterName: "Ismeretlen",
        token,
        loggedIn: !!user,
        error: "Ez a családi kapcsolat lejárt vagy már felhasználták.",
      }),
      404,
    );
  }
  return c.html(
    familyConnectionPage({
      familyName: invite.family_name,
      inviterName: invite.inviter_name,
      token,
      loggedIn: !!user,
      error:
        user && normalizeEmail(user.email) !== normalizeEmail(invite.target_email)
          ? "Ez a kapcsolat másik email címre szól."
          : undefined,
    }),
  );
});

web.post("/family-link/:token/accept", optionalAuth, async (c) => {
  const user = c.get("user");
  if (!user) return c.redirect(`/login?connection=${encodeURIComponent(c.req.param("token"))}`);
  const token = c.req.param("token");
  const invite = await c.env.DB.prepare(
    `SELECT i.id, i.source_family_id, i.target_email, i.status, i.expires_at,
            f.name AS family_name, u.name AS inviter_name
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
      family_name: string;
      inviter_name: string;
    }>();
  if (!invite || invite.status !== "pending" || isExpired(invite.expires_at)) {
    return c.redirect(`/family-link/${encodeURIComponent(token)}`);
  }
  if (normalizeEmail(user.email) !== normalizeEmail(invite.target_email)) {
    return c.html(
      familyConnectionPage({
        familyName: invite.family_name,
        inviterName: invite.inviter_name,
        token,
        loggedIn: true,
        error: "Ez a kapcsolat másik email címre szól.",
      }),
      403,
    );
  }
  const target = await getUserFamily(c.env.DB, user.id);
  if (!target || target.owner_id !== user.id) {
    return c.html(
      familyConnectionPage({
        familyName: invite.family_name,
        inviterName: invite.inviter_name,
        token,
        loggedIn: true,
        error: "Csak egy család tulajdonosa fogadhatja el.",
      }),
      403,
    );
  }
  const [familyA, familyB] =
    invite.source_family_id < target.id
      ? [invite.source_family_id, target.id]
      : [target.id, invite.source_family_id];
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
  return c.redirect("/app?connection=accepted");
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
    // Never auto-join on GET — show explicit accept UI (prevents drive-by joins).
    const existing = await getUserFamily(c.env.DB, user.id);
    const needsLeave = !!existing && existing.id !== invite.family_id;
    return c.html(
      inviteAcceptPage(invite.family_name, token, true, "", {
        needsLeaveConfirmation: needsLeave,
        currentFamilyName: needsLeave ? existing?.name : undefined,
      }),
    );
  }

  // Not logged in: send PIN immediately when invite has an email.
  if (invite.email) {
    try {
      const sent = await sendLoginPin(c.env, invite.email);
      if (sent === "rate_limited") {
        return c.html(
          inviteAcceptPage(invite.family_name, token, false, "Kérj új kódot 30 másodperc múlva."),
          429,
        );
      }
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
  if (!isValidEmail(email)) {
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
    const sent = await sendLoginPin(c.env, email);
    if (sent === "rate_limited") {
      return c.html(
        inviteEmailPage(invite.family_name, token, "Kérj új kódot 30 másodperc múlva."),
        429,
      );
    }
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

  const form = await c.req.parseBody();
  const confirmLeave = String(form.confirmLeave ?? "") === "1";

  const result = await acceptInviteForUser(c.env.DB, invite, user, { confirmLeave });
  if (!result.ok) {
    return c.html(
      inviteAcceptPage(result.familyName || "család", token, true, result.error, {
        needsLeaveConfirmation: result.needsLeaveConfirmation,
        currentFamilyName: result.currentFamilyName,
      }),
    );
  }

  return c.redirect("/app");
});

export default web;
