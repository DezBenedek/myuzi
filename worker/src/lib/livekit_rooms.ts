import { RoomServiceClient } from "livekit-server-sdk";
import type { Env } from "../types";

/** wss://host → https://host for Room Service API. */
export function liveKitHttpHost(env: Env): string {
  const raw = (env.LIVEKIT_URL || "").trim();
  if (!raw) return "";
  if (raw.startsWith("wss://")) return `https://${raw.slice(6)}`;
  if (raw.startsWith("ws://")) return `http://${raw.slice(5)}`;
  if (raw.startsWith("https://") || raw.startsWith("http://")) return raw;
  return `https://${raw}`;
}

export function liveKitRooms(env: Env): RoomServiceClient | null {
  const host = liveKitHttpHost(env);
  if (!host || !env.LIVEKIT_API_KEY || !env.LIVEKIT_API_SECRET) return null;
  return new RoomServiceClient(host, env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET);
}

export async function ensureLiveKitRoom(
  env: Env,
  opts: {
    roomName: string;
    mode: "direct" | "group";
  },
): Promise<void> {
  const rooms = liveKitRooms(env);
  if (!rooms) return;
  try {
    await rooms.createRoom({
      name: opts.roomName,
      // Drop empty ringing rooms quickly; reconnect grace after last leave.
      emptyTimeout: opts.mode === "direct" ? 45 : 90,
      departureTimeout: opts.mode === "direct" ? 15 : 30,
      maxParticipants: opts.mode === "direct" ? 2 : 6,
    });
  } catch {
    // Room may already exist — ignore.
  }
}

export async function deleteLiveKitRoom(env: Env, roomName: string): Promise<void> {
  const rooms = liveKitRooms(env);
  if (!rooms || !roomName) return;
  try {
    await rooms.deleteRoom(roomName);
  } catch {
    // Already gone.
  }
}

export async function countLiveKitParticipants(
  env: Env,
  roomName: string,
): Promise<number | null> {
  const rooms = liveKitRooms(env);
  if (!rooms || !roomName) return null;
  try {
    const list = await rooms.listParticipants(roomName);
    return list.length;
  } catch {
    return null;
  }
}

export async function removeLiveKitParticipant(
  env: Env,
  roomName: string,
  identity: string,
): Promise<void> {
  const rooms = liveKitRooms(env);
  if (!rooms || !roomName || !identity) return;
  try {
    await rooms.removeParticipant(roomName, identity);
  } catch {
    // Already left.
  }
}
