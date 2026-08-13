# Tasks

## Task 1 — Apple identity foundation

Goal: introduce verified Apple identity exchange without granting included
provider access while the feature flag is off.

Files: `backend/main.py`, `backend/auth_utils.py`, `backend/database.py`,
`backend/config.py`, `backend/requirements.txt`, `backend/tests/test_free_included_minutes.py`.

Acceptance: `pytest backend/tests/test_free_included_minutes.py -q` proves a
verified Apple subject is stable across devices and flag-off Free access is
still denied.

Blast radius: backend registration/authentication for new Free users; existing
legacy device and Pro authentication must remain unchanged.

## Task 2 — Included quota enforcement

Goal: enforce 30 calendar-month minutes for verified Free identities using
server-determined audio duration, with the flag off by default.

Files: `backend/main.py`, `backend/config.py`, `backend/audio_duration.py`,
`backend/tests/test_free_included_quota.py`.

Acceptance: `pytest backend/tests/test_free_included_quota.py -q` proves
both flag states, 30-minute boundary, and rejection of untrusted duration.

Blast radius: all server transcription requests; flag off preserves Pro-only
access and flag on admits only verified Free identities within their quota.

## Task 3 — iOS included access

Goal: let a Free user authenticate with Apple and use eligible backend
transcription/summary services without an API key.

Files: `PaperorgNotes/Services/`, `PaperorgNotes/Models/`,
`PaperorgNotesTests/PaperorgNotesTests.swift`, and required entitlement/project
configuration generated from `project.yml`.

Acceptance: `xcodebuild test -project PaperorgNotes.xcodeproj -scheme
PaperorgNotes -destination 'platform=iOS Simulator,name=iPhone 16'` passes and
unit tests cover the Free routing decision.

Blast radius: Free recording start and processing; feature-off behavior stays
BYOK/Pro-only and no entitlement is inferred from a device ID.

## Task 4 — Conversion and localization

Goal: surface remaining minutes and the upgrade moments without blocking Free
use before the quota is exhausted.

Files: `PaperorgNotes/Views/`, `PaperorgNotes/Utilities/L10n.swift`,
`PaperorgNotes/Resources/Localizable.xcstrings`, `PaperorgNotesTests/PaperorgNotesTests.swift`.

Acceptance: the same `xcodebuild test` command passes and tests cover the
3-note/20-minute upgrade-prompt policy.

Blast radius: onboarding, paywall, and recording UX; when the backend flag is
off users retain the current paid-or-BYOK path.
