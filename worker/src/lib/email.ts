import type { Env } from "../types";

type EmailPayload = {
  to: string;
  subject: string;
  html: string;
  text: string;
};

export async function sendEmail(env: Env, payload: EmailPayload): Promise<void> {
  if (!env.EMAIL) {
    console.log("[email:dev]", payload.to, payload.subject, payload.text);
    return;
  }

  await env.EMAIL.send({
    to: payload.to,
    from: {
      email: env.FROM_EMAIL,
      name: env.APP_NAME,
    },
    subject: payload.subject,
    html: payload.html,
    text: payload.text,
  });
}

export function loginCodeEmail(appName: string, name: string, code: string) {
  const text = `Szia ${name}!\n\nA belépési kódod: ${code}\n\n10 percig érvényes.\n\n— ${appName}`;
  const html = `
    <div style="font-family:system-ui,sans-serif;max-width:420px;margin:0 auto;padding:24px">
      <h1 style="font-size:22px;margin:0 0 12px">${appName}</h1>
      <p style="font-size:16px">Szia ${escapeHtml(name)}!</p>
      <p style="font-size:16px">A belépési kódod:</p>
      <p style="font-size:36px;letter-spacing:8px;font-weight:700;margin:16px 0">${code}</p>
      <p style="color:#555;font-size:14px">10 percig érvényes.</p>
    </div>`;
  return { subject: `${appName} belépési kód: ${code}`, html, text };
}

export function inviteEmail(
  appName: string,
  familyName: string,
  inviterName: string,
  inviteUrl: string,
) {
  const text = `${inviterName} meghívott a(z) „${familyName}” családba a ${appName} alkalmazásban.\n\nCsatlakozás: ${inviteUrl}`;
  const html = `
    <div style="font-family:system-ui,sans-serif;max-width:420px;margin:0 auto;padding:24px">
      <h1 style="font-size:22px;margin:0 0 12px">${appName}</h1>
      <p style="font-size:16px"><strong>${escapeHtml(inviterName)}</strong> meghívott a(z) <strong>${escapeHtml(familyName)}</strong> családba.</p>
      <p style="margin:24px 0">
        <a href="${inviteUrl}" style="background:#0B6E4F;color:#fff;text-decoration:none;padding:14px 22px;border-radius:12px;font-size:18px;display:inline-block">Csatlakozom</a>
      </p>
      <p style="color:#555;font-size:13px">${inviteUrl}</p>
    </div>`;
  return { subject: `Meghívó: ${familyName} — ${appName}`, html, text };
}

function escapeHtml(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
