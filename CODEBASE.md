# Brownfield map

Observed at adoption commit `7c6db33`.

## Stack and entry points

- iOS: Swift 5.9, SwiftUI, SwiftData; app entry
  `PaperorgNotes/App/PaperorgNotesApp.swift` and root routing in
  `PaperorgNotes/App/MainTabView.swift`.
- Backend: a separate repository, `gdelagardelle/paperorg-notes-api`. FastAPI
  entry `main.py`, configuration in `config.py`, PostgreSQL in production
  through `database.py`. It is not vendored here; a copy used to live in
  `backend/` and had drifted from the deployed service.
- Subscription: StoreKit 2 client in
  `PaperorgNotes/Services/Subscription/SubscriptionService.swift`; product ID
  `com.paperorg.notes.pro.monthly`.

## Relevant data flow

1. `ProBackendClient` registers a device and stores a backend bearer token in
   Keychain.
2. `TranscriptionOrchestrator` routes Pro requests through
   `ProTranscriptionRouter`; `SummaryService` routes Pro summaries through
   `ProBackendClient`.
3. The backend currently treats a device ID as the local user and meters
   `usage_records` by calendar-month `period_key`.
4. Existing auth accepts legacy HS256 bearer tokens and optional Platform
   RS256 tokens; no Apple identity path exists yet.

## Existing conventions to preserve

- Swift services are `@MainActor`; persistent preferences live in
  `SettingsService`; secrets/tokens live in `KeychainService`.
- The string catalog is `PaperorgNotes/Resources/Localizable.xcstrings` and
  access is centralized by `PaperorgNotes/Utilities/L10n.swift`.
- Backend errors use FastAPI `HTTPException`; settings are typed fields in
  `Settings` and tests isolate SQLite by monkeypatching `database.DB_PATH`.
- The app’s test suite is `PaperorgNotesTests/PaperorgNotesTests.swift`, run in
  CI by `.github/workflows/ci.yml`. Backend tests live in the backend
  repository and run in its own CI.

## Adoption baseline

- iPhone 16 / iOS 18.5: 14 passed, 1 skipped, 0 failed (15 total).
- Backend Python 3.11: `backend/tests/test_platform_tokens.py`: 7 passed.
- Python 3.14 cannot install the current `psycopg[binary]==3.2.4` pin; that
  reproducibility follow-up is outside this feature’s scope.
