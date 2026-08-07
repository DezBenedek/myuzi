import Stripe from "stripe";
import type { Env, PlanId } from "../types";

export function getStripe(env: Env): Stripe {
  return new Stripe(env.STRIPE_SECRET_KEY, {
    httpClient: Stripe.createFetchHttpClient(),
    // apiVersion omitted — package default stays compatible with Stripe SDK
  });
}

export function planFromPriceId(env: Env, priceId: string): PlanId | null {
  if (priceId === env.STRIPE_PRICE_FAMILY) return "family";
  if (priceId === env.STRIPE_PRICE_FAMILY_PLUS) return "family_plus";
  return null;
}

export function maxMembersForPlan(plan: PlanId | "none"): number {
  if (plan === "family_plus") return 25;
  if (plan === "family") return 6;
  return 6;
}

export function planLabel(plan: string): string {
  if (plan === "family_plus") return "Család+";
  if (plan === "family") return "Család";
  return "Nincs előfizetés";
}

export const PLAN_PRICES_HUF = {
  family: 1990,
  family_plus: 4990,
} as const;
