# PaperOrg Notes — release checklist

Updated 20 September 2026. Candidate: **1.0.0 (68)** on `codex/launch-preparation`.

## Candidate contents

- Continuous segmented recording, persisted segments, interruption and offline recovery from main.
- Free-entry and subscription activation fixes from the build-66 branch.
- Server-confirmed cloud usage only: pending activation no longer displays an invented 600-minute balance.
- Expired, revoked or upgraded unfinished StoreKit transactions cannot grant local Pro access.
- Complete English, French, German, Luxembourgish and Portuguese subscription copy.
- Expired or malformed server entitlements cannot unlock Pro or display stale cloud allowance.
- StoreKit trust is verified anew at launch; server confirmation cannot impersonate it.
- Failed verification without purchase proof shows a retry message; authentication rejection stops provider fallback.
- Build and review details: [20 September validation](LAUNCH_VALIDATION-2026-09-20.md).

## Build and source evidence

- [ ] Record commit SHA and archive location, then verify bundle, team and build metadata.
- [ ] Localization and processing/recovery guards pass.
- [ ] Unit and UI suites pass; document any skip.
- [ ] Release analyzer passes with Swift warnings as errors.
- [ ] Android unit tests and debug assembly pass for the consolidated source.
- [ ] CI passes on the PR revision.
- [ ] Apple processes the exact candidate and makes it available to internal Beta testers.

## Live services and purchases

The Release app uses `https://notes-api.paperorg.com` and `https://poplatform.paperorg.com`. Provider credentials stay server-side. Free is device-bound with 30 minutes/month; Pro includes 600. Session caps are three minutes Free and 180 Pro. Verify those limits against server responses on the candidate.

**Open production blocker:** on 19 September both running services used `APPLE_USE_SANDBOX=true`. The authoritative Platform checkout was `91985d1`; its App Store verification and notification code select one environment. Production transaction and notification support must be implemented and validated while preserving TestFlight/App Review sandbox compatibility. Do not merely flip a flag on the shared live service. Apple requires transaction lookup in the environment that generated the transaction: [TransactionIdNotFoundError](https://developer.apple.com/documentation/appstoreserverapi/transactionidnotfounderror).

- [ ] Verify current server identity, device attestation, provider resolution and quota accounting.
- [ ] Verify purchase, activation retry and restore against the server; a local Pro label is not proof of cloud access.
- [ ] Verify production and sandbox lookup, signed-data validation, renewals, expiry, refunds and notifications.
- [ ] Check cost alerts, service monitoring, backup coverage and rollback procedures.

Use existing PoVault connectors and protected credential intake if required. Never place credentials or reviewer passwords in these documents.

## Physical-device acceptance

- [ ] Fresh install: consent, microphone permission, included Free minutes without sign-in or API keys.
- [ ] Short recording produces audio, transcript, summary and accurate remaining minutes.
- [ ] Pro purchase and restore remain usable after relaunch and after Free is exhausted.
- [ ] Pending activation shows a pending message, without claiming unconfirmed cloud allowance.
- [ ] Background, locked-screen and long recordings preserve audio across segment boundaries.
- [ ] Interruption and offline retry preserve captured audio without duplicate usage charges.
- [ ] Session and monthly caps are enforced with clear messages.
- [ ] Luxembourgish native-speaker QA; French, German, English and Portuguese spot checks.
- [ ] Import, search, PDF/text export, widget, Face ID and privacy export/deletion work.
- [ ] Email testing uses disposable content and an explicitly approved recipient.

## Store preparation

App: `6807097485`; bundle: `com.paperorg.voicenotes`; team: `CZY6SHVSXB`.
Monthly subscription: `com.paperorg.voicenotes.pro.monthly`.

- [ ] Replace the currently selected build 59 only after candidate acceptance.
- [ ] Refresh reviewer instructions and contact details; include the Pro subscription in review.
- [ ] Confirm final subscription price and localization in Apple; app displays StoreKit's price.
- [ ] Review billing grace-period choice and notification URLs.
- [ ] Refresh iPhone/iPad screenshots: record, transcript/summary, library, usage and plan.
- [ ] Reconcile listing copy, privacy declaration, live policy and consent with actual behavior.
- [ ] Set marketing URL to `https://notes.paperorg.com/` and verify support destination.
- [ ] Keep manual release selected until the launch decision.

## Android and public launch

- [ ] Resolve Google merchant payment-method verification. The portal warns of account/app removal on **18 October 2026** unless fixed and approved.
- [ ] Confirm the installed Android artifact, Play purchase/restore, Data Safety and listing.
- [ ] Prepare public download links and pricing; retain coming-soon wording until each store is live.
- [ ] Prepare screenshots, short demo, release copy and support ownership.

The date-stamped readiness assessment describes the starting state. This checklist records the remaining release gates; checked build tooling is not physical-device or store approval.
