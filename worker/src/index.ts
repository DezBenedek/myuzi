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
import users from "./routes/users";
import web from "./routes/web";

const app = new Hono<{ Bindings: Env; Variables: Variables }>();
const allowedApiOrigins = new Set([
  "https://myuzi.uvmr.app",
  "http://localhost:3000",
  "http://localhost:5173",
]);

app.use("*", async (c, next) => {
  await next();
  c.header("X-Content-Type-Options", "nosniff");
  c.header("X-Frame-Options", "DENY");
  c.header("Referrer-Policy", "no-referrer");
  c.header("Permissions-Policy", "camera=(self), microphone=(self), geolocation=()");
});

app.use("/api/*", async (c, next) => {
  const declared = c.req.header("Content-Length");
  if (declared) {
    const length = Number(declared);
    const contentType = (c.req.header("Content-Type") ?? "").toLowerCase();
    const max =
      contentType.startsWith("audio/") ? 20 * 1024 * 1024 :
      contentType.startsWith("image/") ? 1024 * 1024 :
      256 * 1024;
    if (!Number.isFinite(length) || length < 0 || length > max) {
      return c.json({ error: "A kérés túl nagy" }, 413);
    }
  }
  await next();
});

app.use(
  "/api/*",
  cors({
    origin: (origin) => (allowedApiOrigins.has(origin) ? origin : null),
    allowMethods: ["GET", "POST", "PATCH", "DELETE", "OPTIONS"],
    allowHeaders: [
      "Content-Type",
      "Authorization",
      "X-Client",
      "X-Duration-Ms",
      "X-Wave-Bars",
    ],
    exposeHeaders: ["ETag"],
    maxAge: 86400,
  }),
);

app.get("/health", (c) =>
  c.json({
    ok: true,
    app: c.env.APP_NAME,
    livekit: c.env.LIVEKIT_URL,
    url: c.env.APP_URL,
  }),
);

app.route("/api/auth", auth);
app.route("/api/users", users);
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
