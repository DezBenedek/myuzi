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
.compare { width: 100%; border-collapse: collapse; margin: 12px 0 18px; font-size: 0.95rem; }
.compare th, .compare td { border-bottom: 1px solid var(--line); padding: 10px 8px; text-align: left; vertical-align: top; }
.compare th { color: var(--muted); font-weight: 700; }
.compare .yes { color: var(--brand); font-weight: 700; }
.compare .no { color: var(--muted); }
.plan-pick { display: grid; gap: 10px; margin: 12px 0; }
.plan-pick label {
  display: flex; gap: 12px; align-items: flex-start;
  border: 1px solid var(--line); border-radius: 14px; padding: 12px 14px; margin: 0; font-weight: 600;
  cursor: pointer;
}
.plan-pick input { width: auto; margin-top: 4px; }
.plan-card {
  border: 1px solid var(--line);
  border-radius: 16px;
  padding: 18px 16px;
  background: #fafdfb;
}
.plan-card h3 { margin: 0 0 4px; font-size: 1.35rem; }
.plan-card .price { font-size: 1.1rem; font-weight: 700; color: var(--brand); margin: 0 0 12px; }
.plan-card ul { margin: 0 0 14px; padding-left: 1.1rem; color: var(--muted); }
.plan-card li { margin: 6px 0; }
.plan-current { margin: 0 0 4px; font-size: 1.2rem; font-weight: 750; }
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
    <p class="footer">MyÜzi · myuzi.uvmr.app</p>
  </div>
</body>
</html>`;
}

export function landingPage(): string {
  return layout(
    "Kezdőlap",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Családi hangüzenetek és hívások.</p>
    <div class="panel">
      <div class="row">
        <a href="/account"><button type="button">Fiókkezelő</button></a>
        <a href="/login"><button class="secondary" type="button">Belépés</button></a>
      </div>
    </div>
  `,
  );
}

export function loginPage(error = ""): string {
  return layout(
    "Belépés",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Email + kód.</p>
    <div class="panel">
      <form method="POST" action="/login">
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

export function verifyPage(
  email: string,
  error = "",
  askName = false,
  verifiedCode = "",
  opts?: { inviteToken?: string; familyName?: string },
): string {
  const inviteToken = opts?.inviteToken ?? "";
  const familyName = opts?.familyName ?? "";
  const inviteHidden = inviteToken
    ? `<input type="hidden" name="inviteToken" value="${escape(inviteToken)}" />`
    : "";
  const sub = askName
    ? "A kód rendben. Add meg a beceneved."
    : familyName
      ? `Meghívó: <strong>${escape(familyName)}</strong><br/>Kódot küldtünk ide: <strong>${escape(email)}</strong>`
      : `Kód: <strong>${escape(email)}</strong>`;

  return layout(
    askName ? "Becenév" : familyName ? "Meghívó" : "Kód",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">${sub}</p>
    <div class="panel">
      <form method="POST" action="/login/verify">
        <input type="hidden" name="email" value="${escape(email)}" />
        ${inviteHidden}
        ${
          askName
            ? `<input type="hidden" name="code" value="${escape(verifiedCode)}" />
        <label for="name">Becenév</label>
        <input id="name" name="name" required minlength="2" autocomplete="nickname" autofocus />
        <button type="submit">${inviteToken ? "Csatlakozom" : "Belépek"}</button>`
            : `<label for="code">Kód</label>
        <input id="code" name="code" inputmode="numeric" pattern="\\d{6}" maxlength="6" required autocomplete="one-time-code" autofocus />
        <button type="submit">Tovább</button>`
        }
        ${error ? `<p class="error">${error}</p>` : ""}
      </form>
    </div>
  `,
  );
}

/** Invite link without a locked email — ask for email, then we send the PIN. */
export function inviteEmailPage(familyName: string, token: string, error = ""): string {
  return layout(
    "Meghívó",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Meghívót kaptál a(z) <strong>${escape(familyName)}</strong> családba.</p>
    ${error ? `<p class="error">${escape(error)}</p>` : ""}
    <div class="panel">
      <form method="POST" action="/invite/${escape(token)}/start">
        <label for="email">Email címed</label>
        <input id="email" name="email" type="email" required autocomplete="email" autofocus />
        <button type="submit">Kód küldése</button>
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
  const currentPlan =
    family?.plan === "family_plus"
      ? "Family+"
      : family?.plan === "family"
        ? "Family"
        : "Free";
  const planLimits =
    family?.plan === "family_plus"
      ? "max 25 tag · 20 perc hangüzenet · hang- és videóhívás · csoport"
      : family?.plan === "family"
        ? "max 6 tag · 10 perc hangüzenet · hang- és videóhívás · csoport"
        : "max 3 tag · 2 perc hangüzenet · nincs hívás · nincs csoport";

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
        <p><span class="pill">${members.length} tag</span></p>
        <ul class="list">
          ${members
            .map((m) => {
              const canRemove = isOwner && m.id !== user.id && m.role !== "owner";
              const canLeave = !isOwner && m.id === user.id;
              return `<li>
                <span><strong>${escape(m.name)}</strong><br/><span class="hint">${escape(m.email)}</span></span>
                <span style="display:flex;align-items:center;gap:8px">
                  <span class="pill">${m.role === "owner" ? "Tulajdonos" : "Tag"}</span>
                  ${
                    canRemove
                      ? `<form method="POST" action="/account/members/remove" style="margin:0" onsubmit="return confirm('Eltávolítod ${escape(m.name)}-t a családból?')">
                          <input type="hidden" name="userId" value="${escape(m.id)}" />
                          <button class="ghost" type="submit" style="margin:0;padding:8px 12px;width:auto">Eltávolít</button>
                        </form>`
                      : canLeave
                        ? `<form method="POST" action="/account/members/remove" style="margin:0" onsubmit="return confirm('Kilépsz a családból?')">
                          <input type="hidden" name="userId" value="${escape(m.id)}" />
                          <button class="ghost" type="submit" style="margin:0;padding:8px 12px;width:auto">Kilépek</button>
                        </form>`
                        : ""
                  }
                </span>
              </li>`;
            })
            .join("")}
        </ul>
        <form method="POST" action="/account/invite" style="margin-top:16px">
          <label for="inv">Meghívó email</label>
          <input id="inv" name="email" type="email" placeholder="családtag@email.hu" />
          <button type="submit">Meghívó</button>
        </form>
        ${inviteUrl ? `<p class="ok"><a href="${inviteUrl}">${inviteUrl}</a></p>` : ""}
      </div>
      ${
        isOwner
          ? `<div class="panel">
        <p class="plan-current">Jelenlegi csomagod: ${currentPlan}</p>
        <p class="hint">${planLimits}</p>
        <form method="GET" action="/account/plans" style="margin-top:14px">
          <button type="submit">Előfizetés</button>
        </form>
        ${
          family.plan === "family" || family.plan === "family_plus"
            ? `<form method="POST" action="/account/portal"><button class="ghost" type="submit">Stripe portál</button></form>`
            : ""
        }
      </div>`
          : ""
      }`;

  return layout(
    "Fiók",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">${escape(user.name)}</p>
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

export function plansPage(opts: {
  user: UserRow;
  currentPlan: string;
}): string {
  const { user, currentPlan } = opts;
  const familyActive = currentPlan === "family";
  const plusActive = currentPlan === "family_plus";

  return layout(
    "Előfizetés",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Válassz csomagot</p>
    <div class="panel" style="display:grid;gap:14px">
      <div class="plan-card">
        <h3>Family</h3>
        <p class="price">1990 Ft/hó</p>
        <ul>
          <li>6 tag</li>
          <li>10 perc hangüzenet</li>
          <li>Hang- és videóhívás</li>
          <li>Csoportok</li>
        </ul>
        <form method="GET" action="/account/billing">
          <input type="hidden" name="plan" value="family" />
          <button type="submit"${familyActive ? " class=\"secondary\"" : ""}>${
            familyActive ? "Jelenlegi csomag" : "Ezt választom"
          }</button>
        </form>
      </div>
      <div class="plan-card">
        <h3>Family+</h3>
        <p class="price">4990 Ft/hó</p>
        <ul>
          <li>25 tag</li>
          <li>20 perc hangüzenet</li>
          <li>Hang- és videóhívás</li>
          <li>Csoportok</li>
        </ul>
        <form method="GET" action="/account/billing">
          <input type="hidden" name="plan" value="family_plus" />
          <button type="submit"${plusActive ? " class=\"secondary\"" : ""}>${
            plusActive ? "Jelenlegi csomag" : "Ezt választom"
          }</button>
        </form>
      </div>
      <form method="GET" action="/account">
        <button class="ghost" type="submit">Vissza</button>
      </form>
    </div>
  `,
    !!user.vision_assist,
  );
}

export function billingPage(opts: {
  user: UserRow;
  plan: "family" | "family_plus";
  billing?: {
    billing_type?: string | null;
    billing_name?: string | null;
    billing_tax_id?: string | null;
    billing_address_line1?: string | null;
    billing_city?: string | null;
    billing_postal_code?: string | null;
    billing_country?: string | null;
  };
  error?: string;
}): string {
  const { user, plan, billing, error } = opts;
  const isCompany = billing?.billing_type === "company";
  const planName = plan === "family_plus" ? "Family+" : "Family";
  const price = plan === "family_plus" ? "4990" : "1990";
  const savedName = billing?.billing_name ?? "";
  const savedTax = billing?.billing_tax_id ?? "";
  const savedAddr = billing?.billing_address_line1 ?? "";
  const savedCity = billing?.billing_city ?? "";
  const savedPostal = billing?.billing_postal_code ?? "";

  return layout(
    "Számlázás",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">${planName} · ${price} Ft/hó</p>
    ${error ? `<p class="error">${error}</p>` : ""}
    <div class="panel">
      <p class="hint">A számlázási adatok nálunk maradnak (manuális számla). A Stripe nem kéri őket újra.</p>
      <form method="POST" action="/account/checkout">
        <input type="hidden" name="plan" value="${plan}" />
        <label for="billingType">Számlázás</label>
        <select id="billingType" name="billingType" onchange="document.getElementById('company-fields').style.display=this.value==='company'?'block':'none'">
          <option value="individual" ${!isCompany ? "selected" : ""}>Magánszemély</option>
          <option value="company" ${isCompany ? "selected" : ""}>Cég</option>
        </select>
        <label for="billingName">Számlázási név</label>
        <input id="billingName" name="billingName" required minlength="2" value="${escape(savedName)}" autocomplete="organization" />
        <div id="company-fields" style="display:${isCompany ? "block" : "none"}">
          <label for="taxId">Adószám</label>
          <input id="taxId" name="taxId" value="${escape(savedTax)}" />
        </div>
        <label for="addressLine1">Cím</label>
        <input id="addressLine1" name="addressLine1" required value="${escape(savedAddr)}" autocomplete="street-address" />
        <div class="row">
          <div>
            <label for="postalCode">Irányítószám</label>
            <input id="postalCode" name="postalCode" required value="${escape(savedPostal)}" autocomplete="postal-code" />
          </div>
          <div>
            <label for="city">Város</label>
            <input id="city" name="city" required value="${escape(savedCity)}" autocomplete="address-level2" />
          </div>
        </div>
        <input type="hidden" name="country" value="${escape(billing?.billing_country || "HU")}" />
        <button type="submit">Fizetés</button>
      </form>
      <form method="GET" action="/account/plans" style="margin-top:8px">
        <button class="ghost" type="submit">Vissza</button>
      </form>
    </div>
  `,
    !!user.vision_assist,
  );
}

export function inviteAcceptPage(
  familyName: string,
  token: string,
  loggedIn: boolean,
  error = "",
): string {
  return layout(
    "Meghívó",
    `
    <h1 class="brand">MyÜzi</h1>
    <p class="sub">Meghívót kaptál a(z) <strong>${escape(familyName)}</strong> családba.</p>
    ${error ? `<p class="error">${escape(error)}</p>` : ""}
    <div class="panel">
      ${
        loggedIn
          ? error
            ? `<p class="hint">Csatlakozás most nem lehetséges.</p><a href="/account"><button type="button">Fiók</button></a>`
            : `<form method="POST" action="/invite/${escape(token)}/accept"><button type="submit">Csatlakozom</button></form>`
          : `<p class="hint">Küldjük a belépési kódot…</p>`
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
