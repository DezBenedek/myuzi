import type { UserRow } from "../types";

const css = `
:root {
  --bg: #f3f7f4;
  --ink: #12261c;
  --muted: #4d6358;
  --brand: #0b6e4f;
  --brand-2: #14966c;
  --card: #ffffff;
  --line: #d7e4dc;
  --danger: #b42318;
  --radius: 18px;
  --font: "Segoe UI", system-ui, -apple-system, sans-serif;
}
* { box-sizing: border-box; }
body {
  margin: 0;
  font-family: var(--font);
  color: var(--ink);
  background:
    radial-gradient(1200px 500px at 10% -10%, #d9f2e6 0%, transparent 60%),
    radial-gradient(900px 400px at 100% 0%, #e8f4ff 0%, transparent 55%),
    var(--bg);
  min-height: 100vh;
}
a { color: var(--brand); }
.wrap { max-width: 720px; margin: 0 auto; padding: 28px 18px 64px; }
.brand {
  font-size: clamp(2rem, 6vw, 3rem);
  font-weight: 800;
  letter-spacing: -0.03em;
  margin: 0;
}
.sub { color: var(--muted); font-size: 1.05rem; margin: 8px 0 28px; }
.panel {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 22px;
  margin-bottom: 18px;
}
label { display: block; font-weight: 650; margin: 14px 0 6px; }
input, button, select {
  font: inherit;
  width: 100%;
  border-radius: 14px;
  padding: 14px 16px;
  border: 1px solid var(--line);
}
input { background: #fff; }
button {
  background: var(--brand);
  color: #fff;
  border: none;
  font-weight: 700;
  cursor: pointer;
  margin-top: 14px;
}
button.secondary { background: #e8f3ee; color: var(--brand); }
button.ghost { background: transparent; color: var(--brand); border: 1px solid var(--line); }
.row { display: flex; gap: 10px; flex-wrap: wrap; }
.row > * { flex: 1; min-width: 140px; }
.hint { color: var(--muted); font-size: 0.95rem; }
.error { color: var(--danger); margin-top: 10px; }
.ok { color: var(--brand); margin-top: 10px; }
.big { font-size: 1.25rem; }
.switch {
  display: flex; align-items: center; gap: 12px;
  margin-top: 16px; font-weight: 650;
}
.switch input { width: auto; }
.list { list-style: none; padding: 0; margin: 0; }
.list li {
  display: flex; justify-content: space-between; gap: 12px;
  padding: 12px 0; border-bottom: 1px solid var(--line);
}
.pill {
  display: inline-block; padding: 4px 10px; border-radius: 999px;
  background: #e8f3ee; color: var(--brand); font-size: 0.85rem; font-weight: 700;
}
.footer { margin-top: 28px; color: var(--muted); font-size: 0.9rem; }
@media (max-width: 520px) {
  .wrap { padding: 18px 14px 48px; }
  button, input { min-height: 52px; }
}
`;

export function layout(title: string, body: string, vision = false): string {
  const visionCss = vision
    ? `body{font-size:1.2rem} .brand{font-size:3.2rem} button,input{min-height:60px;font-size:1.15rem;font-weight:800;border-width:2px}
       :root{--ink:#000;--bg:#fff;--brand:#004d33;--line:#000}`
    : "";
  return `<!doctype html>
<html lang="hu">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${title} · MyÜzi</title>
  <style>${css}${visionCss}</style>
</head>
<body>
  <div class="wrap">
    ${body}
    <p class="footer">MyÜzi · családi hangüzenetek és hívások · myuzi.dezso.hu</p>
  </div>
</body>
</html>`;
}

export function landingPage(): string {
  return layout(
    "Kezdőlap",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Egyszerű családi hangüzenetek és hívások — telefonon, tableten és számítógépen.</p>
    <div class="panel">
      <p class="big">Töltsd le az appot, vagy kezeld a fiókodat a weben.</p>
      <div class="row">
        <a href="/account"><button type="button">Fiókkezelő</button></a>
        <a href="/login"><button class="secondary" type="button">Belépés</button></a>
      </div>
      <p class="hint" style="margin-top:16px">Hangüzenet · hanghívás · videó · kijelzőmegosztás</p>
    </div>
  `,
  );
}

export function loginPage(error = ""): string {
  return layout(
    "Belépés",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Belépés email kóddal — jelszó nem kell.</p>
    <div class="panel">
      <form method="POST" action="/login">
        <label for="name">Neved</label>
        <input id="name" name="name" required minlength="2" autocomplete="name" />
        <label for="email">Email</label>
        <input id="email" name="email" type="email" required autocomplete="email" />
        <label class="switch">
          <input type="checkbox" name="visionAssist" value="1" />
          Látássérült segítség
        </label>
        <button type="submit">Kód küldése</button>
        ${error ? `<p class="error">${error}</p>` : ""}
      </form>
    </div>
  `,
  );
}

export function verifyPage(email: string, error = ""): string {
  return layout(
    "Kód",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Írd be a 6 számjegyű kódot, amit elküldtünk ide: <strong>${email}</strong></p>
    <div class="panel">
      <form method="POST" action="/login/verify">
        <input type="hidden" name="email" value="${email}" />
        <label for="code">Kód</label>
        <input id="code" name="code" inputmode="numeric" pattern="\\d{6}" maxlength="6" required autocomplete="one-time-code" />
        <button type="submit">Belépek</button>
        ${error ? `<p class="error">${error}</p>` : ""}
      </form>
    </div>
  `,
  );
}

export function accountPage(opts: {
  user: UserRow;
  family: null | {
    id: string;
    name: string;
    plan: string;
    max_members: number;
    role: string;
    owner_id: string;
    stripe_status: string | null;
  };
  members: Array<{ id: string; name: string; email: string; role: string }>;
  inviteUrl?: string;
  message?: string;
  error?: string;
}): string {
  const { user, family, members, inviteUrl, message, error } = opts;
  const isOwner = family?.owner_id === user.id;
  const planLabel =
    family?.plan === "family_plus"
      ? "Család+"
      : family?.plan === "family"
        ? "Család"
        : "Nincs előfizetés";

  const familyBlock = !family
    ? `
      <div class="panel">
        <h2>Család létrehozása</h2>
        <form method="POST" action="/account/family">
          <label for="fname">Család neve</label>
          <input id="fname" name="name" required minlength="2" placeholder="Pl. Nagy család" />
          <button type="submit">Létrehozom</button>
        </form>
      </div>`
    : `
      <div class="panel">
        <h2>${escape(family.name)}</h2>
        <p><span class="pill">${planLabel}</span> · max ${family.max_members} fő · ${members.length} tag</p>
        <ul class="list">
          ${members
            .map(
              (m) =>
                `<li><span><strong>${escape(m.name)}</strong><br/><span class="hint">${escape(m.email)}</span></span><span class="pill">${m.role === "owner" ? "Tulajdonos" : "Tag"}</span></li>`,
            )
            .join("")}
        </ul>
        <form method="POST" action="/account/invite" style="margin-top:16px">
          <label for="inv">Meghívó email (opcionális)</label>
          <input id="inv" name="email" type="email" placeholder="családtag@email.hu" />
          <button type="submit">Meghívó link készítése</button>
        </form>
        ${inviteUrl ? `<p class="ok">Meghívó: <a href="${inviteUrl}">${inviteUrl}</a></p>` : ""}
      </div>
      ${
        isOwner
          ? `<div class="panel">
        <h2>Előfizetés</h2>
        <p class="hint">Csak a tulajdonos fizet. Az appban nincs agresszív paywall — itt tudsz előfizetni.</p>
        <div class="row">
          <form method="POST" action="/account/checkout"><input type="hidden" name="plan" value="family" /><button type="submit">Család — 1990 Ft/hó (6 fő)</button></form>
          <form method="POST" action="/account/checkout"><input type="hidden" name="plan" value="family_plus" /><button class="secondary" type="submit">Család+ — 4990 Ft/hó (25 fő)</button></form>
        </div>
        <form method="POST" action="/account/portal"><button class="ghost" type="submit">Stripe ügyfélportál</button></form>
      </div>`
          : `<div class="panel"><p class="hint">Az előfizetést a család tulajdonosa intézi a weben.</p></div>`
      }`;

  return layout(
    "Fiók",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Szia ${escape(user.name)}!</p>
    ${message ? `<p class="ok">${message}</p>` : ""}
    ${error ? `<p class="error">${error}</p>` : ""}
    <div class="panel">
      <p><strong>${escape(user.name)}</strong><br/><span class="hint">${escape(user.email)}</span></p>
      <form method="POST" action="/account/vision">
        <label class="switch">
          <input type="checkbox" name="visionAssist" value="1" ${user.vision_assist ? "checked" : ""} onchange="this.form.submit()" />
          Látássérült segítség
        </label>
      </form>
      <form method="POST" action="/logout"><button class="ghost" type="submit">Kijelentkezés</button></form>
    </div>
    ${familyBlock}
  `,
    !!user.vision_assist,
  );
}

export function inviteAcceptPage(familyName: string, token: string, loggedIn: boolean): string {
  return layout(
    "Meghívó",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Meghívót kaptál a(z) <strong>${escape(familyName)}</strong> családba.</p>
    <div class="panel">
      ${
        loggedIn
          ? `<form method="POST" action="/invite/${token}/accept"><button type="submit">Csatlakozom</button></form>`
          : `<p>Előbb lépj be ugyanezzel az emaillel.</p><a href="/login"><button type="button">Belépés</button></a>`
      }
    </div>
  `,
  );
}

function escape(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
