import { hmacSha256, timingSafeEqual } from "./crypto";

const TICKET_TTL_SEC = 90;

/** Short-lived WS ticket so the long-lived session token is not put in query logs. */
export async function mintRealtimeTicket(
  secret: string,
  userId: string,
): Promise<{ ticket: string; expiresIn: number }> {
  const exp = Math.floor(Date.now() / 1000) + TICKET_TTL_SEC;
  const payload = `${userId}.${exp}`;
  const sig = await hmacSha256(secret, `ws-ticket:${payload}`);
  return { ticket: `${payload}.${sig}`, expiresIn: TICKET_TTL_SEC };
}

export async function verifyRealtimeTicket(
  secret: string,
  ticket: string,
): Promise<string | null> {
  const raw = ticket.trim();
  if (!raw || raw.length > 512) return null;
  const parts = raw.split(".");
  if (parts.length !== 3) return null;
  const [userId, expStr, sig] = parts;
  if (!userId || !/^[A-Za-z0-9_-]{6,80}$/.test(userId)) return null;
  const exp = Number(expStr);
  if (!Number.isFinite(exp) || exp < Math.floor(Date.now() / 1000)) return null;
  const expect = await hmacSha256(secret, `ws-ticket:${userId}.${expStr}`);
  if (!timingSafeEqual(sig, expect)) return null;
  return userId;
}
