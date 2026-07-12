# Paperorg Notes — TestFlight & App Store Checklist

Use this before submitting build **1.0.0** to TestFlight.

---

## App Store Connect

- [ ] App record created with bundle ID `com.paperorg.notes`
- [ ] Subscription product: `com.paperorg.notes.pro.monthly` (auto-renewable)
- [ ] Pricing and localizations (EN, FR, DE minimum for LU market)
- [ ] Privacy policy URL live (see `docs/privacy.html` or hosted copy)
- [ ] App category: **Productivity**
- [ ] Age rating questionnaire completed
- [ ] Export compliance: **ITSAppUsesNonExemptEncryption = NO** (already in Info.plist)

---

## Pro backend (production)

You are deploying the backend separately. When live, set **Release** build URL in `project.yml`:

```yaml
configs:
  Release:
    PAPERORG_PRO_BACKEND_URL: "https://YOUR-PRO-BACKEND-URL"
```

Then run `xcodegen generate` and rebuild Release.

Backend production env (see `backend/.env.example`):

- [ ] `PAPERORG_DEV_MODE=false`
- [ ] Strong `PAPERORG_JWT_SECRET`
- [ ] Provider API keys set
- [ ] App Store Connect API key (`.p8`) for subscription verification
- [ ] `APPLE_USE_SANDBOX=false` in production
- [ ] HTTPS only

---

## App Store Server API (App Store Connect → Users and Access → Keys)

- [ ] Issuer ID → `APPLE_ISSUER_ID`
- [ ] Key ID → `APPLE_KEY_ID`
- [ ] Private key `.p8` → `APPLE_PRIVATE_KEY` (path or PEM contents)
- [ ] Sandbox testing: `APPLE_USE_SANDBOX=true` on staging backend

---

## Device testing (TestFlight)

- [ ] Fresh install: Privacy → Plan selection → Free path with BYOK
- [ ] Pro path: StoreKit sandbox purchase → backend verify → transcription works
- [ ] Restore purchases on second device
- [ ] Usage meter updates after transcription
- [ ] 600 min limit returns clear error when exceeded
- [ ] SMTP auto-email (if configured)
- [ ] Face ID lock
- [ ] Swipe to delete note
- [ ] Branded PDF export (Pro)
- [ ] Luxembourgish transcription quality spot-check

---

## Screenshots (6.7" + 6.5" minimum)

Suggested screens:

1. Record tab with waveform
2. Note detail with summary + transcript
3. Notes library
4. Settings / Pro usage
5. Plan selection or paywall
6. Search results

---

## Metadata copy (draft)

**Subtitle:** Voice notes with Luxembourgish transcription  
**Keywords:** voice notes, transcription, Luxembourgish, Lëtzebuergesch, meeting notes, AI summary

**Description opening:**  
Paperorg Notes records voice on your device, transcribes in Luxembourgish and multiple languages, and turns recordings into structured meeting notes, action items, and email drafts.

---

## After TestFlight

- [ ] Collect crash reports (Sentry optional)
- [ ] Monitor backend logs for 402/429 rates
- [ ] Submit for App Review when stable

---

*Last updated: 2026-07-12*
