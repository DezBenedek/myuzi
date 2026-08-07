# MyÜzi

Egyszerű családi kommunikációs alkalmazás: hangüzenetek, hang- és videóhívás, kijelzőmegosztás.

- **App:** MyÜzi  
- **Domain:** https://myuzi.dezso.hu  
- **LiveKit:** `wss://call.api.dezso.hu`  
- **Email:** Cloudflare Email Service → `noreply@dezso.run`

## Struktúra

```
worker/   Cloudflare Worker (Hono) + D1 + R2 + web fiókkezelő
app/      Flutter (Android, iOS, Windows, macOS, Linux)
```

## Funkciók

1. Passwordless belépés (név + email + 6 jegyű kód)
2. Család létrehozása / meghívó elfogadása
3. Emberek és csoportok a főoldalon
4. Csak hangüzenetes beszélgetés
5. 1:1 és csoportos hanghívás
6. Videóhívás
7. Kijelzőmegosztás
8. Mikrofon / kamera / kamera váltás / bontás
9. Bejövő hívás (app poll + push token tárolás)
10. Meghívó link / email
11. Látássérült segítség mód
12. Stripe előfizetés a webes fiókkezelőből (nem agresszív paywall)

### Előfizetések

| Csomag   | Ár          | Max tag |
|----------|-------------|---------|
| Család   | 1990 Ft/hó  | 6       |
| Család+  | 4990 Ft/hó  | 25      |

Csak a család tulajdonosa fizet.

## Worker telepítés

```bash
cd worker
npm install

# D1
npx wrangler d1 create myuzi
# Illeszd be a database_id-t a wrangler.jsonc-be

# R2
npx wrangler r2 bucket create myuzi-voice

# Migráció
npm run db:migrate

# Secrets
npx wrangler secret put SESSION_SECRET
npx wrangler secret put LIVEKIT_API_KEY
npx wrangler secret put LIVEKIT_API_SECRET
npx wrangler secret put STRIPE_SECRET_KEY
npx wrangler secret put STRIPE_WEBHOOK_SECRET

# Email: Cloudflare Email Service
# Dashboard → Compute → Email Service → Email Sending → Onboard Domain (dezso.run)
# A Worker `EMAIL` bindingje a wrangler.jsonc-ben van (send_email).

# Stripe price ID-k a wrangler.jsonc vars-ban:
# STRIPE_PRICE_FAMILY, STRIPE_PRICE_FAMILY_PLUS

npm run deploy
```

DNS: `myuzi.dezso.hu` → Worker route (lásd `wrangler.jsonc`).

Stripe webhook endpoint: `https://myuzi.dezso.hu/api/billing/webhook`

### Helyi fejlesztés

```bash
cd worker
cp .dev.vars.example .dev.vars   # töltsd ki
npm run db:migrate:local
npm run dev
```

Helyben a `send_email` binding szimulált: a kimenő levél a wrangler logban / helyi fájlokban jelenik meg. Éles küldéshez a bindingre tehetsz `"remote": true`-t.

## CI

GitHub Actions (`.github/workflows/android.yml`) minden `main` pushnál (és manuálisan) épít Android **APK** + **AAB** artifacteket.

Artifacts: Actions run → Artifacts → `myuzi-android-apk` / `myuzi-android-aab`

## Flutter app

```bash
cd app
flutter pub get

# Production API
flutter run --dart-define=API_BASE_URL=https://myuzi.dezso.hu

# Helyi Worker
flutter run --dart-define=API_BASE_URL=http://127.0.0.1:8787
```

Platformok: `android`, `ios`, `windows`, `macos`, `linux`.

### Push / bejövő hívás

- Az app 4 másodpercenként pollolja az aktív hívásokat (`/api/calls/active`).
- A `/api/devices/push-token` endpoint tárolja a tokeneket; FCM/APNs provider kulcsok beállítása után a Worker logolás helyett küldhető valódi push (lásd `routes/calls.ts`).

## LiveKit

Self-hosted:

- Signaling: `wss://call.api.dezso.hu`
- TURN: `turn.call.api.dezso.hu`

A Worker JWT-t ad ki a LiveKit API key/secret párossal.

## API áttekintés

| Metódus | Útvonal | Leírás |
|---------|---------|--------|
| POST | `/api/auth/start` | Kód küldése |
| POST | `/api/auth/verify` | Belépés |
| GET | `/api/auth/me` | Profil |
| GET/POST | `/api/families…` | Család |
| POST | `/api/invites` | Meghívó |
| GET | `/api/conversations` | Emberek/csoportok |
| POST | `/api/messages/:id` | Hangüzenet feltöltés (R2) |
| POST | `/api/calls/start` | Hívás + LiveKit token |
| POST | `/api/billing/checkout` | Stripe Checkout |
| POST | `/api/billing/webhook` | Stripe webhook |

Web: `/`, `/login`, `/account`, `/invite/:token`
