import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { requireAuth } from "../middleware/auth";

const devices = new Hono<{ Bindings: Env; Variables: Variables }>();
devices.use("*", requireAuth);

devices.post("/push-token", async (c) => {
  const body = await c.req.json<{ token?: string; platform?: string }>();
  const token = (body.token ?? "").trim();
  const platform = (body.platform ?? "").trim();
  if (!token) return c.json({ error: "token kell" }, 400);

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
