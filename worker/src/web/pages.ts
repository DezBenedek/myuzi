import type { UserRow } from "../types";
import type { InvoiceSummary } from "../lib/stripe";

const css = `
:root {
  --bg: #eef4f0;
  --bg-deep: #0d1c16;
  --ink: #12261c;
  --muted: #4d6358;
  --brand: #0b6e4f;
  --brand-2: #14966c;
  --brand-soft: #d5efe4;
  --card: #ffffff;
  --line: #cfe0d6;
  --danger: #b42318;
  --ok: #0b6e4f;
  --radius: 16px;
  --font: "Segoe UI", system-ui, -apple-system, sans-serif;
  --display: "Segoe UI", system-ui, -apple-system, sans-serif;
  --shadow-soft: 0 18px 40px rgba(18, 38, 28, 0.08);
  --safe-top: env(safe-area-inset-top, 0px);
  --safe-bottom: env(safe-area-inset-bottom, 0px);
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  min-height: 100dvh;
  font-family: var(--font);
  color: var(--ink);
  background: var(--bg);
  -webkit-font-smoothing: antialiased;
}
a { color: var(--brand); }
button, input, select, textarea { font: inherit; }
button {
  border: none;
  border-radius: 14px;
  padding: 14px 18px;
  background: var(--brand);
  color: #fff;
  font-weight: 700;
  cursor: pointer;
}
button:disabled { opacity: 0.55; cursor: not-allowed; }
button.secondary { background: var(--brand-soft); color: var(--brand); }
button.ghost {
  background: transparent;
  color: var(--brand);
  border: 1px solid var(--line);
}
button.danger { background: var(--danger); color: #fff; }
label { display: block; font-weight: 650; margin: 14px 0 6px; }
input, select, textarea {
  width: 100%;
  border-radius: 14px;
  padding: 14px 16px;
  border: 1px solid var(--line);
  background: #fff;
  color: var(--ink);
}
.hint { color: var(--muted); font-size: 0.95rem; }
.error { color: var(--danger); margin-top: 10px; }
.ok { color: var(--ok); margin-top: 10px; }
.pill {
  display: inline-block;
  padding: 4px 10px;
  border-radius: 999px;
  background: var(--brand-soft);
  color: var(--brand);
  font-size: 0.85rem;
  font-weight: 700;
}
.row { display: flex; gap: 10px; flex-wrap: wrap; }
.row > * { flex: 1; min-width: 140px; }
.switch {
  display: flex; align-items: center; gap: 12px;
  margin-top: 16px; font-weight: 650;
}
.switch input { width: auto; }
.list { list-style: none; padding: 0; margin: 0; }
.list li {
  display: flex; justify-content: space-between; gap: 12px;
  padding: 14px 0; border-bottom: 1px solid var(--line);
}
.panel {
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  padding: 22px;
  margin-bottom: 16px;
}
.brand-mark {
  font-family: var(--display);
  font-weight: 800;
  letter-spacing: -0.04em;
  margin: 0;
  line-height: 0.95;
}
.sub { color: var(--muted); font-size: 1.05rem; margin: 8px 0 24px; }

/* ——— Page chrome (account / forms) ——— */
.page {
  min-height: 100dvh;
  display: flex;
  flex-direction: column;
}
.page-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: calc(16px + var(--safe-top)) 22px 12px;
  border-bottom: 1px solid transparent;
}
.page-top a.logo {
  font-family: var(--display);
  font-weight: 800;
  font-size: 1.35rem;
  letter-spacing: -0.03em;
  color: var(--ink);
  text-decoration: none;
}
.page-nav { display: flex; gap: 8px; flex-wrap: wrap; }
.page-nav a { text-decoration: none; }
.page-nav button { margin: 0; width: auto; padding: 10px 14px; min-height: 44px; }
.page-body {
  flex: 1;
  width: min(720px, 100%);
  margin: 0 auto;
  padding: 28px 18px calc(40px + var(--safe-bottom));
}
.page-body h1.brand-mark { font-size: clamp(2.2rem, 6vw, 3rem); }
.page-foot {
  text-align: center;
  color: var(--muted);
  font-size: 0.85rem;
  padding: 0 18px calc(20px + var(--safe-bottom));
}

/* ——— Auth: full-viewport ——— */
.auth-screen {
  min-height: 100dvh;
  display: grid;
  grid-template-columns: 1.05fr 0.95fr;
  background: var(--bg-deep);
}
.auth-visual {
  position: relative;
  overflow: hidden;
  min-height: 42vh;
  background:
    radial-gradient(800px 500px at 20% 20%, rgba(20, 150, 108, 0.35), transparent 60%),
    radial-gradient(700px 420px at 90% 80%, rgba(90, 160, 120, 0.18), transparent 55%),
    linear-gradient(160deg, #0d1c16 0%, #143528 48%, #0a1612 100%);
  color: #e8f4ee;
  padding: calc(36px + var(--safe-top)) 40px 40px;
  display: flex;
  flex-direction: column;
  justify-content: space-between;
}
.auth-visual .brand-mark { font-size: clamp(2.8rem, 6vw, 4.4rem); color: #fff; }
.auth-visual p {
  max-width: 22rem;
  color: rgba(232, 244, 238, 0.72);
  font-size: 1.05rem;
  line-height: 1.45;
  margin: 18px 0 0;
}
.auth-wave {
  width: min(420px, 100%);
  height: auto;
  opacity: 0.92;
  margin-top: auto;
}
.auth-panel {
  background: var(--bg);
  color: var(--ink);
  display: flex;
  flex-direction: column;
  justify-content: center;
  padding: 36px 28px calc(36px + var(--safe-bottom));
}
.auth-panel-inner { width: min(420px, 100%); margin: 0 auto; }
.auth-panel h1 {
  font-family: var(--display);
  font-size: clamp(1.8rem, 4vw, 2.3rem);
  letter-spacing: -0.03em;
  margin: 0 0 8px;
}
.auth-panel .sub { margin-bottom: 22px; }
.auth-panel form button { width: 100%; margin-top: 16px; min-height: 52px; }
.auth-back {
  display: inline-block;
  margin-bottom: 22px;
  color: var(--muted);
  text-decoration: none;
  font-weight: 600;
  font-size: 0.95rem;
}
.auth-back:hover { color: var(--brand); }

/* ——— Landing ——— */
.landing { background: var(--bg-deep); color: #eef6f1; }
.landing-hero {
  min-height: 100dvh;
  min-height: 100svh;
  position: relative;
  overflow: hidden;
  display: grid;
  align-items: center;
  padding: calc(28px + var(--safe-top)) 28px calc(36px + var(--safe-bottom));
  background:
    radial-gradient(1100px 700px at 75% 15%, rgba(31, 170, 114, 0.28), transparent 58%),
    radial-gradient(900px 600px at 10% 90%, rgba(120, 180, 140, 0.14), transparent 50%),
    linear-gradient(165deg, #0a1511 0%, #123226 42%, #0c1a14 100%);
}
.landing-hero::before {
  content: "";
  position: absolute;
  inset: 0;
  background:
    linear-gradient(90deg, rgba(8, 18, 14, 0.72) 0%, rgba(8, 18, 14, 0.35) 42%, transparent 70%),
    url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1600' height='1000' viewBox='0 0 1600 1000' fill='none'%3E%3Cpath d='M80 620c120-180 240-180 360 0s240 180 360 0 240-180 360 0 240 180 360 0' stroke='%233dcf9a' stroke-opacity='.28' stroke-width='18' stroke-linecap='round'/%3E%3Cpath d='M80 700c120-140 240-140 360 0s240 140 360 0 240-140 360 0 240 140 360 0' stroke='%23a8e6c8' stroke-opacity='.16' stroke-width='12' stroke-linecap='round'/%3E%3Ccircle cx='1180' cy='320' r='210' fill='%231faa72' fill-opacity='.14'/%3E%3Ccircle cx='1260' cy='280' r='92' fill='%23e8f4ee' fill-opacity='.09'/%3E%3Crect x='980' y='420' width='280' height='480' rx='48' fill='%23e8f4ee' fill-opacity='.09' stroke='%23a8e6c8' stroke-opacity='.32' stroke-width='3'/%3E%3Crect x='1018' y='470' width='204' height='300' rx='22' fill='%230d1c16' fill-opacity='.55'/%3E%3Cpath d='M1060 620h120M1060 660h88M1060 700h104' stroke='%233dcf9a' stroke-opacity='.65' stroke-width='10' stroke-linecap='round'/%3E%3C/svg%3E")
      right 4% center / min(62vw, 760px) auto no-repeat;
  pointer-events: none;
}
.landing-hero-copy {
  position: relative;
  z-index: 1;
  width: min(560px, 100%);
  animation: rise 0.85s ease-out;
}
.landing-hero .brand-mark {
  font-size: clamp(3.6rem, 12vw, 6.6rem);
  color: #fff;
  margin-bottom: 18px;
}
.landing-hero h2 {
  font-family: var(--display);
  font-weight: 700;
  font-size: clamp(1.45rem, 3.4vw, 2.15rem);
  letter-spacing: -0.03em;
  line-height: 1.15;
  margin: 0 0 14px;
  color: #f4faf7;
  max-width: 14ch;
}
.landing-hero .lead {
  margin: 0 0 28px;
  color: rgba(232, 244, 238, 0.78);
  font-size: clamp(1rem, 2.2vw, 1.15rem);
  line-height: 1.45;
  max-width: 28ch;
}
.cta-row { display: flex; flex-wrap: wrap; gap: 12px; }
.cta-row a { text-decoration: none; }
.cta-row .btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 52px;
  padding: 14px 22px;
  border-radius: 14px;
  font-weight: 700;
  border: none;
  cursor: pointer;
}
.cta-row .btn-primary { background: #1faa72; color: #062417; }
.cta-row .btn-ghost {
  background: transparent;
  color: #e8f4ee;
  border: 1px solid rgba(232, 244, 238, 0.28);
}
.landing-section {
  padding: clamp(56px, 10vh, 96px) 28px;
  background: var(--bg);
  color: var(--ink);
}
.landing-section .inner { width: min(920px, 100%); margin: 0 auto; }
.landing-section h3 {
  font-family: var(--display);
  font-size: clamp(1.7rem, 4vw, 2.4rem);
  letter-spacing: -0.03em;
  margin: 0 0 12px;
  max-width: 16ch;
}
.landing-section p {
  margin: 0;
  color: var(--muted);
  font-size: 1.08rem;
  line-height: 1.5;
  max-width: 36ch;
}
.landing-section + .landing-section { border-top: 1px solid var(--line); }
.landing-section.alt {
  background:
    linear-gradient(180deg, #e7f2eb 0%, #eef4f0 100%);
}
.landing-foot {
  background: var(--bg-deep);
  color: rgba(232, 244, 238, 0.55);
  padding: 28px;
  text-align: center;
  font-size: 0.9rem;
}
.landing-foot a { color: #9fd9be; }

@keyframes rise {
  from { opacity: 0; transform: translateY(18px); }
  to { opacity: 1; transform: translateY(0); }
}
@keyframes softPulse {
  0%, 100% { opacity: 0.85; transform: scale(1); }
  50% { opacity: 1; transform: scale(1.02); }
}
.landing-hero::after {
  content: "";
  position: absolute;
  right: 12%;
  top: 22%;
  width: min(28vw, 220px);
  height: min(28vw, 220px);
  border-radius: 50%;
  background: radial-gradient(circle, rgba(61, 207, 154, 0.35), transparent 70%);
  animation: softPulse 4.5s ease-in-out infinite;
  pointer-events: none;
}

.plan-card {
  border: 1px solid var(--line);
  border-radius: 16px;
  padding: 18px 16px;
  background: #fafdfb;
}
.plan-card h3 { margin: 0 0 4px; font-size: 1.35rem; font-family: var(--display); }
.plan-card .price { font-size: 1.1rem; font-weight: 700; color: var(--brand); margin: 0 0 12px; }
.plan-card ul { margin: 0 0 14px; padding-left: 1.1rem; color: var(--muted); }
.plan-card li { margin: 6px 0; }
.plan-current { margin: 0 0 4px; font-size: 1.2rem; font-weight: 750; }
.qr-stage {
  display: flex; flex-direction: column; align-items: center; gap: 16px;
  padding: 28px 16px; text-align: center;
}
.billing-portal {
  min-height: 100dvh;
  background:
    radial-gradient(900px 420px at 0% 0%, #d9f2e6 0%, transparent 55%),
    var(--bg);
}
.billing-top {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  width: min(860px, 100%);
  margin: 0 auto;
  padding: calc(18px + var(--safe-top)) 18px 12px;
}
.billing-top .logo {
  color: var(--ink);
  font-family: var(--display);
  font-size: 1.35rem;
  font-weight: 800;
  letter-spacing: -0.04em;
  text-decoration: none;
}
.billing-top .context {
  color: var(--muted);
  font-size: .9rem;
  font-weight: 700;
}
.billing-main {
  width: min(860px, 100%);
  margin: 0 auto;
  padding: 28px 18px calc(44px + var(--safe-bottom));
}
.billing-heading {
  display: grid;
  grid-template-columns: auto 1fr;
  align-items: center;
  gap: 16px;
  margin-bottom: 22px;
}
.billing-avatar {
  width: 76px;
  height: 76px;
  border-radius: 50%;
  object-fit: cover;
  background: var(--brand-soft);
  color: var(--brand);
  display: grid;
  place-items: center;
  font-family: var(--display);
  font-size: 2rem;
  font-weight: 800;
}
.billing-heading h1 {
  font-family: var(--display);
  font-size: clamp(1.8rem, 4vw, 2.5rem);
  letter-spacing: -0.04em;
  margin: 0;
}
.billing-heading p {
  color: var(--muted);
  margin: 5px 0 0;
  overflow-wrap: anywhere;
}
.billing-family {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
  padding: 16px 18px;
  background: var(--card);
  border: 1px solid var(--line);
  border-radius: var(--radius);
}
.billing-family strong { display: block; font-size: 1.05rem; }
.billing-family span { color: var(--muted); font-size: .9rem; }
.billing-actions { display: grid; gap: 10px; }
.billing-action {
  display: flex;
  align-items: center;
  gap: 14px;
  width: 100%;
  min-height: 68px;
  padding: 13px 16px;
  margin: 0;
  text-align: left;
  background: var(--card);
  color: var(--ink);
  border: 1px solid var(--line);
  border-radius: var(--radius);
  transition: transform 180ms ease, border-color 180ms ease, background 180ms ease;
}
.billing-action:hover {
  transform: translateY(-2px);
  border-color: var(--brand);
  background: #fbfefc;
}
.billing-action:active { transform: scale(.985); }
.billing-action .action-icon {
  display: grid;
  place-items: center;
  flex: 0 0 40px;
  width: 40px;
  height: 40px;
  border-radius: 13px;
  background: var(--brand-soft);
  color: var(--brand);
  font-size: 1.35rem;
}
.billing-action .action-copy { flex: 1; }
.billing-action strong { display: block; font-size: 1rem; }
.billing-action small { display: block; color: var(--muted); margin-top: 2px; }
.billing-action .chevron { color: var(--muted); font-size: 1.3rem; }
.billing-stripe {
  margin-top: 22px;
  text-align: center;
}
.billing-stripe form { display: inline-block; }
.billing-stripe button {
  width: auto;
  min-height: 44px;
  padding: 10px 14px;
  font-size: .9rem;
}
.billing-note {
  margin: 18px 0 0;
  color: var(--muted);
  text-align: center;
  font-size: .9rem;
}
.billing-alert {
  margin: 0 0 16px;
  padding: 12px 14px;
  border-radius: 13px;
  background: var(--brand-soft);
  color: var(--brand-dark);
  font-weight: 700;
}
.billing-alert.error { background: #fbe9e7; color: var(--danger); }
dialog.billing-dialog {
  width: min(560px, calc(100% - 28px));
  max-height: min(760px, calc(100dvh - 28px));
  padding: 0;
  border: 1px solid var(--line);
  border-radius: 22px;
  background: var(--card);
  color: var(--ink);
  box-shadow: 0 24px 80px rgba(18, 38, 28, .22);
  animation: dialogIn 220ms ease-out both;
}
dialog.billing-dialog::backdrop {
  background: rgba(7, 20, 14, .48);
  backdrop-filter: blur(3px);
}
.dialog-inner { padding: 22px; }
.dialog-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 14px;
  margin-bottom: 12px;
}
.dialog-head h2 {
  margin: 0;
  font-family: var(--display);
  font-size: 1.45rem;
  letter-spacing: -0.03em;
}
.dialog-close {
  width: 42px;
  min-height: 42px;
  padding: 0;
  margin: 0;
  background: var(--brand-soft);
  color: var(--brand);
  font-size: 1.35rem;
}
.dialog-actions { display: flex; gap: 10px; margin-top: 18px; }
.dialog-actions button { flex: 1; margin: 0; }
.plan-options { display: grid; gap: 10px; }
.plan-option {
  display: block;
  padding: 16px;
  margin: 0;
  border: 1px solid var(--line);
  border-radius: 16px;
  cursor: pointer;
  transition: border-color 180ms ease, background 180ms ease, transform 180ms ease;
}
.plan-option:hover { border-color: var(--brand); transform: translateY(-1px); }
.plan-option.current { border-color: var(--brand); background: var(--brand-soft); }
.plan-option strong { display: block; font-size: 1.15rem; }
.plan-option .price { color: var(--brand); font-weight: 800; margin: 4px 0; }
.plan-option .features { color: var(--muted); font-size: .9rem; }
.invoice-list { display: grid; gap: 8px; }
.invoice-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--line);
}
.invoice-row:last-child { border-bottom: 0; }
.invoice-row strong { display: block; }
.invoice-row small { color: var(--muted); }
.invoice-row a {
  flex: 0 0 auto;
  padding: 9px 12px;
  border-radius: 11px;
  background: var(--brand-soft);
  color: var(--brand);
  font-size: .85rem;
  font-weight: 800;
  text-decoration: none;
}
@keyframes dialogIn {
  from { opacity: 0; transform: translateY(12px) scale(.98); }
  to { opacity: 1; transform: translateY(0) scale(1); }
}

@media (max-width: 860px) {
  .auth-screen { grid-template-columns: 1fr; }
  .auth-visual { min-height: 34vh; padding: calc(28px + var(--safe-top)) 24px 28px; }
  .auth-wave { width: min(280px, 70%); }
  .landing-hero {
    align-items: end;
    padding: calc(24px + var(--safe-top)) 22px calc(32px + var(--safe-bottom));
  }
  .landing-hero::before {
    background:
      linear-gradient(180deg, rgba(8, 18, 14, 0.15) 0%, rgba(8, 18, 14, 0.55) 48%, rgba(8, 18, 14, 0.92) 100%),
      url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='1600' height='1000' viewBox='0 0 1600 1000' fill='none'%3E%3Cpath d='M80 520c120-180 240-180 360 0s240 180 360 0 240-180 360 0 240 180 360 0' stroke='%233dcf9a' stroke-opacity='.3' stroke-width='18' stroke-linecap='round'/%3E%3Cpath d='M80 600c120-140 240-140 360 0s240 140 360 0 240-140 360 0 240 140 360 0' stroke='%23a8e6c8' stroke-opacity='.18' stroke-width='12' stroke-linecap='round'/%3E%3Crect x='980' y='180' width='280' height='480' rx='48' fill='%23e8f4ee' fill-opacity='.1' stroke='%23a8e6c8' stroke-opacity='.3' stroke-width='3'/%3E%3Crect x='1018' y='230' width='204' height='300' rx='22' fill='%230d1c16' fill-opacity='.5'/%3E%3Cpath d='M1060 380h120M1060 420h88M1060 460h104' stroke='%233dcf9a' stroke-opacity='.65' stroke-width='10' stroke-linecap='round'/%3E%3C/svg%3E")
        center 16% / min(96vw, 460px) auto no-repeat;
  }
  .landing-hero::after { top: 12%; right: 8%; }
}
@media (max-width: 520px) {
  .page-body { padding: 22px 14px calc(32px + var(--safe-bottom)); }
  button, input, select { min-height: 52px; }
  .cta-row .btn { width: 100%; }
  .billing-main { padding: 22px 14px calc(32px + var(--safe-bottom)); }
  .billing-heading { grid-template-columns: 64px 1fr; gap: 12px; }
  .billing-avatar { width: 64px; height: 64px; font-size: 1.65rem; }
  .billing-family { align-items: flex-start; flex-direction: column; gap: 5px; }
  .dialog-inner { padding: 18px; }
  .dialog-actions { flex-direction: column; }
  .invoice-row { align-items: flex-start; flex-direction: column; }
}
`;

const waveSvg = `<svg class="auth-wave" viewBox="0 0 420 120" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <path d="M10 70c40-48 80-48 120 0s80 48 120 0 80-48 120 0 80 48 120 0" stroke="#3dcf9a" stroke-width="10" stroke-linecap="round" opacity=".85"/>
  <path d="M10 88c40-32 80-32 120 0s80 32 120 0 80-32 120 0 80 32 120 0" stroke="#a8e6c8" stroke-width="6" stroke-linecap="round" opacity=".45"/>
</svg>`;

type LayoutOpts = {
  vision?: boolean;
  variant?: "page" | "auth" | "landing" | "bare";
  userName?: string | null;
};

export function layout(title: string, body: string, visionOrOpts: boolean | LayoutOpts = false): string {
  const opts: LayoutOpts =
    typeof visionOrOpts === "boolean" ? { vision: visionOrOpts } : visionOrOpts;
  const vision = !!opts.vision;
  const variant = opts.variant ?? "page";
  const visionCss = vision
    ? `body{font-size:1.2rem} .brand-mark{font-size:3.2rem!important} button,input,select{min-height:60px;font-size:1.15rem;font-weight:800;border-width:2px}
       :root{--ink:#000;--bg:#fff;--brand:#004d33;--line:#000;--muted:#222}`
    : "";
  const safeTitle = escape(title);
  const bodyClass =
    variant === "landing" ? "landing" : variant === "auth" ? "auth" : variant === "bare" ? "bare" : "site";

  return `<!doctype html>
<html lang="hu">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover" />
  <meta name="theme-color" content="#0d1c16" />
  <meta name="referrer" content="no-referrer" />
  <meta http-equiv="Content-Security-Policy" content="default-src 'self'; script-src 'self' 'unsafe-inline' https://cdn.jsdelivr.net; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com data:; connect-src 'self' https: wss:; media-src 'self' blob:; img-src 'self' data: blob:; frame-ancestors 'none'; base-uri 'self'; form-action 'self'" />
  <title>${safeTitle} · MyÜzi</title>
  <style>${css}${visionCss}</style>
</head>
<body class="${bodyClass}">
  ${body}
</body>
</html>`;
}

function pageChrome(body: string, opts?: { userName?: string | null }): string {
  const nav = opts?.userName
    ? `<nav class="page-nav">
        <a href="/app"><button class="secondary" type="button">Beszélgetések</button></a>
        <a href="/account"><button class="ghost" type="button">Fiók</button></a>
      </nav>`
    : `<nav class="page-nav">
        <a href="/login"><button type="button">Belépés</button></a>
      </nav>`;
  return `
  <div class="page">
    <header class="page-top">
      <a class="logo" href="/">MyÜzi</a>
      ${nav}
    </header>
    <main class="page-body">${body}</main>
    <p class="page-foot">MyÜzi · myuzi.uvmr.app</p>
  </div>`;
}

function authChrome(title: string, sub: string, formHtml: string): string {
  return `
  <div class="auth-screen">
    <aside class="auth-visual">
      <div>
        <p class="brand-mark">MyÜzi</p>
        <p>Hangüzenetek és hívások a családnak — appban és böngészőben.</p>
      </div>
      ${waveSvg}
    </aside>
    <section class="auth-panel">
      <div class="auth-panel-inner">
        <a class="auth-back" href="/">← Kezdőlap</a>
        <h1>${escape(title)}</h1>
        <p class="sub">${sub}</p>
        ${formHtml}
      </div>
    </section>
  </div>`;
}

export function landingPage(opts?: { loggedIn?: boolean; userName?: string }): string {
  const loggedIn = !!opts?.loggedIn;
  const name = opts?.userName?.trim();
  const primary = loggedIn
    ? `<a href="/app"><span class="btn btn-primary">Beszélgetések</span></a>
       <a href="/account"><span class="btn btn-ghost">Fiók${name ? ` · ${escape(name)}` : ""}</span></a>`
    : `<a href="/login"><span class="btn btn-primary">Belépés</span></a>
       <a href="/app"><span class="btn btn-ghost">Webes beszélgetések</span></a>`;

  return layout(
    "Kezdőlap",
    `
    <section class="landing-hero">
      <div class="landing-hero-copy">
        <p class="brand-mark">MyÜzi</p>
        <h2>A család hangja egy helyen.</h2>
        <p class="lead">Hangüzenetek és élő hívások — telefonon, és a teljes képernyős weben.</p>
        <div class="cta-row">${primary}</div>
      </div>
    </section>
    <section class="landing-section">
      <div class="inner">
        <h3>Hangüzenet, ami megmarad</h3>
        <p>Küldj és hallgass üzeneteket a családdal — akkor is, ha épp nem tudtok beszélni.</p>
      </div>
    </section>
    <section class="landing-section alt">
      <div class="inner">
        <h3>Hang- és videóhívás</h3>
        <p>Egy gombnyomással csatlakozhatsz — a böngészőben is, teljes kijelzőn.</p>
      </div>
    </section>
    <section class="landing-section">
      <div class="inner">
        <h3>Egy család, egy hely</h3>
        <p>Tagok, meghívók és csomagok a fiókkezelőben. Egyszerűen, zölden, a MyÜzi módjára.</p>
      </div>
    </section>
    <footer class="landing-foot">
      MyÜzi · <a href="/login">Belépés</a> · <a href="/account">Fiók</a>
    </footer>
  `,
    { variant: "landing" },
  );
}

export function loginPage(error = ""): string {
  return layout(
    "Belépés",
    authChrome(
      "Belépés",
      "Add meg az emailed — küldünk egy 6 jegyű kódot.",
      `<form method="POST" action="/login">
        <label for="email">Email</label>
        <input id="email" name="email" type="email" required autocomplete="email" autofocus />
        <label class="switch">
          <input type="checkbox" name="visionAssist" value="1" />
          Látássérült segítség
        </label>
        <button type="submit">Kód küldése</button>
        ${error ? `<p class="error">${escape(error)}</p>` : ""}
      </form>`,
    ),
    { variant: "auth" },
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
  const title = askName ? "Becenév" : familyName ? "Meghívó" : "Kód";
  const sub = askName
    ? "A kód rendben. Add meg a beceneved."
    : familyName
      ? `Meghívó: <strong>${escape(familyName)}</strong><br/>Kódot küldtünk ide: <strong>${escape(email)}</strong>`
      : `Kód: <strong>${escape(email)}</strong>`;

  const resendBlock = askName
    ? ""
    : `
      <form method="POST" action="/login" id="resendForm" style="margin-top:14px">
        <input type="hidden" name="email" value="${escape(email)}" />
        <button type="submit" class="ghost" id="resendBtn" disabled>Új kód 30 mp múlva</button>
      </form>
      <script>
      (function(){
        var btn = document.getElementById('resendBtn');
        if (!btn) return;
        var left = 30;
        var t = setInterval(function(){
          left -= 1;
          if (left <= 0) {
            clearInterval(t);
            btn.disabled = false;
            btn.textContent = 'Új kód küldése';
          } else {
            btn.textContent = 'Új kód ' + left + ' mp múlva';
          }
        }, 1000);
      })();
      </script>`;

  const form = `
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
        ${error ? `<p class="error">${escape(error)}</p>` : ""}
      </form>
      ${resendBlock}`;

  return layout(title, authChrome(title, sub, form), { variant: "auth" });
}

/** Invite link without a locked email — ask for email, then we send the PIN. */
export function inviteEmailPage(familyName: string, token: string, error = ""): string {
  return layout(
    "Meghívó",
    authChrome(
      "Meghívó",
      `Meghívót kaptál a(z) <strong>${escape(familyName)}</strong> családba.`,
      `${error ? `<p class="error">${escape(error)}</p>` : ""}
      <form method="POST" action="/invite/${escape(token)}/start">
        <label for="email">Email címed</label>
        <input id="email" name="email" type="email" required autocomplete="email" autofocus />
        <button type="submit">Kód küldése</button>
      </form>`,
    ),
    { variant: "auth" },
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
  const isPaid = family?.plan === "family" || family?.plan === "family_plus";
  const isCanceling = family?.stripe_status === "canceling";
  const pendingPlan = family?.stripe_status?.startsWith("pending:")
    ? family.stripe_status.slice("pending:".length)
    : null;
  const pendingLabel =
    pendingPlan === "family_plus" ? "Family+" : pendingPlan === "family" ? "Family" : null;
  const planCta = isPaid ? "Csomagmódosítás" : "Előfizetés";
  const planStatusHint = isCanceling
    ? "Lemondva — a jelenlegi hónap végéig még érvényes."
    : pendingLabel
      ? `Váltás ${pendingLabel} csomagra a hónap végén.`
      : "";

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
                      ? `<form method="POST" action="/account/members/remove" style="margin:0" onsubmit="return confirm('Eltávolítod ezt a tagot a családból?')">
                          <input type="hidden" name="userId" value="${escape(m.id)}" />
                          <button class="ghost" type="submit" style="margin:0;padding:8px 12px;width:auto;min-height:auto">Eltávolít</button>
                        </form>`
                      : canLeave
                        ? `<form method="POST" action="/account/members/remove" style="margin:0" onsubmit="return confirm('Kilépsz a családból?')">
                          <input type="hidden" name="userId" value="${escape(m.id)}" />
                          <button class="ghost" type="submit" style="margin:0;padding:8px 12px;width:auto;min-height:auto">Kilépek</button>
                        </form>`
                        : ""
                  }
                </span>
              </li>`;
            })
            .join("")}
        </ul>
        <form method="POST" action="/account/invite" style="margin-top:16px">
          <label for="inv">Meghívó email (kötelező)</label>
          <input id="inv" name="email" type="email" required placeholder="családtag@email.hu" />
          <button type="submit">Meghívó</button>
        </form>
        ${inviteUrl ? `<p class="ok"><a href="${escape(inviteUrl)}">${escape(inviteUrl)}</a></p>` : ""}
      </div>
      ${
        isOwner
          ? `<div class="panel">
        <p class="plan-current">Jelenlegi csomagod: ${currentPlan}</p>
        <p class="hint">${planLimits}</p>
        ${planStatusHint ? `<p class="ok">${planStatusHint}</p>` : ""}
        <form method="GET" action="/account/plans" style="margin-top:14px">
          <button type="submit">${planCta}</button>
        </form>
        ${
          isPaid && !isCanceling
            ? `<form method="POST" action="/account/cancel-subscription" onsubmit="return confirm('Lemondod az előfizetést? A hónap végéig még használhatod.')">
                <button class="ghost" type="submit">Előfizetés lemondása</button>
              </form>`
            : ""
        }
        ${
          isCanceling
            ? `<form method="POST" action="/account/resume-subscription">
                <button type="submit">Lemondás visszavonása</button>
              </form>`
            : ""
        }
        ${
          isPaid
            ? `<form method="POST" action="/account/portal"><button class="ghost" type="submit">Stripe portál</button></form>`
            : ""
        }
      </div>`
          : ""
      }`;

  return layout(
    "Fiók",
    pageChrome(
      `
    <h1 class="brand-mark">Fiók</h1>
    <p class="sub">${escape(user.name)}</p>
    ${message ? `<p class="ok">${escape(message)}</p>` : ""}
    ${error ? `<p class="error">${escape(error)}</p>` : ""}
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
      { userName: user.name },
    ),
    { vision: !!user.vision_assist, variant: "page" },
  );
}

export function plansPage(opts: {
  user: UserRow;
  currentPlan: string;
}): string {
  const { user, currentPlan } = opts;
  const familyActive = currentPlan === "family";
  const plusActive = currentPlan === "family_plus";
  const isPaid = familyActive || plusActive;
  const pageTitle = isPaid ? "Csomagmódosítás" : "Előfizetés";

  const familyBtn = familyActive
    ? "Jelenlegi csomag"
    : plusActive
      ? "Váltás hónap végén"
      : "Ezt választom";
  const plusBtn = plusActive
    ? "Jelenlegi csomag"
    : familyActive
      ? "Váltás most"
      : "Ezt választom";

  return layout(
    pageTitle,
    pageChrome(
      `
    <h1 class="brand-mark">${pageTitle}</h1>
    <p class="sub">${isPaid ? "Csomag módosítása" : "Válassz csomagot"}</p>
    <p class="hint">Upgrade azonnal érvényes. Downgrade a hónap végén lép életbe.</p>
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
          <button type="submit"${familyActive ? " class=\"secondary\" disabled" : ""}>${familyBtn}</button>
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
          <button type="submit"${plusActive ? " class=\"secondary\" disabled" : ""}>${plusBtn}</button>
        </form>
      </div>
      ${
        isPaid
          ? `<form method="POST" action="/account/cancel-subscription" onsubmit="return confirm('Lemondod az előfizetést? A hónap végéig még használhatod.')">
              <button class="ghost" type="submit">Előfizetés lemondása</button>
            </form>`
          : ""
      }
      <form method="GET" action="/account">
        <button class="ghost" type="submit">Vissza</button>
      </form>
    </div>
  `,
      { userName: user.name },
    ),
    { vision: !!user.vision_assist, variant: "page" },
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
  currentPlan?: string;
  error?: string;
}): string {
  const { user, plan, billing, currentPlan, error } = opts;
  const isCompany = billing?.billing_type === "company";
  const planName = plan === "family_plus" ? "Family+" : "Family";
  const price = plan === "family_plus" ? "4990" : "1990";
  const savedName = billing?.billing_name ?? "";
  const savedTax = billing?.billing_tax_id ?? "";
  const savedAddr = billing?.billing_address_line1 ?? "";
  const savedCity = billing?.billing_city ?? "";
  const savedPostal = billing?.billing_postal_code ?? "";
  const isChange =
    currentPlan === "family" || currentPlan === "family_plus";
  const isDowngrade =
    currentPlan === "family_plus" && plan === "family";
  const submitLabel = !isChange
    ? "Fizetés"
    : isDowngrade
      ? "Váltás hónap végén"
      : "Váltás most";

  return layout(
    isChange ? "Csomagváltás" : "Számlázás",
    pageChrome(
      `
    <h1 class="brand-mark">${isChange ? "Csomagváltás" : "Számlázás"}</h1>
    <p class="sub">${planName} · ${price} Ft/hó</p>
    ${
      isDowngrade
        ? `<p class="ok">A kisebb csomag a jelenlegi hónap végén lép életbe.</p>`
        : ""
    }
    ${error ? `<p class="error">${escape(error)}</p>` : ""}
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
        <button type="submit">${submitLabel}</button>
      </form>
      <form method="GET" action="/account/plans" style="margin-top:8px">
        <button class="ghost" type="submit">Vissza</button>
      </form>
    </div>
  `,
      { userName: user.name },
    ),
    { vision: !!user.vision_assist, variant: "page" },
  );
}

export function subscriptionPortalPage(opts: {
  user: UserRow;
  family: {
    id: string;
    name: string;
    plan: string;
    owner_id: string;
    stripe_status: string | null;
    stripe_customer_id: string | null;
  } | null;
  billing: {
    billing_type?: string | null;
    billing_name?: string | null;
    billing_tax_id?: string | null;
    billing_address_line1?: string | null;
    billing_city?: string | null;
    billing_postal_code?: string | null;
    billing_country?: string | null;
  } | null;
  invoices: InvoiceSummary[];
  isOwner: boolean;
  message?: string;
  error?: string;
}): string {
  const { user, family, billing, invoices, isOwner, message, error } = opts;
  const avatarUrl = user.avatar_key
    ? `/api/users/${encodeURIComponent(user.id)}/avatar`
    : "";
  const initial = escape(user.name.trim().charAt(0).toUpperCase() || "?");
  const planLabel =
    family?.plan === "family_plus"
      ? "Család+"
      : family?.plan === "family"
        ? "Család"
        : "Ingyenes";
  const planSummary =
    family?.plan === "family_plus"
      ? "25 tag · 20 perc hangüzenet · hang- és videóhívás"
      : family?.plan === "family"
        ? "6 tag · 10 perc hangüzenet · hang- és videóhívás"
        : "3 tag · 2 perc hangüzenet";
  const isCompany = billing?.billing_type === "company";
  const billingName = billing?.billing_name ?? "";
  const taxId = billing?.billing_tax_id ?? "";
  const address = billing?.billing_address_line1 ?? "";
  const city = billing?.billing_city ?? "";
  const postalCode = billing?.billing_postal_code ?? "";
  const country = billing?.billing_country ?? "HU";
  const billingComplete =
    billingName.trim().length >= 2 &&
    address.trim().length > 0 &&
    city.trim().length > 0 &&
    postalCode.trim().length > 0 &&
    (!isCompany || taxId.trim().length >= 5);
  const hiddenBilling = `
    <input type="hidden" name="billingType" value="${isCompany ? "company" : "individual"}" />
    <input type="hidden" name="billingName" value="${escape(billingName)}" />
    <input type="hidden" name="taxId" value="${escape(taxId)}" />
    <input type="hidden" name="addressLine1" value="${escape(address)}" />
    <input type="hidden" name="city" value="${escape(city)}" />
    <input type="hidden" name="postalCode" value="${escape(postalCode)}" />
    <input type="hidden" name="country" value="${escape(country)}" />`;
  const invoiceRows = invoices.length
    ? invoices
        .map((invoice) => {
          const date = new Date(invoice.created * 1000).toLocaleDateString("hu-HU");
          const zeroDecimal = new Set([
            "bif", "clp", "djf", "gnf", "huf", "jpy", "kmf", "krw",
            "mga", "pyg", "rwf", "ugx", "vnd", "vuv", "xaf", "xof", "xpf",
          ]);
          const amountValue = zeroDecimal.has(invoice.currency.toLowerCase())
            ? invoice.amountPaid
            : invoice.amountPaid / 100;
          const amount = `${amountValue.toLocaleString("hu-HU")} ${invoice.currency.toUpperCase()}`;
          const number = invoice.number || invoice.id;
          return `<div class="invoice-row">
            <span><strong>${escape(number)}</strong><small>${escape(date)} · ${escape(invoice.status || "számla")} · ${escape(amount)}</small></span>
            <a href="/api/billing/invoices/${encodeURIComponent(invoice.id)}/download">PDF</a>
          </div>`;
        })
        .join("")
    : `<p class="hint">Még nincs letölthető számlád.</p>`;
  const accountMessage = message
    ? `<p class="billing-alert">${escape(message)}</p>`
    : "";
  const accountError = error
    ? `<p class="billing-alert error">${escape(error)}</p>`
    : "";

  return layout(
    "Csomag módosítása",
    `
    <div class="billing-portal">
      <header class="billing-top">
        <a class="logo" href="/">MyÜzi</a>
        <span class="context">Fiókkezelés</span>
      </header>
      <main class="billing-main">
        ${accountMessage}
        ${accountError}
        <section class="billing-heading">
          ${
            avatarUrl
              ? `<img class="billing-avatar" src="${escape(avatarUrl)}" alt="${escape(user.name)}" />`
              : `<span class="billing-avatar" aria-hidden="true">${initial}</span>`
          }
          <div>
            <h1>Csomag módosítása</h1>
            <p><strong>${escape(user.name)}</strong><br/>${escape(user.email)}</p>
          </div>
        </section>
        ${
          family
            ? `<section class="billing-family">
                <div><strong>${escape(family.name)}</strong><span>Család</span></div>
                <div><strong>${escape(planLabel)}</strong><span>${escape(planSummary)}</span></div>
              </section>`
            : `<section class="billing-family"><div><strong>Nincs család</strong><span>Előbb hozz létre vagy fogadj el egy családi meghívót.</span></div></section>`
        }
        <section class="billing-actions" aria-label="Fiókkezelési lehetőségek">
          <button class="billing-action" type="button" data-dialog="plansDialog" ${family && isOwner ? "" : "disabled"}>
            <span class="action-icon">↕</span>
            <span class="action-copy"><strong>Csomag módosítása</strong><small>${isOwner ? "Válassz a Család és Család+ csomagok közül" : "Csak a család tulajdonosa módosíthatja"}</small></span>
            <span class="chevron">›</span>
          </button>
          <button class="billing-action" type="button" data-dialog="detailsDialog" ${family && isOwner ? "" : "disabled"}>
            <span class="action-icon">⌂</span>
            <span class="action-copy"><strong>Számlázási adatok</strong><small>${billingComplete ? "Mentett adatok módosítása" : "Add meg a számlázási adataidat"}</small></span>
            <span class="chevron">›</span>
          </button>
          <button class="billing-action" type="button" data-dialog="invoicesDialog" ${family && isOwner ? "" : "disabled"}>
            <span class="action-icon">↓</span>
            <span class="action-copy"><strong>Számlák letöltése</strong><small>${invoices.length ? `${invoices.length} számla elérhető` : "Korábbi számlák PDF-ben"}</small></span>
            <span class="chevron">›</span>
          </button>
        </section>
        ${
          family && isOwner && !!family.stripe_customer_id
            ? `<div class="billing-stripe">
                <form method="POST" action="/account/portal">
                  <button class="ghost" type="submit">Stripe portál megnyitása</button>
                </form>
              </div>`
            : ""
        }
        <p class="billing-note">A MyÜzi portálon a legfontosabb beállításokat egyszerűen kezelheted.</p>
      </main>

      <dialog class="billing-dialog" id="detailsDialog">
        <div class="dialog-inner">
          <div class="dialog-head">
            <h2>Számlázási adatok</h2>
            <button class="dialog-close" type="button" data-close="detailsDialog" aria-label="Bezárás">×</button>
          </div>
          <form method="POST" action="/account/subscription/billing">
            <label for="portalBillingType">Számlázás</label>
            <select id="portalBillingType" name="billingType">
              <option value="individual" ${!isCompany ? "selected" : ""}>Magánszemély</option>
              <option value="company" ${isCompany ? "selected" : ""}>Cég</option>
            </select>
            <label for="portalBillingName">Számlázási név</label>
            <input id="portalBillingName" name="billingName" required minlength="2" value="${escape(billingName)}" />
            <div id="portalCompanyFields" style="display:${isCompany ? "block" : "none"}">
              <label for="portalTaxId">Adószám</label>
              <input id="portalTaxId" name="taxId" value="${escape(taxId)}" />
            </div>
            <label for="portalAddress">Cím</label>
            <input id="portalAddress" name="addressLine1" required value="${escape(address)}" />
            <div class="row">
              <div>
                <label for="portalPostalCode">Irányítószám</label>
                <input id="portalPostalCode" name="postalCode" required value="${escape(postalCode)}" />
              </div>
              <div>
                <label for="portalCity">Város</label>
                <input id="portalCity" name="city" required value="${escape(city)}" />
              </div>
            </div>
            <input type="hidden" name="country" value="${escape(country)}" />
            <div class="dialog-actions">
              <button class="ghost" type="button" data-close="detailsDialog">Mégse</button>
              <button type="submit">Mentés</button>
            </div>
          </form>
        </div>
      </dialog>

      <dialog class="billing-dialog" id="plansDialog">
        <div class="dialog-inner">
          <div class="dialog-head">
            <h2>Csomag módosítása</h2>
            <button class="dialog-close" type="button" data-close="plansDialog" aria-label="Bezárás">×</button>
          </div>
          ${
            billingComplete
              ? ""
              : `<p class="billing-alert">A csomagváltás előtt töltsd ki a számlázási adatokat.</p>`
          }
          <div class="plan-options">
            <form method="POST" action="/account/checkout">
              <input type="hidden" name="plan" value="family" />
              ${hiddenBilling}
              <button class="plan-option ${family?.plan === "family" ? "current" : ""}" type="submit" ${billingComplete ? "" : "disabled"}>
                <strong>Család</strong>
                <div class="price">1 990 Ft / hó</div>
                <div class="features">6 tag · 10 perc hangüzenet · hívások és csoportok</div>
              </button>
            </form>
            <form method="POST" action="/account/checkout">
              <input type="hidden" name="plan" value="family_plus" />
              ${hiddenBilling}
              <button class="plan-option ${family?.plan === "family_plus" ? "current" : ""}" type="submit" ${billingComplete ? "" : "disabled"}>
                <strong>Család+</strong>
                <div class="price">4 990 Ft / hó</div>
                <div class="features">25 tag · 20 perc hangüzenet · hívások és csoportok</div>
              </button>
            </form>
          </div>
          <div class="dialog-actions">
            <button class="ghost" type="button" data-close="plansDialog">Mégse</button>
          </div>
        </div>
      </dialog>

      <dialog class="billing-dialog" id="invoicesDialog">
        <div class="dialog-inner">
          <div class="dialog-head">
            <h2>Számlák letöltése</h2>
            <button class="dialog-close" type="button" data-close="invoicesDialog" aria-label="Bezárás">×</button>
          </div>
          <div class="invoice-list">${invoiceRows}</div>
        </div>
      </dialog>
      <script>
      (() => {
        document.querySelectorAll('[data-dialog]').forEach((button) => {
          button.addEventListener('click', () => {
            const dialog = document.getElementById(button.dataset.dialog);
            if (dialog && typeof dialog.showModal === 'function') dialog.showModal();
          });
        });
        document.querySelectorAll('[data-close]').forEach((button) => {
          button.addEventListener('click', () => {
            document.getElementById(button.dataset.close)?.close();
          });
        });
        const type = document.getElementById('portalBillingType');
        const company = document.getElementById('portalCompanyFields');
        type?.addEventListener('change', () => {
          company.style.display = type.value === 'company' ? 'block' : 'none';
        });
        document.querySelectorAll('dialog.billing-dialog').forEach((dialog) => {
          dialog.addEventListener('click', (event) => {
            if (event.target === dialog) dialog.close();
          });
        });
      })();
      </script>
    </div>
  `,
    { vision: !!user.vision_assist, variant: "page" },
  );
}

export function inviteAcceptPage(
  familyName: string,
  token: string,
  loggedIn: boolean,
  error = "",
  opts: { needsLeaveConfirmation?: boolean; currentFamilyName?: string } = {},
): string {
  const leaveBlock = opts.needsLeaveConfirmation
    ? `
      <p class="hint">Jelenleg a(z) <strong>${escape(opts.currentFamilyName || "másik")}</strong> család tagja vagy.
      A csatlakozáshoz ki kell lépned — ez visszavonhatatlan.</p>
      <form method="POST" action="/invite/${escape(token)}/accept">
        <label class="switch">
          <input type="checkbox" name="confirmLeave" value="1" required />
          Kilépek a jelenlegi családból, és csatlakozom
        </label>
        <button type="submit">Kilépek és csatlakozom</button>
      </form>`
    : loggedIn
      ? error
        ? `<p class="hint">Csatlakozás most nem lehetséges.</p><a href="/account"><button type="button">Fiók</button></a>`
        : `<form method="POST" action="/invite/${escape(token)}/accept"><button type="submit">Csatlakozom</button></form>`
      : `<p class="hint">Küldjük a belépési kódot…</p>`;

  return layout(
    "Meghívó",
    authChrome(
      "Meghívó",
      `Meghívót kaptál a(z) <strong>${escape(familyName)}</strong> családba.`,
      `${error ? `<p class="error">${escape(error)}</p>` : ""}
      ${leaveBlock}`,
    ),
    { variant: "auth" },
  );
}

function escape(s: string): string {
  return s
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}
