import type { Env } from "../types";
import type { RealtimeEvent } from "../realtime/user_hub";

export async function publishToUser(
  env: Env,
  userId: string,
  event: RealtimeEvent,
): Promise<void> {
  const hub = env.USER_HUB;
  if (!hub) return;
  try {
    const id = hub.idFromName(userId);
    const stub = hub.get(id);
    await stub.fetch("https://hub/publish", {
      method: "POST",
      body: JSON.stringify({ ...event, ts: Date.now() }),
    });
  } catch (err) {
    console.error("[realtime publish]", userId, err);
  }
}

export async function publishToUsers(
  env: Env,
  userIds: string[],
  event: RealtimeEvent,
): Promise<void> {
  await Promise.all(
    [...new Set(userIds)].map((uid) => publishToUser(env, uid, event)),
  );
}

/** Notify every conversation member except excludeUserId. */
export async function publishToConversation(
  env: Env,
  opts: {
    conversationId: string;
    excludeUserId?: string;
    event: RealtimeEvent;
  },
): Promise<void> {
  const rows = await env.DB.prepare(
    `SELECT user_id FROM conversation_members WHERE conversation_id = ?`,
  )
    .bind(opts.conversationId)
    .all<{ user_id: string }>();

  const ids = (rows.results ?? [])
    .map((r) => r.user_id)
    .filter((id) => id !== opts.excludeUserId);

  await publishToUsers(env, ids, {
    ...opts.event,
    conversationId: opts.conversationId,
  });
}
