# Included Minutes release checklist

This release adds an account-bound Free allowance without changing the existing
Pro subscription: Free receives 30 transcription minutes per calendar month
after Sign in with Apple; Pro retains 600 minutes per month.

## Required release configuration

1. In the Apple Developer portal, enable **Sign in with Apple** for the
   `com.paperorg.notes` App ID. Archive the app from Xcode with the generated
   entitlement.
2. Deploy the backend version containing this change with a non-development
   `PAPERORG_JWT_SECRET`, production database, and provider credentials.
3. Keep `FREE_INCLUDED_MINUTES_ENABLED=false` until the backend deployment,
   Apple sign-in smoke test, provider cost alert, and StoreKit product review
   are all complete. Turn it on remotely with
   `FREE_INCLUDED_MINUTES_ENABLED=true` to activate Free usage.
4. Keep `FREE_MINUTES_PER_MONTH=30` unless a later pricing decision changes
   the allowance. The server determines M4A duration; the app cannot raise
   the allowance by sending a different duration.

## Operational boundaries

- Configure OpenAI, ElevenLabs, LuxASR, and the optional email relay only as
  backend environment variables. Do not put provider credentials in the app.
- Pro entitlement remains controlled by App Store transaction verification;
  the app continues to load the price from StoreKit rather than hard-coding a
  price.
- Normal iPhone Phone/FaceTime calls are not captured by this app. The
  allowance applies to audio recorded inside Paperorg Notes.

## Release verification

1. On a physical device, sign in with Apple and confirm `/v1/usage` returns a
   30-minute allowance.
2. Record a short in-app audio note and confirm the backend, not the client,
   meters its M4A duration.
3. Confirm that 30 minutes are enforced and that restoring or buying Pro
   changes the allowance to 600 minutes.
4. Repeat the visible Free, Pro, and remaining-minutes screens in English,
   French, and German.
