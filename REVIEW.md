# Review

## Task 1 — Apple identity foundation

Execution profile: solo (Codex-only), same-model fallback review. The Duo
orchestrator did not produce a passed result-tree record: its candidate-tree
materializer failed closed before gate verification in two checkouts. Do not
describe this as a Duo-gated delivery.

Reviewed scope: backend auth/config/database/main only. The implementation
verifies Apple RS256 identity assertions against Apple JWKS with the expected
issuer and bundle-ID audience, stores only the verified subject, issues a
stable account token, and preserves the legacy/device and Platform paths.

Evidence: protected backend tests 9 passed (2 inherited FastAPI deprecation
warnings), diff check passed, and `gitleaks detect --source . --no-banner
--redact` reported no leaks.

Finding [S]: a concurrent first sign-in for the same Apple subject may race on
the unique database index and return an error. Defer a conflict-retry path to
the quota task; it cannot create duplicate entitled users.

## Task 2 — included quota enforcement

Same-model fallback review. The 30-minute limit is selected only for a
non-Pro user with a stored Apple subject while the feature flag is enabled;
device-only and flag-off paths keep their existing paid-or-BYOK behavior.
The client-sent duration is no longer used for provider accounting. A minimal
M4A `mvhd` reader rejects uploads whose duration cannot be determined before a
provider call. The summary endpoint is additionally rate limited for Free
accounts. Protected backend tests: 14 passed; gitleaks: no leaks.

## Tasks 3–4 — iOS access, conversion, and localization

Same-model fallback review. The iOS app exposes included usage only after a
successful Apple account exchange returned a non-Pro allowance. It retains the
existing BYOK fallback, shows the allowance remaining, and presents Pro once
after three completed notes or 20 used minutes. The entitlement is generated
from `project.yml`; new conversion/paywall strings have English, French, and
German translations. Xcode iPhone 16/iOS 18.5 tests passed: 16 passed, 1
expected simulator Keychain skip, 0 failed. A physical-device Sign in with
Apple and production-backend smoke test remains a release requirement; the
feature flag is deliberately disabled by default.
