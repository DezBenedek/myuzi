import Stripe from "stripe";
import type { Env, PlanId } from "../types";

export function getStripe(env: Env): Stripe {
  const key = (env.STRIPE_SECRET_KEY ?? "").trim();
  if (!key) {
    throw new Error("STRIPE_SECRET_KEY hiányzik");
  }
  // Common misconfig: webhook signing secret (whsec_…) put into STRIPE_SECRET_KEY
  if (key.startsWith("whsec_")) {
    throw new Error(
      "STRIPE_SECRET_KEY rossz: whsec_… webhook secret van beállítva. Tedd a sk_… titkos kulcsot a STRIPE_SECRET_KEY-be, a whsec_… pedig a STRIPE_WEBHOOK_SECRET-be.",
    );
  }
  if (!key.startsWith("sk_")) {
    throw new Error("STRIPE_SECRET_KEY érvénytelen (sk_test_… vagy sk_live_… kell)");
  }
  return new Stripe(key, {
    httpClient: Stripe.createFetchHttpClient(),
  });
}

export function planFromPriceId(env: Env, priceId: string): PlanId | null {
  if (priceId === env.STRIPE_PRICE_FAMILY) return "family";
  if (priceId === env.STRIPE_PRICE_FAMILY_PLUS) return "family_plus";
  return null;
}

/** Free: 3 · Család: 6 · Család+: 25 */
export function maxMembersForPlan(plan: PlanId | "none"): number {
  if (plan === "family_plus") return 25;
  if (plan === "family") return 6;
  return 3;
}

/** Free: 2 p · Család: 10 p · Család+: 20 p */
export function voiceMaxMsForPlan(plan: string | null | undefined): number {
  if (plan === "family_plus") return 20 * 60 * 1000;
  if (plan === "family") return 10 * 60 * 1000;
  return 2 * 60 * 1000;
}

export function hasPaidPlan(plan: string | null | undefined): boolean {
  return plan === "family" || plan === "family_plus";
}

export function planLabel(plan: string): string {
  if (plan === "family_plus") return "Család+";
  if (plan === "family") return "Család";
  return "Ingyenes";
}

export function planSummary(plan: string): string {
  if (plan === "family_plus") {
    return "Család+ · max 25 fő · 20 perc hang · hívás · csoport";
  }
  if (plan === "family") {
    return "Család · max 6 fő · 10 perc hang · hívás · csoport";
  }
  return "Ingyenes · max 3 fő · 2 perc hang · nincs hívás";
}

export const PLAN_PRICES_HUF = {
  family: 1990,
  family_plus: 4990,
} as const;

export const PLAN_FEATURES = {
  free: {
    id: "none",
    name: "Ingyenes",
    priceHuf: 0,
    maxMembers: 3,
    voiceMinutes: 2,
    calls: false,
    groups: false,
  },
  family: {
    id: "family",
    name: "Család",
    priceHuf: PLAN_PRICES_HUF.family,
    maxMembers: 6,
    voiceMinutes: 10,
    calls: true,
    groups: true,
  },
  family_plus: {
    id: "family_plus",
    name: "Család+",
    priceHuf: PLAN_PRICES_HUF.family_plus,
    maxMembers: 25,
    voiceMinutes: 20,
    calls: true,
    groups: true,
  },
} as const;
