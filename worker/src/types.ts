/** Secrets via `wrangler secret put`:
 * SESSION_SECRET
 * LIVEKIT_API_KEY
 * LIVEKIT_API_SECRET
 * STRIPE_SECRET_KEY
 * STRIPE_WEBHOOK_SECRET
 * FCM_SERVER_KEY (opcionális)
 *
 * Email: Cloudflare Email Service `send_email` binding (`EMAIL`)
 * — onboardeld a dezso.run domaint az Email Sendingben.
 */

type EmailAddress = {
  email: string;
  name?: string;
};

/** Cloudflare Email Service Workers binding (EmailMessageBuilder). */
type SendEmail = {
  send(message: {
    to: string | EmailAddress | (string | EmailAddress)[];
    from: string | EmailAddress;
    subject: string;
    html?: string;
    text?: string;
    cc?: string | EmailAddress | (string | EmailAddress)[];
    bcc?: string | EmailAddress | (string | EmailAddress)[];
    replyTo?: string | EmailAddress;
    headers?: Record<string, string>;
  }): Promise<{ messageId: string }>;
};

interface Env {
  DB: D1Database;
  VOICE: R2Bucket;
  EMAIL: SendEmail;
  APP_NAME: string;
  APP_URL: string;
  LIVEKIT_URL: string;
  FROM_EMAIL: string;
  STRIPE_PRICE_FAMILY: string;
  STRIPE_PRICE_FAMILY_PLUS: string;
  SESSION_SECRET: string;
  LIVEKIT_API_KEY: string;
  LIVEKIT_API_SECRET: string;
  STRIPE_SECRET_KEY: string;
  STRIPE_WEBHOOK_SECRET: string;
  FCM_SERVER_KEY?: string;
}

type Variables = {
  userId: string;
  user: UserRow;
};

type UserRow = {
  id: string;
  email: string;
  name: string;
  vision_assist: number;
  push_token: string | null;
  push_platform: string | null;
  created_at: string;
  updated_at: string;
};

type FamilyRow = {
  id: string;
  name: string;
  owner_id: string;
  plan: "none" | "family" | "family_plus";
  stripe_customer_id: string | null;
  stripe_subscription_id: string | null;
  stripe_status: string | null;
  max_members: number;
  created_at: string;
  updated_at: string;
};

type PlanId = "family" | "family_plus";

export type { Env, Variables, UserRow, FamilyRow, PlanId, SendEmail };
