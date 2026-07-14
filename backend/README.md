# Paperorg Notes Pro Backend

Proxy API for **Paperorg Pro** subscribers. Holds OpenAI / ElevenLabs / LuxASR keys server-side, meters usage, and enforces monthly minute limits.

## Quick start

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
# Edit .env with your provider API keys
uvicorn main:app --reload --host 0.0.0.0 --port 8080
```

Health check: `GET http://localhost:8080/health`  
Readiness (DB): `GET http://localhost:8080/ready`

## Database

**Local development** uses SQLite (`backend/paperorg_pro.db`) when `DATABASE_URL` is unset.

**Production** should use PostgreSQL — set `DATABASE_URL` in `.env`:

```
DATABASE_URL=postgresql://paperorg:paperorg@127.0.0.1:5444/paperorg_pro
```

Start Postgres locally with Docker:

```bash
cd backend
docker compose up -d
export DATABASE_URL=postgresql://paperorg:paperorg@127.0.0.1:5444/paperorg_pro
uvicorn main:app --reload --host 0.0.0.0 --port 8080
```

### Migrate SQLite → PostgreSQL

After pointing `DATABASE_URL` at Postgres:

```bash
python scripts/migrate_sqlite_to_postgres.py
```

Copies users, usage, subscription events, and transaction links from the local SQLite file.

## Auth flow

1. iOS app calls `POST /v1/auth/register` with `{ "device_id": "<uuid>" }`
2. Backend returns JWT `access_token`
3. All Pro endpoints use `Authorization: Bearer <token>`

## Subscription

- `POST /v1/subscription/verify` — send StoreKit `transaction_id` after purchase; backend verifies via **App Store Server API**
- `POST /v1/subscription/dev-activate` — **dev only** (`PAPERORG_DEV_MODE=true`) activates Pro without App Store

### App Store Server API (production)

Set in `.env`:

```
APPLE_ISSUER_ID=...
APPLE_KEY_ID=...
APPLE_PRIVATE_KEY=/path/to/AuthKey_XXXX.p8
APPLE_USE_SANDBOX=true   # false in production
```

The iOS app sends `transaction_id` from StoreKit 2; the backend fetches and verifies the signed transaction with Apple.

### App Store Server Notifications (v2)

Configure in App Store Connect → your app → App Store Server Notifications:

```
POST https://YOUR-HOST/v1/webhooks/app-store
```

The backend verifies the signed payload and updates Pro status on renewals, expirations, refunds, and revocations. Users are linked by `originalTransactionId` when they first verify a purchase.

## Pro endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /v1/usage` | Minutes used / remaining |
| `POST /v1/transcribe/openai` | OpenAI transcription proxy |
| `POST /v1/transcribe/elevenlabs` | ElevenLabs Scribe proxy |
| `POST /v1/transcribe/luxasr` | LuxASR async proxy |
| `POST /v1/summarize` | GPT-4o-mini structured summary |
| `GET /v1/email/status` | Whether server-side email relay is configured |
| `POST /v1/email/send` | Send note email on behalf of the user (multipart) |

## Email relay (hands-free auto-send)

The iOS app sends post-recording emails through notes-api so users only add recipients.

**Production (recommended):** configure SMTP in the **Paperorg Platform admin** for `app_id=notes`. notes-api forwards sends using `PLATFORM_INTERNAL_TOKEN`. See [`docs/PLATFORM_EMAIL_API.md`](../docs/PLATFORM_EMAIL_API.md).

```bash
PLATFORM_API_URL=https://poplatform.paperorg.com
PLATFORM_INTERNAL_TOKEN=...
```

Check: `GET /v1/email/status` → `{"available": true, "source": "platform_relay"}`

**Dev fallback:** set `EMAIL_SMTP_*` locally on notes-api if Platform email is not ready yet.

## Limits

Default **600 minutes/month** per Pro user (`PRO_MINUTES_PER_MONTH`).

## Production checklist

- Set `PAPERORG_DEV_MODE=false`
- Use a strong `PAPERORG_JWT_SECRET`
- Set `DATABASE_URL` to a managed PostgreSQL instance (Railway, Fly Postgres, Supabase, etc.)
- Configure App Store Server API credentials (see above)
- Set `APPLE_USE_SANDBOX=false` for App Store builds
- Deploy behind HTTPS (Fly.io, Railway, Render, etc.)
- Set `PAPERORG_PRO_BACKEND_URL` in iOS **Release** config (`project.yml`)
- See [`docs/PRO_BACKEND_DEPLOYMENT.md`](../docs/PRO_BACKEND_DEPLOYMENT.md)

## App Store product

Create an auto-renewable subscription in App Store Connect:

- Product ID: `com.paperorg.notes.pro.monthly`
- Suggested price: €7.99–9.99/month
