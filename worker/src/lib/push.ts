import type { Env } from "../types";

/** Optional FCM legacy HTTP push. Set FCM_SERVER_KEY secret to enable. */
export async function sendPush(
  env: Env & { FCM_SERVER_KEY?: string },
  opts: {
    token: string;
    title: string;
    body: string;
    data?: Record<string, string>;
  },
): Promise<void> {
  const key = (env as { FCM_SERVER_KEY?: string }).FCM_SERVER_KEY;
  if (!key) {
    console.log(JSON.stringify({ push: "skipped_no_fcm", ...opts, token: opts.token.slice(0, 8) }));
    return;
  }

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
        sound: "default",
      },
      data: opts.data ?? {},
      content_available: true,
    }),
  });

  if (!res.ok) {
    console.error("FCM error", res.status, await res.text());
  }
}
