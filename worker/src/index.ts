import { Hono } from "hono";
import { cors } from "hono/cors";
import type { Env, Variables } from "./types";
import auth from "./routes/auth";
import billing from "./routes/billing";
import calls from "./routes/calls";
import conversations from "./routes/conversations";
import devices from "./routes/devices";
import families from "./routes/families";
import invites from "./routes/invites";
import messages from "./routes/messages";
import web from "./routes/web";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();

app.use(
  "/api/*",
  cors({
    origin: (origin) => origin || "*",
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: ["Content-Type", "Authorization", "X-Client", "X-Duration-Ms"],
    exposeHeaders: ["ETag"],
    maxAge: 86400,
  }),
);

app.get("/health", (c) =>
  c.json({
    ok: true,
    app: c.env.APP_NAME,
    livekit: c.env.LIVEKIT_URL,
  }),
);

app.route("/api/auth", auth);
app.route("/api/families", families);
app.route("/api/invites", invites);
app.route("/api/conversations", conversations);
app.route("/api/messages", messages);
app.route("/api/calls", calls);
app.route("/api/billing", billing);
app.route("/api/devices", devices);

app.route("/", web);

app.notFound((c) => {
  if (c.req.path.startsWith("/api/")) {
    return c.json({ error: "Not found" }, 404);
  }
  return c.redirect("/");
});

app.onError((err, c) => {
  console.error(JSON.stringify({ err: String(err), path: c.req.path }));
  if (c.req.path.startsWith("/api/")) {
    return c.json({ error: "Szerverhiba" }, 500);
  }
  return c.text("Hiba történt", 500);
});

export default app;
