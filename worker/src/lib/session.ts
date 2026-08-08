import type { Env, UserRow } from "../types";
import { hmacSha256, isExpired } from "./crypto";
import { getUserById } from "./db";

/** Resolve a session token (Bearer / cookie / WS query) to a user. */
export async function resolveSessionUser(
  env: Env,
  rawToken: string | null | undefined,
): Promise<UserRow | null> {
  const raw = (rawToken ?? "").trim();
  if (!raw || raw.length > 256) return null;

  const tokenHash = await hmacSha256(env.SESSION_SECRET, raw);
  const session = await env.DB.prepare(
    "SELECT id, user_id, expires_at FROM sessions WHERE token_hash = ?",
  )
    .bind(tokenHash)
    .first<{ id: string; user_id: string; expires_at: string }>();

  if (!session || isExpired(session.expires_at)) {
    if (session) {
      await env.DB.prepare("DELETE FROM sessions WHERE id = ?").bind(session.id).run();
    }
    return null;
  }

  return getUserById(env.DB, session.user_id);
}

export function getCookie(cookieHeader: string, name: string): string | null {
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

export function bearerFromAuthorization(header: string | null | undefined): string | null {
  const h = header ?? "";
  if (!h.startsWith("Bearer ")) return null;
  const raw = h.slice(7).trim();
  return raw && raw.length <= 256 ? raw : null;
}
