# Progress

- 2026-08-13 adoption baseline: iPhone 16/iOS 18.5 Xcode tests 14 passed, 1
  skipped, 0 failed. Backend Python 3.11 platform-token tests 7 passed.
- 2026-08-13: product approval recorded — 30 included minutes/calendar month,
  verified Sign in with Apple entitlement, feature default off. Dispatches: 0.
- 2026-08-13 task 1: Duo gate could not complete because its candidate-tree
  materializer failed in both a linked worktree and a clean clone; the first
  clone gate otherwise caught a false-positive `token =` secret pattern. The
  repair capability expired while its stdin handoff was absent. Same-model
  fallback review: protected backend suite 9 passed; `gitleaks detect` found
  no leaks. No deployment. Dispatches: 4 (3 failed infrastructure/gate runs,
  1 stale repair attempt).
- 2026-08-13 task 2: same-model fallback implementation — verified Apple
  accounts receive 30 calendar-month minutes only when the backend feature
  flag is enabled; device-only accounts remain excluded. Uploaded M4A metadata
  now determines metered duration; the client duration form field is ignored.
  Protected backend tests: 14 passed; gitleaks: no leaks.
