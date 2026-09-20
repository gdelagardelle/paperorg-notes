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

- Apple: monthly Pro corrected to EUR 5.99 in all 25 euro storefronts; other currencies preserved. Full English description, marketing URL and reviewer notes updated.
- Google: EUR 5.99 monthly already configured. Merchant verification still asks the owner to enter Google's bank test-deposit amount directly in the official form.
- Reviewer contact supplied by owner: +352 691800008; hello@luxxow.com. Saving the contact and other remaining store work is being verified.

Public release remains manual and has not been triggered. Store processing, review and installed-device purchase acceptance remain separate release gates.
