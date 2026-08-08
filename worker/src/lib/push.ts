import { importPKCS8, SignJWT } from "jose";
import type { Env } from "../types";

type ServiceAccount = {
  project_id: string;
  private_key: string;
  client_email: string;
};

type TokenCache = { accessToken: string; expiresAtMs: number };
let tokenCache: TokenCache | null = null;

function parseServiceAccount(raw: string | undefined): ServiceAccount | null {
  if (!raw?.trim()) return null;
  try {
    const parsed = JSON.parse(raw) as Partial<ServiceAccount>;
    if (
      typeof parsed.project_id === "string" &&
      typeof parsed.private_key === "string" &&
      typeof parsed.client_email === "string"
    ) {
      return {
        project_id: parsed.project_id,
        private_key: parsed.private_key,
        client_email: parsed.client_email,
      };
    }
  } catch (_) {}
  return null;
}

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Date.now();
  if (tokenCache && tokenCache.expiresAtMs > now + 60_000) {
    return tokenCache.accessToken;
  }

  const key = await importPKCS8(sa.private_key, "RS256");
  const issuedAt = Math.floor(now / 1000);
  const jwt = await new SignJWT({
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  })
    .setProtectedHeader({ alg: "RS256" })
    .setIssuer(sa.client_email)
    .setSubject(sa.client_email)
    .setAudience("https://oauth2.googleapis.com/token")
    .setIssuedAt(issuedAt)
    .setExpirationTime(issuedAt + 3600)
    .sign(key);

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  const body = (await res.json()) as {
    access_token?: string;
    expires_in?: number;
    error?: string;
  };
  if (!res.ok || !body.access_token) {
    throw new Error(`FCM OAuth failed: ${body.error ?? res.status}`);
  }

  tokenCache = {
    accessToken: body.access_token,
    expiresAtMs: now + (body.expires_in ?? 3600) * 1000,
  };
  return body.access_token;
}

/** FCM HTTP v1. Set secret FCM_SERVICE_ACCOUNT_JSON (Firebase Admin SDK JSON). */
export async function sendPush(
  env: Env,
  opts: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
    kind?: "call" | "message";
  },
): Promise<void> {
  // Ignore placeholder / non-FCM tokens.
  if (!opts.token || opts.token.startsWith("device:")) return;

  const sa = parseServiceAccount(env.FCM_SERVICE_ACCOUNT_JSON);
  if (!sa) {
    console.log(
      JSON.stringify({
        push: "skipped_no_fcm",
        title: opts.title,
        body: opts.body,
        kind: opts.kind ?? "message",
        token: opts.token.slice(0, 8),
      }),
    );
    return;
  }

  const isCall = opts.kind === "call";
  const data: Record<string, string> = {
    ...(opts.data ?? {}),
    title: opts.title,
    body: opts.body,
    kind: opts.kind ?? "message",
  };

  // Calls: data-only high-priority so the Flutter background handler can show
  // a native CallKit-style UI (system notification tap alone is not enough).
  const message = isCall
    ? {
        message: {
          token: opts.token,
          data,
          android: {
            priority: "HIGH" as const,
            ttl: "60s",
          },
        },
      }
    : {
        message: {
          token: opts.token,
          data,
          notification: {
            title: opts.title,
            body: opts.body,
          },
          android: {
            priority: "HIGH" as const,
            ttl: "86400s",
            notification: {
              channelId: "messages",
              sound: "default",
              notificationPriority: "PRIORITY_HIGH",
              clickAction: "FLUTTER_NOTIFICATION_CLICK",
            },
          },
        },
      };

  try {
    const accessToken = await getAccessToken(sa);
    const res = await fetch(
      `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      },
    );
    if (!res.ok) {
      console.error("FCM error", res.status, await res.text());
    }
  } catch (err) {
    console.error("FCM send failed", err);
  }
}

/** Push every other conversation member who has a token. */
export async function notifyConversationMembers(
  env: Env,
  opts: {
    conversationId: string;
    excludeUserId: string;
    title: string;
    body: string;
    data?: Record<string, string>;
    kind?: "call" | "message";
  },
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT u.push_token
     FROM conversation_members cm
     JOIN users u ON u.id = cm.user_id
     WHERE cm.conversation_id = ?
       AND cm.user_id != ?
       AND u.push_token IS NOT NULL
       AND u.push_token != ''`,
  )
    .bind(opts.conversationId, opts.excludeUserId)
    .all<{ push_token: string }>();

  await Promise.all(
    (rows.results ?? []).map((r) =>
      sendPush(env, {
        token: r.push_token,
        title: opts.title,
        body: opts.body,
        data: opts.data,
        kind: opts.kind ?? "message",
      }),
    ),
  );
}
