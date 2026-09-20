# Launch fixes — 20 September 2026

## Mobile

- iOS 1.0.0 (70): readable error and Pro status text in light/dark appearance; included-minute connection failures translated into all five app languages.
- Android 1.0.5 (6): readable dark primary buttons, light status/error text, and explicit microphone permission handling. Android unit tests, release lint and debug assembly now run in CI.
- iOS: 79 tests passed, one expected simulator Keychain skip; five-language UI coverage included. Signed archive and App Store export succeeded. Upload currently blocked by Xcode Apple-account authentication.
- Android: 49 unit tests passed, release lint and assembly passed; signed release AAB built with the existing Notes upload certificate. Signing credential supplied only to Gradle through the protected Keychain launcher.

## Services

- Platform PR #27 merged and deployed at 0315954. Apple production lookup with verified sandbox fallback is enabled, numeric app ID configured. 120 tests passed on isolated PostgreSQL; readiness healthy.
- Notes API PR #33 merged and deployed at e646f9e. Restored Google Play purchases share one allowance across installations; consumed minutes, concurrent requests and late refunds preserved. 236 full-suite tests passed, then 39 focused billing cases. Isolated PostgreSQL concurrency checks passed. Readiness healthy.
- GitHub backend jobs did not start because the account payment/spending limit blocked Actions. Local validation is recorded separately from CI.

## Stores

- Apple: monthly Pro corrected to EUR 5.99 in all 25 euro storefronts; other currencies preserved. Full descriptions, promotional text and keywords saved in English, French, German and Portuguese. App subtitles localized. Marketing URL and reviewer notes updated.
- Google: EUR 5.99 monthly already configured. Merchant verification still asks the owner to enter Google's bank test-deposit amount directly in the official form.
- Reviewer contact supplied by owner: +352 691800008; hello@luxxow.com. Saved and visually verified in App Store Connect.

Public release remains manual and has not been triggered. Store processing, review and installed-device purchase acceptance remain separate release gates.

## Published preparation and remaining gates

- Android build 6 (1.0.5) is available to the existing internal testers; release notes cover all four store languages. Google accepted the bundle with no errors and two diagnostic-file warnings. No production release was started.
- Mobile CI run 35503575807 passed all three jobs: iOS build/tests/release analysis, Android tests/lint/assembly, and contract guards.
- Website PRs #2 and #3 merged; Sites version 25 deployed successfully from 2fec88316bb5afb1fa2c360cc13d75fd41d154a1. Five-language pricing and limits, coming-soon availability, privacy page and support links published while preserving newer live translations.
- iOS build 70 is signed and exported but still requires Xcode account authentication before upload; the store version still has old build 59 selected. Website sign-in does not refresh Xcode upload credentials.
- Google foreground microphone declaration requires a real demonstration video. Background audio input is the applicable purpose; no placeholder video was submitted.
- Owner-only Google bank-deposit verification remains pending. Google displays an account removal deadline of 18 October 2026 until verification is resolved.
- Installed-device recording, purchase, reinstall/restore, and final store review remain outstanding acceptance gates.
