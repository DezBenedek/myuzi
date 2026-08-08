import { createMiddleware } from "hono/factory";
import type { Env, Variables } from "../types";
import { hmacSha256 } from "../lib/crypto";
import {
  bearerFromAuthorization,
  getCookie,
  resolveSessionUser,
} from "../lib/session";

export const requireAuth = createMiddleware<{ Bindings: Env; Variables: Variables }>(
  async (c, next) => {
    const raw =
      bearerFromAuthorization(c.req.header("Authorization")) ||
      getCookie(c.req.header("Cookie") ?? "", "myuzi_session");

    const user = await resolveSessionUser(c.env, raw);
    if (!user) {
      return c.json({ error: "Bejelentkezés szükséges" }, 401);
    }

    if (raw) {
      c.executionCtx.waitUntil(
        (async () => {
          try {
            const tokenHash = await hmacSha256(c.env.SESSION_SECRET, raw);
            const session = await c.env.DB.prepare(
              "SELECT id FROM sessions WHERE token_hash = ?",
            )
              .bind(tokenHash)
              .first<{ id: string }>();
            if (session) {
              await c.env.DB.prepare(
                "UPDATE sessions SET last_used_at = datetime('now') WHERE id = ?",
              )
                .bind(session.id)
                .run();
            }
          } catch (err) {
            console.error("[session touch]", err);
          }
        })(),
      );
    }

    c.set("userId", user.id);
    c.set("user", user);
    await next();
  },
);

export const optionalAuth = createMiddleware<{ Bindings: Env; Variables: Variables }>(
  async (c, next) => {
    const raw =
      bearerFromAuthorization(c.req.header("Authorization")) ||
      getCookie(c.req.header("Cookie") ?? "", "myuzi_session");
    const user = await resolveSessionUser(c.env, raw);
    if (user) {
      c.set("userId", user.id);
      c.set("user", user);
    }
    await next();
  },
);
