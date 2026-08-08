import { Hono } from "hono";
import type { Env, Variables } from "../types";
import {
  bearerFromAuthorization,
  getCookie,
  resolveSessionUser,
} from "../lib/session";

const realtime = new Hono<{ Bindings: Env; Variables: Variables }>();

/** Authenticated WebSocket upgrade → per-user Durable Object hub. */
realtime.get("/ws", async (c) => {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") {
    return c.json({ error: "WebSocket szükséges" }, 426);
  }

  const hub = c.env.USER_HUB;
  if (!hub) {
    return c.json({ error: "Realtime nincs beállítva" }, 503);
  }

  const fromQuery = c.req.query("token");
  const fromAuth = bearerFromAuthorization(c.req.header("Authorization"));
  const fromCookie = getCookie(c.req.header("Cookie") ?? "", "myuzi_session");
  const user = await resolveSessionUser(c.env, fromQuery || fromAuth || fromCookie);
  if (!user) {
    return c.json({ error: "Bejelentkezés szükséges" }, 401);
  }

  const id = hub.idFromName(user.id);
  const stub = hub.get(id);
  // Forward the original upgrade request so the client WebSocket is preserved.
  const forwardUrl = new URL(c.req.url);
  forwardUrl.searchParams.set("userId", user.id);
  return stub.fetch(new Request(forwardUrl.toString(), c.req.raw));
});

export default realtime;
