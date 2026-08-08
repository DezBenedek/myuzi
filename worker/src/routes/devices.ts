import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { readLimitedJson } from "../lib/body";
import { requireAuth } from "../middleware/auth";

const devices = new Hono<{ Bindings: Env; Variables: Variables }>();
devices.use("*", requireAuth);

devices.post("/push-token", async (c) => {
  const body = await readLimitedJson<{ token?: string; platform?: string }>(c.req.raw);
  if (!body || typeof body !== "object" || Array.isArray(body)) {
    return c.json({ error: "Érvénytelen kérés" }, 400);
  }
  const token = typeof body.token === "string" ? body.token.trim() : "";
  const platform = typeof body.platform === "string" ? body.platform.trim() : "";
  if (!token || token.length > 512) return c.json({ error: "Érvénytelen token" }, 400);
  if (platform && !["android", "ios", "macos", "windows", "linux", "web"].includes(platform)) {
    return c.json({ error: "Érvénytelen platform" }, 400);
  }

  await c.env.DB.prepare(
    `UPDATE users SET push_token = ?, push_platform = ?, updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(token, platform || null, c.get("userId"))
    .run();

  return c.json({ ok: true });
});

devices.delete("/push-token", async (c) => {
  await c.env.DB.prepare(
    `UPDATE users SET push_token = NULL, push_platform = NULL, updated_at = datetime('now') WHERE id = ?`,
  )
    .bind(c.get("userId"))
    .run();
  return c.json({ ok: true });
});

export default devices;
