import { Hono } from "hono";
import type { Env, Variables } from "../types";
import {
  addDays,
  addMinutes,
  hmacSha256,
  id,
  isExpired,
  normalizeEmail,
  sessionToken,
  sha256,
  sixDigitCode,
  timingSafeEqual,
} from "../lib/crypto";
import { getUserByEmail, publicUser } from "../lib/db";
import { loginCodeEmail, sendEmail } from "../lib/email";
import { publicBaseUrl } from "../lib/urls";
import { requireAuth } from "../middleware/auth";

const auth = new Hono<{ Bindings: Env; Variables: Variables }>();

auth.post("/start", async (c) => {
  const body = await c.req.json<{
    email?: string;
    visionAssist?: boolean;
  }>();

  const email = normalizeEmail(body.email ?? "");
  const visionAssist = !!body.visionAssist;

  if (!email || !email.includes("@")) {
    return c.json({ error: "Érvényes email kell" }, 400);
  }

  const existing = await getUserByEmail(c.env.DB, email);
  const isNew = !existing;
  const displayName = existing?.name || "Felhasználó";

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
      existing?.name ?? "",
      visionAssist ? 1 : existing?.vision_assist ?? 0,
      codeHash,
      addMinutes(10),
    )
    .run();

  const mail = loginCodeEmail(c.env.APP_NAME, displayName, code);
  await sendEmail(c.env, { to: email, ...mail });

  return c.json({ ok: true, email, isNew });
});

auth.post("/verify", async (c) => {
  const body = await c.req.json<{
    email?: string;
    code?: string;
    name?: string;
    visionAssist?: boolean;
  }>();
  const email = normalizeEmail(body.email ?? "");
  const code = (body.code ?? "").trim();
  const name = (body.name ?? "").trim();

  if (!email || !/^\d{6}$/.test(code)) {
    return c.json({ error: "Hibás kód" }, 400);
  }

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

  if (!row || isExpired(row.expires_at)) {
    return c.json({ error: "A kód lejárt. Kérj újat." }, 400);
  }

  if (row.attempts >= 5) {
    await c.env.DB.prepare("DELETE FROM auth_codes WHERE id = ?").bind(row.id).run();
    return c.json({ error: "Túl sok próbálkozás. Kérj új kódot." }, 429);
  }

  const expected = await sha256(`${email}:${code}:${c.env.SESSION_SECRET}`);
  if (!timingSafeEqual(expected, row.code_hash)) {
    await c.env.DB.prepare("UPDATE auth_codes SET attempts = attempts + 1 WHERE id = ?")
      .bind(row.id)
      .run();
    return c.json({ error: "Hibás kód" }, 400);
  }

  let user = await getUserByEmail(c.env.DB, email);
  const visionAssist =
    typeof body.visionAssist === "boolean"
      ? body.visionAssist
        ? 1
        : 0
      : row.vision_assist;

  if (!user) {
    if (name.length < 2) {
      // Keep OTP valid so the client can ask for nickname after PIN.
      return c.json(
        {
          error: "Új fióknál név vagy becenév kell",
          needsName: true,
        },
        400,
      );
    }
    const userId = id("usr");
    await c.env.DB.prepare(
      `INSERT INTO users (id, email, name, vision_assist) VALUES (?, ?, ?, ?)`,
    )
      .bind(userId, email, name, visionAssist)
      .run();
    user = await getUserByEmail(c.env.DB, email);
  } else if (typeof body.visionAssist === "boolean") {
    await c.env.DB.prepare(
      `UPDATE users SET vision_assist = ?, updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(visionAssist, user.id)
      .run();
    user = await getUserByEmail(c.env.DB, email);
  }

  if (!user) return c.json({ error: "Sikertelen belépés" }, 500);

  await c.env.DB.prepare("DELETE FROM auth_codes WHERE email = ?").bind(email).run();

  const token = sessionToken();
  const tokenHash = await hmacSha256(c.env.SESSION_SECRET, token);
  await c.env.DB.prepare(
    `INSERT INTO sessions (id, user_id, token_hash, expires_at) VALUES (?, ?, ?, ?)`,
  )
    .bind(id("ses"), user.id, tokenHash, addDays(60))
    .run();

  const isWeb = (c.req.header("X-Client") ?? "").toLowerCase() === "web";
  if (isWeb) {
    c.header(
      "Set-Cookie",
      `myuzi_session=${encodeURIComponent(token)}; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=${60 * 60 * 24 * 60}`,
    );
  }

  return c.json({
    token,
    user: publicUser(user),
  });
});

auth.get("/me", requireAuth, async (c) => {
  return c.json({ user: publicUser(c.get("user")) });
});

auth.post("/logout", requireAuth, async (c) => {
  const header = c.req.header("Authorization") ?? "";
  const raw = header.startsWith("Bearer ") ? header.slice(7).trim() : "";
  if (raw) {
    const tokenHash = await hmacSha256(c.env.SESSION_SECRET, raw);
    await c.env.DB.prepare("DELETE FROM sessions WHERE token_hash = ?").bind(tokenHash).run();
  }
  c.header(
    "Set-Cookie",
    "myuzi_session=; Path=/; HttpOnly; Secure; SameSite=Lax; Max-Age=0",
  );
  return c.json({ ok: true });
});

auth.patch("/me", requireAuth, async (c) => {
  const body = await c.req.json<{ name?: string; email?: string; visionAssist?: boolean }>();
  const user = c.get("user");
  const name = body.name?.trim() || user.name;
  if (name.length < 2) return c.json({ error: "A név túl rövid" }, 400);

  let email = user.email;
  if (typeof body.email === "string" && body.email.trim()) {
    email = normalizeEmail(body.email);
    if (!email.includes("@")) return c.json({ error: "Érvénytelen email" }, 400);
    if (email !== user.email) {
      const taken = await getUserByEmail(c.env.DB, email);
      if (taken && taken.id !== user.id) {
        return c.json({ error: "Ez az email már foglalt" }, 409);
      }
    }
  }

  const vision =
    typeof body.visionAssist === "boolean" ? (body.visionAssist ? 1 : 0) : user.vision_assist;

  await c.env.DB.prepare(
    `UPDATE users SET name = ?, email = ?, vision_assist = ?, updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(name, email, vision, user.id)
    .run();

  const updated = await getUserByEmail(c.env.DB, email);
  return c.json({ user: publicUser(updated!) });
});

/** One-time link: app → web, auto login with cookie. */
auth.post("/web-link", requireAuth, async (c) => {
  const raw = sessionToken();
  const tokenHash = await sha256(raw);
  await c.env.DB.prepare("DELETE FROM web_bridge_tokens WHERE user_id = ?")
    .bind(c.get("userId"))
    .run();
  await c.env.DB.prepare(
    `INSERT INTO web_bridge_tokens (id, user_id, token_hash, expires_at)
     VALUES (?, ?, ?, ?)`,
  )
    .bind(id("wbr"), c.get("userId"), tokenHash, addMinutes(5))
    .run();

  const base = publicBaseUrl(c.req.url, c.env);
  return c.json({ url: `${base}/auth/bridge?t=${encodeURIComponent(raw)}` });
});

export default auth;
