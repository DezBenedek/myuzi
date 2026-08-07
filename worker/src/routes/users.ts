import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { getUserById, publicUser } from "../lib/db";
import { requireAuth } from "../middleware/auth";

const users = new Hono<{ Bindings: Env; Variables: Variables }>();

users.get("/:id/avatar", requireAuth, async (c) => {
  const user = await getUserById(c.env.DB, c.req.param("id"));
  if (!user?.avatar_key) return c.json({ error: "Nincs profilkép" }, 404);

  const obj = await c.env.VOICE.get(user.avatar_key);
  if (!obj) return c.json({ error: "Fájl hiányzik" }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  headers.set("etag", obj.httpEtag);
  headers.set("Cache-Control", "private, max-age=3600");
  return new Response(obj.body, { headers });
});

users.get("/:id", requireAuth, async (c) => {
  const user = await getUserById(c.env.DB, c.req.param("id"));
  if (!user) return c.json({ error: "Nem található" }, 404);
  return c.json({ user: publicUser(user) });
});

export default users;
