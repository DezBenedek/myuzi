/** Generated placeholder — run `npm run types` after configuring wrangler bindings. */
interface Env {
  DB: D1Database;
  VOICE: R2Bucket;
  EMAIL: {
    send(message: {
      to: string | { email: string; name?: string } | Array<string | { email: string; name?: string }>;
      from: string | { email: string; name?: string };
      subject: string;
      html?: string;
      text?: string;
    }): Promise<{ messageId: string }>;
  };
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
