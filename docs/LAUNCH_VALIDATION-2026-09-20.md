# Launch validation — 20 September 2026

Candidate: iOS **1.0.0 (68)**, bundle `com.paperorg.voicenotes`, Luxxow team `CZY6SHVSXB`.

## Errors reproduced and corrected

- Expired or malformed server Pro expiry could continue unlocking paid features and displaying a stale allowance. Both access and display now check expiry.
- Server confirmation set the separate StoreKit trust flag. Only StoreKit now establishes that trust, and a previous launch's saved boolean is discarded pending verification.
- Failed subscription verification without StoreKit proof claimed Pro was activating and usable. It now shows the localized activation failure and restore guidance.
- A backend authentication rejection allowed English processing to fall through to Apple Speech. It now stops provider fallback, like entitlement and quota rejections.
- Two views referenced SwiftData without importing it, causing compiler warnings. Both imports are explicit.

Regression checks first failed against the original behavior, then passed after the fixes.

## Verification evidence

| Gate | Result |
| --- | --- |
| iOS unit suite | 73 tests reported; zero failures, one expected simulator Keychain skip |
| UI suite | Five-language entry-screen test passed |
| Release analyzer | Passed with warnings promoted to errors; no compiler warnings in final log |
| Contract checks | All five localization, processing and recovery checks passed |
| Archive | Signed build 68 archived successfully on 20 September |
| Export/upload/TestFlight | See local `Exports/build68/STATUS.md`; archive is not upload proof |
| Android | Source unchanged in this follow-up; prior build-67 validation had 48 passing tests and debug assembly |
| Physical device / live Apple purchase | Still pending; simulator and fixture tests do not establish acceptance |

Archive: `~/Library/Developer/Xcode/Archives/2026-09-20/PaperorgNotes-build68.xcarchive`.
Logs and artifact metadata are retained locally in `Exports/build68/` (ignored by Git).
The iOS changes are in [Notes PR 26](https://github.com/gdelagardelle/paperorg-notes/pull/26).

## Payment service follow-up

A separate Platform change adds opt-in production-first purchase lookup, with sandbox fallback only for Apple's transaction-not-found code. It verifies signed data against the selected environment and binds notification transactions to the verified outer environment. Existing deployment behavior stays unchanged until explicitly configured.

The full Platform test run also reproduced a usage-chart error under a Luxembourg-time database: UTC labels did not match database-local dates and the first day was truncated. The correction aggregates whole UTC days. All **120 Platform tests pass** on an isolated PostgreSQL 17 database. One existing Starlette/httpx deprecation warning remains.

The Platform changes are prepared in `codex/appstore-environments`; deployment and real Apple purchase/restore checks remain outstanding. The live service was last verified as sandbox-only at revision `91985d1` on 19 September.

## Remaining launch gates

- Restore Xcode access to the Luxxow Apple account, upload build 68, and confirm processing plus tester availability. The previous build-67 upload failed at account access; no upload is inferred from a local export.
- Review/deploy the Platform changes with the correct Apple app ID and auto mode, then verify real purchase, restore and notifications.
- Complete physical-device recording, interruption, offline recovery, purchase and native-language acceptance from the release checklist.
- Finish store screenshots, reviewer details, privacy/listing reconciliation and Google merchant verification.

This report records code and local validation. It does not claim deployment, App Store submission, store approval or public launch.
