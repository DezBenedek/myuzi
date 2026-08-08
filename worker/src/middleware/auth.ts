import { createMiddleware } from "hono/factory";
import type { Env, Variables } from "../types";
import { hmacSha256, isExpired } from "../lib/crypto";
import { getUserById } from "../lib/db";

export const requireAuth = createMiddleware<{ Bindings: Env; Variables: Variables }>(
  async (c, next) => {
    const header = c.req.header("Authorization") ?? "";
    const cookie = getCookie(c.req.header("Cookie") ?? "", "myuzi_session");
    const raw = header.startsWith("Bearer ") ? header.slice(7).trim() : cookie;

    if (!raw || raw.length > 256) {
      return c.json({ error: "Bejelentkezés szükséges" }, 401);
    }

    const tokenHash = await hmacSha256(c.env.SESSION_SECRET, raw);
    const session = await c.env.DB.prepare(
      "SELECT id, user_id, expires_at FROM sessions WHERE token_hash = ?",
    )
      .bind(tokenHash)
      .first<{ id: string; user_id: string; expires_at: string }>();

    if (!session || isExpired(session.expires_at)) {
      if (session) {
        await c.env.DB.prepare("DELETE FROM sessions WHERE id = ?").bind(session.id).run();
      }
      return c.json({ error: "A munkamenet lejárt" }, 401);
    }

    const user = await getUserById(c.env.DB, session.user_id);
    if (!user) {
      return c.json({ error: "Felhasználó nem található" }, 401);
    }

    c.executionCtx.waitUntil(
      c.env.DB.prepare("UPDATE sessions SET last_used_at = datetime('now') WHERE id = ?")
        .bind(session.id)
        .run()
        .catch((err) => console.error("[session touch]", err)),
    );

    c.set("userId", user.id);
    c.set("user", user);
    await next();
  },
);

export const optionalAuth = createMiddleware<{ Bindings: Env; Variables: Variables }>(
  async (c, next) => {
    const header = c.req.header("Authorization") ?? "";
    const cookie = getCookie(c.req.header("Cookie") ?? "", "myuzi_session");
    const raw = header.startsWith("Bearer ") ? header.slice(7).trim() : cookie;
    if (raw && raw.length <= 256) {
      const tokenHash = await hmacSha256(c.env.SESSION_SECRET, raw);
      const session = await c.env.DB.prepare(
        "SELECT user_id, expires_at FROM sessions WHERE token_hash = ?",
      )
        .bind(tokenHash)
        .first<{ user_id: string; expires_at: string }>();
      if (session && !isExpired(session.expires_at)) {
        const user = await getUserById(c.env.DB, session.user_id);
        if (user) {
          c.set("userId", user.id);
          c.set("user", user);
        }
      }
    }
    await next();
  },
);

function getCookie(cookieHeader: string, name: string): string | null {
  const parts = cookieHeader.split(";").map((p) => p.trim());
  for (const part of parts) {
    const eq = part.indexOf("=");
    if (eq === -1) continue;
    if (part.slice(0, eq) === name) {
      try {
        const value = decodeURIComponent(part.slice(eq + 1));
        return value.length <= 256 ? value : null;
      } catch {
        return null;
      }
    }
  }
  return null;
}
