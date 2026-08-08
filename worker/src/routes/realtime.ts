import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { getUserById } from "../lib/db";
import {
  mintRealtimeTicket,
  verifyRealtimeTicket,
} from "../lib/realtime_ticket";
import {
  bearerFromAuthorization,
  getCookie,
  resolveSessionUser,
} from "../lib/session";
import { requireAuth } from "../middleware/auth";

const realtime = new Hono<{ Bindings: Env; Variables: Variables }>();

/** Short-lived ticket for WebSocket auth (prefer over session token in query). */
realtime.post("/ticket", requireAuth, async (c) => {
  const minted = await mintRealtimeTicket(c.env.SESSION_SECRET, c.get("userId"));
  return c.json(minted);
});

/** Authenticated WebSocket upgrade → per-user Durable Object hub. */
realtime.get("/ws", async (c) => {
  if (c.req.header("Upgrade")?.toLowerCase() !== "websocket") {
    return c.json({ error: "WebSocket szükséges" }, 426);
  }

  const hub = c.env.USER_HUB;
  if (!hub) {
    return c.json({ error: "Realtime nincs beállítva" }, 503);
  }

  const ticket = c.req.query("ticket");
  const fromQuery = c.req.query("token");
  const fromAuth = bearerFromAuthorization(c.req.header("Authorization"));
  const fromCookie = getCookie(c.req.header("Cookie") ?? "", "myuzi_session");

  let userId: string | null = null;
  if (ticket) {
    userId = await verifyRealtimeTicket(c.env.SESSION_SECRET, ticket);
  }
  if (!userId) {
    const user = await resolveSessionUser(c.env, fromQuery || fromAuth || fromCookie);
    userId = user?.id ?? null;
  } else {
    const user = await getUserById(c.env.DB, userId);
    if (!user) userId = null;
  }

  if (!userId) {
    return c.json({ error: "Bejelentkezés szükséges" }, 401);
  }

  const id = hub.idFromName(userId);
  const stub = hub.get(id);
  // Forward upgrade without leaking session/token query params into the DO URL.
  const forwardUrl = new URL(c.req.url);
  forwardUrl.searchParams.delete("token");
  forwardUrl.searchParams.delete("ticket");
  forwardUrl.searchParams.set("userId", userId);
  return stub.fetch(new Request(forwardUrl.toString(), c.req.raw));
});

export default realtime;
