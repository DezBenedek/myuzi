import type { Env } from "../types";

export const PRIMARY_HOST = "myuzi.uvmr.app";

const ALLOWED_HOSTS = new Set([PRIMARY_HOST, "localhost", "127.0.0.1"]);

/** Public site/API base for the current request. */
export function publicBaseUrl(reqUrl: string, env: Env): string {
  const url = new URL(reqUrl);
  const host = url.hostname.toLowerCase();

  if (ALLOWED_HOSTS.has(host)) {
    const proto = host === "localhost" || host === "127.0.0.1" ? "http" : "https";
    const port = url.port && url.port !== "443" && url.port !== "80" ? `:${url.port}` : "";
    return `${proto}://${host}${port}`;
  }

  // Always prefer the canonical app URL — never workers.dev
  return env.APP_URL || `https://${PRIMARY_HOST}`;
}

export function primaryAppUrl(env: Env): string {
  return env.APP_URL || `https://${PRIMARY_HOST}`;
}

export function allAppUrls(env: Env): string[] {
  return [primaryAppUrl(env)];
}
