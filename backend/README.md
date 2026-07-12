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

## Auth flow

1. iOS app calls `POST /v1/auth/register` with `{ "device_id": "<uuid>" }`
2. Backend returns JWT `access_token`
3. All Pro endpoints use `Authorization: Bearer <token>`

## Subscription

- `POST /v1/subscription/verify` — send StoreKit transaction after purchase
- `POST /v1/subscription/dev-activate` — **dev only** (`PAPERORG_DEV_MODE=true`) activates Pro without App Store

## Pro endpoints

| Endpoint | Purpose |
|----------|---------|
| `GET /v1/usage` | Minutes used / remaining |
| `POST /v1/transcribe/openai` | OpenAI transcription proxy |
| `POST /v1/transcribe/elevenlabs` | ElevenLabs Scribe proxy |
| `POST /v1/transcribe/luxasr` | LuxASR async proxy |
| `POST /v1/summarize` | GPT-4o-mini structured summary |

## Limits

Default **600 minutes/month** per Pro user (`PRO_MINUTES_PER_MONTH`).

## Production checklist

- Set `PAPERORG_DEV_MODE=false`
- Use a strong `PAPERORG_JWT_SECRET`
- Implement App Store Server API verification for `signed_transaction_info`
- Deploy behind HTTPS (Fly.io, Railway, Render, etc.)
- Set `PAPERORG_BACKEND_URL` in the iOS app build config

## App Store product

Create an auto-renewable subscription in App Store Connect:

- Product ID: `com.paperorg.notes.pro.monthly`
- Suggested price: €7.99–9.99/month
