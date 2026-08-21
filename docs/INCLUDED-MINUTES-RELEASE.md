# Included Minutes release checklist

This release adds a device-bound Free allowance without changing the existing
Pro subscription: Free receives 30 transcription minutes per calendar month
without an app sign-in; Pro retains 600 minutes per month.

## Required release configuration

1. Store the `openai` credential in the Paperorg Platform vault with scope
   `app` and `app_id=notes`. Add `elevenlabs` or `luxasr` only when those
   providers are enabled for Notes.
2. Configure notes-api with `PLATFORM_API_URL` and a scoped
   `PLATFORM_INTERNAL_TOKEN`. In this mode the Platform vault is authoritative:
   notes-api never falls back to an older local provider key after a remote key
   is disabled or rotated.
3. Deploy the backend version containing this change with a non-development
   `PAPERORG_JWT_SECRET` (32+ characters), production database, and the Apple
   root-certificate directory used for App Store transaction verification.
4. Keep `FREE_INCLUDED_MINUTES_ENABLED=false` until the backend deployment,
   Platform credential-resolution smoke test, provider cost alert, App Attest
   anti-abuse implementation, and StoreKit product review are all complete.
   Turn it on remotely with
   `FREE_INCLUDED_MINUTES_ENABLED=true` to activate Free usage.
5. Keep `FREE_MINUTES_PER_MONTH=30` unless a later pricing decision changes
   the allowance. The server determines M4A duration; the app cannot raise
   the allowance by sending a different duration.

## Operational boundaries

- Provider credentials are held in the Paperorg Platform vault and resolved
  only by notes-api over the internal service-token boundary. Do not put
  Paperorg provider credentials in the app, repository, logs, or build settings.
- The Free allowance is tied to the app's device identifier in the iOS Keychain,
  not an account. It does not migrate to another device; this is deliberate so
  trying the app requires no sign-in. The backend rate-limits registration and
  persists a per-user transcription request limit as well as an atomic,
  server-measured monthly-minute reservation. A device identifier alone is not
  a fraud-proof identity: keep Free disabled until App Attest is implemented
  and verified on a physical device.
- Pro entitlement remains controlled by App Store transaction verification;
  the app continues to load the price from StoreKit rather than hard-coding a
  price.
- Normal iPhone Phone/FaceTime calls are not captured by this app. The
  allowance applies to audio recorded inside Paperorg Notes.

## Release verification

1. On a fresh physical device, tap **Use included minutes** and confirm
   `/v1/usage` returns a 30-minute allowance without an app sign-in.
2. Record a short in-app audio note and confirm the backend, not the client,
   meters its M4A duration. Confirm repeated concurrent attempts cannot exceed
   the 30-minute allowance.
3. Confirm that 30 minutes are enforced and that restoring or buying Pro
   changes the allowance to 600 minutes; verify the 12-per-15-minute request
   limit separately.
4. Repeat the visible Free, Pro, and remaining-minutes screens in English,
   French, and German.
