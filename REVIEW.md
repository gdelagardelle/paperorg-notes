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
