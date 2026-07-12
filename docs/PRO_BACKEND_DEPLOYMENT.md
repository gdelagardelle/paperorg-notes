# Paperorg Pro Backend — Production Deployment

Quick reference while you deploy item #1. The iOS **Release** build reads `PAPERORG_PRO_BACKEND_URL` from Info.plist.

---

## 1. Environment variables

Copy `backend/.env.example` → production secrets:

| Variable | Production value |
|----------|------------------|
| `PAPERORG_JWT_SECRET` | Long random string (32+ bytes) |
| `PAPERORG_DEV_MODE` | `false` |
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

## 3. Health check

```
GET https://YOUR-HOST/health
→ {"status":"ok","service":"paperorg-pro"}
```

---

## 4. Point iOS Release build at your URL

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

## 5. Verify subscription flow

1. iOS purchase (StoreKit sandbox or production)
2. App sends `POST /v1/subscription/verify` with `transaction_id`
3. Backend calls App Store Server API → verifies JWS → sets Pro + expiry
4. `GET /v1/usage` returns `is_pro: true`

---

## 6. Staging tip

Deploy a second instance with `APPLE_USE_SANDBOX=true` and use a **Staging** Xcode configuration before production.

---

*Last updated: 2026-07-12*
