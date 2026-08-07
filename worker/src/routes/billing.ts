import { Hono } from "hono";
import type { Env, Variables } from "../types";
import { getFamily, getUserFamily, publicFamily } from "../lib/db";
import {
  getStripe,
  hasPaidPlan,
  maxMembersForPlan,
  planFromPriceId,
  PLAN_FEATURES,
} from "../lib/stripe";
import { publicBaseUrl } from "../lib/urls";
import { requireAuth } from "../middleware/auth";

const billing = new Hono<{ Bindings: Env; Variables: Variables }>();

billing.get("/plans", (c) => {
  return c.json({
    plans: [
      PLAN_FEATURES.free,
      {
        ...PLAN_FEATURES.family,
        priceId: c.env.STRIPE_PRICE_FAMILY,
      },
      {
        ...PLAN_FEATURES.family_plus,
        priceId: c.env.STRIPE_PRICE_FAMILY_PLUS,
      },
    ],
  });
});

billing.post("/checkout", requireAuth, async (c) => {
  const body = await c.req.json<{ plan?: "family" | "family_plus" }>();
  const plan = body.plan;
  if (plan !== "family" && plan !== "family_plus") {
    return c.json({ error: "Válassz csomagot" }, 400);
  }

  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Előbb hozz létre családot" }, 400);
  if (family.owner_id !== c.get("userId")) {
    return c.json(
      { error: "Csak a család tulajdonosa fizethet. Kérdezd meg a tulajdonost." },
      403,
    );
  }

  const stripe = getStripe(c.env);
  let customerId = family.stripe_customer_id;

  if (!customerId) {
    const customer = await stripe.customers.create({
      email: c.get("user").email,
      name: c.get("user").name,
      metadata: { familyId: family.id, userId: c.get("userId") },
    });
    customerId = customer.id;
    await c.env.DB.prepare(
      `UPDATE families SET stripe_customer_id = ?, updated_at = datetime('now') WHERE id = ?`,
    )
      .bind(customerId, family.id)
      .run();
  }

  const priceId =
    plan === "family" ? c.env.STRIPE_PRICE_FAMILY : c.env.STRIPE_PRICE_FAMILY_PLUS;

  const base = publicBaseUrl(c.req.url, c.env);
  const session = await stripe.checkout.sessions.create({
    mode: "subscription",
    customer: customerId,
    line_items: [{ price: priceId, quantity: 1 }],
    success_url: `${base}/account?billing=success`,
    cancel_url: `${base}/account?billing=cancel`,
    metadata: { familyId: family.id, plan },
    subscription_data: {
      metadata: { familyId: family.id, plan },
    },
    allow_promotion_codes: true,
    // Billing details are collected in-app and stored in D1 for manual invoicing.
    billing_address_collection: "auto",
  });

  return c.json({ url: session.url });
});

billing.post("/portal", requireAuth, async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ error: "Nincs család" }, 400);
  if (family.owner_id !== c.get("userId")) {
    return c.json({ error: "Csak a tulajdonos kezelheti az előfizetést" }, 403);
  }
  if (!family.stripe_customer_id) {
    return c.json({ error: "Még nincs Stripe ügyfél" }, 400);
  }

  const stripe = getStripe(c.env);
  const portal = await stripe.billingPortal.sessions.create({
    customer: family.stripe_customer_id,
    return_url: `${publicBaseUrl(c.req.url, c.env)}/account`,
  });

  return c.json({ url: portal.url });
});

billing.post("/webhook", async (c) => {
  const stripe = getStripe(c.env);
  const signature = c.req.header("stripe-signature");
  if (!signature) return c.json({ error: "Missing signature" }, 400);

  const raw = await c.req.text();
  let event;
  try {
    event = await stripe.webhooks.constructEventAsync(
      raw,
      signature,
      c.env.STRIPE_WEBHOOK_SECRET,
    );
  } catch (err) {
    console.error("stripe webhook verify failed", err);
    return c.json({ error: "Invalid signature" }, 400);
  }

  switch (event.type) {
    case "checkout.session.completed": {
      const session = event.data.object as {
        metadata?: { familyId?: string; plan?: string };
        subscription?: string | null;
        customer?: string | null;
      };
      const familyId = session.metadata?.familyId;
      const plan = session.metadata?.plan as "family" | "family_plus" | undefined;
      if (familyId && plan) {
        await applyPlan(c.env, familyId, plan, {
          subscriptionId: typeof session.subscription === "string" ? session.subscription : null,
          customerId: typeof session.customer === "string" ? session.customer : null,
          status: "active",
        });
      }
      break;
    }
    case "customer.subscription.updated":
    case "customer.subscription.deleted": {
      const sub = event.data.object as {
        id: string;
        status: string;
        cancel_at_period_end?: boolean;
        metadata?: { familyId?: string; plan?: string; pending_plan?: string };
        items?: { data?: Array<{ price?: { id?: string } }> };
        customer?: string;
      };
      let familyId = sub.metadata?.familyId;
      if (!familyId && sub.customer) {
        const fam = await c.env.DB.prepare(
          "SELECT id FROM families WHERE stripe_customer_id = ?",
        )
          .bind(sub.customer)
          .first<{ id: string }>();
        familyId = fam?.id;
      }
      if (!familyId) break;

      if (event.type === "customer.subscription.deleted" || sub.status === "canceled") {
        await c.env.DB.prepare(
          `UPDATE families SET plan = 'none', stripe_subscription_id = NULL,
           stripe_status = ?, max_members = 3, updated_at = datetime('now') WHERE id = ?`,
        )
          .bind(sub.status, familyId)
          .run();
        break;
      }

      const priceId = sub.items?.data?.[0]?.price?.id;
      // Prefer live price over stale metadata (portal / scheduled changes).
      const planFromPrice = priceId ? planFromPriceId(c.env, priceId) : null;
      const plan =
        planFromPrice ||
        (sub.metadata?.plan as "family" | "family_plus" | undefined) ||
        "family";

      let status = sub.status;
      if (sub.cancel_at_period_end && sub.status === "active") {
        status = "canceling";
      } else if (
        sub.metadata?.pending_plan &&
        hasPaidPlan(sub.metadata.pending_plan) &&
        sub.metadata.pending_plan !== plan
      ) {
        status = `pending:${sub.metadata.pending_plan}`;
      }

      await applyPlan(c.env, familyId, plan, {
        subscriptionId: sub.id,
        customerId: typeof sub.customer === "string" ? sub.customer : null,
        status,
      });
      break;
    }
    default:
      break;
  }

  return c.json({ received: true });
});

billing.get("/status", requireAuth, async (c) => {
  const family = await getUserFamily(c.env.DB, c.get("userId"));
  if (!family) return c.json({ family: null });
  return c.json({
    family: publicFamily(family),
    isOwner: family.owner_id === c.get("userId"),
    plans: [PLAN_FEATURES.free, PLAN_FEATURES.family, PLAN_FEATURES.family_plus],
  });
});

export async function applyPlan(
  env: Env,
  familyId: string,
  plan: "family" | "family_plus",
  opts: { subscriptionId: string | null; customerId: string | null; status: string },
) {
  const family = await getFamily(env.DB, familyId);
  if (!family) return;

  await env.DB.prepare(
    `UPDATE families SET
      plan = ?,
      max_members = ?,
      stripe_subscription_id = COALESCE(?, stripe_subscription_id),
      stripe_customer_id = COALESCE(?, stripe_customer_id),
      stripe_status = ?,
      updated_at = datetime('now')
     WHERE id = ?`,
  )
    .bind(
      plan,
      maxMembersForPlan(plan),
      opts.subscriptionId,
      opts.customerId,
      opts.status,
      familyId,
    )
    .run();
}

export default billing;
