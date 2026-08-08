function orderedPair(a: string, b: string): [string, string] {
  return a < b ? [a, b] : [b, a];
}

export async function canDirectConnect(
  db: D1Database,
  userA: string,
  userB: string,
): Promise<boolean> {
  const sameFamily = await db
    .prepare(
      `SELECT 1
       FROM family_members a
       JOIN family_members b ON b.family_id = a.family_id
       WHERE a.user_id = ? AND b.user_id = ?`,
    )
    .bind(userA, userB)
    .first();
  if (sameFamily) return true;

  const [familyA, familyB] = orderedPair(userA, userB);
  const acceptedConnection = await db
    .prepare(
      `SELECT 1 FROM user_connections
       WHERE user_a_id = ? AND user_b_id = ? AND status = 'accepted'`,
    )
    .bind(familyA, familyB)
    .first();
  if (acceptedConnection) return true;

  const familyRows = await db
    .prepare(
      `SELECT DISTINCT fm.family_id
       FROM family_members fm
       WHERE fm.user_id IN (?, ?)`,
    )
    .bind(userA, userB)
    .all<{ family_id: string }>();
  const familyIds = [...new Set((familyRows.results ?? []).map((row) => row.family_id))];
  if (familyIds.length < 2) return false;

  for (let i = 0; i < familyIds.length; i++) {
    for (let j = i + 1; j < familyIds.length; j++) {
      const [a, b] = orderedPair(familyIds[i], familyIds[j]);
      const linked = await db
        .prepare(
          `SELECT 1 FROM family_connections
           WHERE family_a_id = ? AND family_b_id = ? AND status = 'active'`,
        )
        .bind(a, b)
        .first();
      if (linked) return true;
    }
  }
  return false;
}
