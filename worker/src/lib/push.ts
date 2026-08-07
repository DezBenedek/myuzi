import type { Env } from "../types";

/** Optional FCM legacy HTTP push. Set FCM_SERVER_KEY secret to enable. */
export async function sendPush(
  env: Env & { FCM_SERVER_KEY?: string },
  opts: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
    /** ringing / message */
    kind?: "call" | "message";
  },
): Promise<void> {
  const key = (env as { FCM_SERVER_KEY?: string }).FCM_SERVER_KEY;
  if (!key) {
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
  const res = await fetch("https://fcm.googleapis.com/fcm/send", {
    method: "POST",
    headers: {
      Authorization: `key=${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      to: opts.token,
      priority: "high",
      notification: {
        title: opts.title,
        body: opts.body,
        sound: isCall ? "ringtone" : "default",
        android_channel_id: isCall ? "incoming_calls" : "messages",
      },
      data: opts.data ?? {},
      content_available: true,
    }),
  });

  if (!res.ok) {
    console.error("FCM error", res.status, await res.text());
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
