import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { getUserById, getUserFamily, isFamilyMember, publicUser } from "../lib/db";
import { publicBaseUrl } from "../lib/urls";
import { requireAuth } from "../middleware/auth";

const users = new Hono<{ Bindings: Env; Variables: Variables }>();

async function canViewPrivateUserData(
  db: D1Database,
  viewerId: string,
  targetId: string,
): Promise<boolean> {
  if (viewerId === targetId) return true;
  const family = await getUserFamily(db, viewerId);
  return !!family && (await isFamilyMember(db, family.id, targetId));
}

users.get("/me/qr", requireAuth, async (c) => {
  const me = c.get("user");
  const base = publicBaseUrl(c.req.url, c.env);
  const url = `${base}/u/${me.id}`;
  return c.json({
    userId: me.id,
    name: me.name,
    url,
  });
});

users.get("/:id/avatar", requireAuth, async (c) => {
  const targetId = c.req.param("id");
  if (!(await canViewPrivateUserData(c.env.DB, c.get("userId"), targetId))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }
  const user = await getUserById(c.env.DB, targetId);
  if (!user?.avatar_key) return c.json({ error: "Nincs profilkép" }, 404);

  const obj = await c.env.VOICE.get(user.avatar_key);
  if (!obj) return c.json({ error: "Fájl hiányzik" }, 404);

  const headers = new Headers();
  obj.writeHttpMetadata(headers);
  const contentType = (headers.get("content-type") ?? "").toLowerCase();
  if (!["image/jpeg", "image/png", "image/webp"].includes(contentType)) {
    return c.json({ error: "A profilkép formátuma nem támogatott" }, 415);
  }
  headers.set("etag", obj.httpEtag);
  headers.set("Cache-Control", "private, max-age=3600");
  return new Response(obj.body, { headers });
});

/** Minimal card for QR scan / contact sheet. */
users.get("/:id/card", requireAuth, async (c) => {
  const targetId = c.req.param("id");
  const target = await getUserById(c.env.DB, targetId);
  if (!target) return c.json({ error: "Nem található" }, 404);

  const me = c.get("userId");
  const myFamily = await getUserFamily(c.env.DB, me);
  const theirFamily = await getUserFamily(c.env.DB, targetId);
  const sameFamily =
    !!myFamily && (await isFamilyMember(c.env.DB, myFamily.id, targetId));

  return c.json({
    user: {
      id: target.id,
      name: target.name,
      avatarUrl:
        sameFamily && target.avatar_key
          ? `/api/users/${target.id}/avatar`
          : null,
    },
    sameFamily,
    hasFamily: !!theirFamily,
    familyName: theirFamily?.name ?? null,
    isSelf: targetId === me,
  });
});

users.get("/:id", requireAuth, async (c) => {
  const targetId = c.req.param("id");
  if (!(await canViewPrivateUserData(c.env.DB, c.get("userId"), targetId))) {
    return c.json({ error: "Nincs hozzáférés" }, 403);
  }
  const user = await getUserById(c.env.DB, targetId);
  if (!user) return c.json({ error: "Nem található" }, 404);
  return c.json({ user: publicUser(user) });
});

export default users;
