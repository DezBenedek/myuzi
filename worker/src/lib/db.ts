import type { Env, FamilyRow, UserRow } from "../types";
import { hasPaidPlan, maxMembersForPlan, voiceMaxMsForPlan } from "./stripe";

export async function getUserById(db: D1Database, id: string): Promise<UserRow | null> {
  return await db.prepare("SELECT * FROM users WHERE id = ?").bind(id).first<UserRow>();
}

export async function getUserByEmail(db: D1Database, email: string): Promise<UserRow | null> {
  return await db.prepare("SELECT * FROM users WHERE email = ?").bind(email).first<UserRow>();
}

export async function getFamily(db: D1Database, id: string): Promise<FamilyRow | null> {
  return await db.prepare("SELECT * FROM families WHERE id = ?").bind(id).first<FamilyRow>();
}

export async function getUserFamily(
  db: D1Database,
  userId: string,
): Promise<(FamilyRow & { role: string }) | null> {
  return await db
    .prepare(
      `SELECT f.*, fm.role AS role
       FROM family_members fm
       JOIN families f ON f.id = fm.family_id
       WHERE fm.user_id = ?
       LIMIT 1`,
    )
    .bind(userId)
    .first<FamilyRow & { role: string }>();
}

export async function isFamilyMember(
  db: D1Database,
  familyId: string,
  userId: string,
): Promise<boolean> {
  const row = await db
    .prepare("SELECT 1 AS ok FROM family_members WHERE family_id = ? AND user_id = ?")
    .bind(familyId, userId)
    .first<{ ok: number }>();
  return !!row;
}

export async function memberCount(db: D1Database, familyId: string): Promise<number> {
  const row = await db
    .prepare("SELECT COUNT(*) AS c FROM family_members WHERE family_id = ?")
    .bind(familyId)
    .first<{ c: number }>();
  return row?.c ?? 0;
}

export async function isConversationMember(
  db: D1Database,
  conversationId: string,
  userId: string,
): Promise<boolean> {
  const row = await db
    .prepare(
      "SELECT 1 AS ok FROM conversation_members WHERE conversation_id = ? AND user_id = ?",
    )
    .bind(conversationId, userId)
    .first<{ ok: number }>();
  return !!row;
}

export function publicUser(u: UserRow) {
  return {
    id: u.id,
    email: u.email,
    name: u.name,
    visionAssist: !!u.vision_assist,
  };
}

export function publicFamily(f: FamilyRow & { role?: string }) {
  return {
    id: f.id,
    name: f.name,
    ownerId: f.owner_id,
    plan: f.plan,
    stripeStatus: f.stripe_status,
    maxMembers: maxMembersForPlan(f.plan),
    role: f.role,
  };
}

/** Soft seat limit based on plan (free = 3). */
export function canAddMember(family: FamilyRow, count: number): boolean {
  return count < maxMembersForPlan(family.plan);
}

export { hasPaidPlan, voiceMaxMsForPlan };
