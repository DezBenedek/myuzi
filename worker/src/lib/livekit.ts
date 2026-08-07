import { AccessToken } from "livekit-server-sdk";
import type { Env } from "../types";

export async function createLiveKitToken(
  env: Env,
  opts: {
    identity: string;
    name: string;
    roomName: string;
    canPublish?: boolean;
    canSubscribe?: boolean;
    ttlSeconds?: number;
  },
): Promise<string> {
  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: opts.identity,
    name: opts.name,
    ttl: opts.ttlSeconds ?? 60 * 60 * 2,
  });

  at.addGrant({
    roomJoin: true,
    room: opts.roomName,
    canPublish: opts.canPublish ?? true,
    canSubscribe: opts.canSubscribe ?? true,
    canPublishData: true,
  });

  return await at.toJwt();
}
