# Paperorg Pro Backend — Production Deployment

Quick reference while you deploy item #1. The iOS **Release** build reads `PAPERORG_PRO_BACKEND_URL` from Info.plist.

---

## 1. Environment variables

Copy `backend/.env.example` → production secrets:

| Variable | Production value |
|----------|------------------|
| `PAPERORG_JWT_SECRET` | Long random string (32+ bytes) |
| `PAPERORG_DEV_MODE` | `false` |
| `DATABASE_URL` | `postgresql://user:pass@host:5432/dbname` |
| `OPENAI_API_KEY` | Server-side key |
| `ELEVENLABS_API_KEY` | Server-side key |
| `PRO_MINUTES_PER_MONTH` | `600` |
| `APPLE_BUNDLE_ID` | `com.paperorg.notes` |
| `APPLE_PRO_PRODUCT_ID` | `com.paperorg.notes.pro.monthly` |
| `APPLE_ISSUER_ID` | App Store Connect → Keys |
| `APPLE_KEY_ID` | App Store Connect → Keys |
| `APPLE_PRIVATE_KEY` | Path to `.p8` or PEM string |
| `APPLE_USE_SANDBOX` | `false` (prod) / `true` (staging) |

---

## 2. Run command

```bash
uvicorn main:app --host 0.0.0.0 --port 8080
```

Use a process manager (Fly, Railway, Docker) with HTTPS termination.

---

## 3. Health checks

```
GET https://YOUR-HOST/health
→ {"status":"ok","service":"paperorg-pro","database":"postgresql"}

GET https://YOUR-HOST/ready
→ {"status":"ready","database":"connected"}
```

Use `/ready` for load balancer readiness probes (returns 503 if the database is down).

---

## 4. PostgreSQL (recommended for production)

SQLite is fine for local dev. In production, attach a managed Postgres and set:

```
DATABASE_URL=postgresql://USER:PASSWORD@HOST:5432/paperorg_pro
```

Local Postgres via Docker (port **5444** avoids conflict with a system Postgres on 5432):

```bash
cd backend && docker compose up -d
export DATABASE_URL=postgresql://paperorg:paperorg@127.0.0.1:5444/paperorg_pro
```

One-time migration from an existing SQLite file:

```bash
export DATABASE_URL=postgresql://...
python backend/scripts/migrate_sqlite_to_postgres.py
```

---

## 5. Point iOS Release build at your URL

In `project.yml`:

```yaml
settings:
  configs:
    Debug:
      PAPERORG_PRO_BACKEND_URL: "http://127.0.0.1:8080"
    Release:
      PAPERORG_PRO_BACKEND_URL: "https://YOUR-HOST"
```

```bash
xcodegen generate
```

Archive with **Release** configuration for TestFlight.

---

## 6. Verify subscription flow

1. iOS purchase (StoreKit sandbox or production)
2. App sends `POST /v1/subscription/verify` with `transaction_id`
3. Backend calls App Store Server API → verifies JWS → sets Pro + expiry
4. `GET /v1/usage` returns `is_pro: true`

---

## 7. App Store Server Notifications

In App Store Connect, set the notification URL to:

```
https://YOUR-HOST/v1/webhooks/app-store
```

Use the **Sandbox** URL for staging (`APPLE_USE_SANDBOX=true`) and **Production** for live.

Apple sends `{ "signedPayload": "..." }`. The backend handles:

- **Activate Pro:** `SUBSCRIBED`, `DID_RENEW`, `OFFER_REDEEMED`
- **Deactivate Pro:** `EXPIRED`, `GRACE_PERIOD_EXPIRED`, `REFUND`, `REVOKE`

Users must complete at least one in-app purchase verify so their `originalTransactionId` is linked.

---

## 8. Staging tip

Deploy a second instance with `APPLE_USE_SANDBOX=true` and use a **Staging** Xcode configuration before production.

---

*Last updated: 2026-07-12*
