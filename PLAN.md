# Plan — included minutes launch

Execution profile: solo (Codex-only). This environment cannot provide an
independent Fable/Claude review; all reviews will be labeled same-model.

Mode: production — this is a live iOS product with paid subscriptions and
provider-funded usage. Branch: `duo/free-credit-launch`. Rollback reference:
`f21aaab` (provisional documented TestFlight commit; not live-verified).

## Architecture

The backend gains an Apple identity exchange endpoint. It validates the Apple
identity token, persists the verified `sub`, and issues the existing backend
bearer token for that user. Legacy device registration remains for current Pro
and BYOK flows. A feature flag gates Free provider use. When on, a verified
Apple identity has a 30-minute calendar-month quota; Pro has 600. Metering is
derived from the uploaded M4A bytes before provider calls, not the posted
duration field.

The iOS client asks for Sign in with Apple only when a Free user elects to use
included processing. It sends the identity token to the backend, refreshes
usage, and routes eligible Free users through the same backend transcription
and summary services as Pro. The normal Pro upsell stays StoreKit-driven.

## Tasks

1. **Apple identity foundation** — verified identity exchange, persistent
   subject mapping/migration, legacy compatibility, flag-off tests.
2. **Included quota enforcement** — 30-minute entitlement, server-owned M4A
   duration metering, flag-on/off and quota-boundary tests.
3. **iOS included access** — native Sign in with Apple, entitlement refresh,
   safe backend routing for Free, and regression tests.
4. **Conversion and localization** — Free-default progression, usage/threshold
   upgrade states, store-priced Pro sheet, and English/French/German strings.

Estimated Sol calls: 4 primary task dispatches, plus up to 3 bounded repairs
if gates fail. Generated media: none. Deployment target: none in this round.

## Release requirement outside this plan

Before turning the flag on: enable Sign in with Apple capability for the app
identifier in Apple Developer, set the backend production configuration, test
with a real Apple ID and Sandbox purchase, configure the subscription’s actual
App Store price, and separately approve deployment.

## Plan approval

The CEO approved the product/identity approach on 2026-08-13. This four-task
split is the safe implementation decomposition of that approval; no deployment
or store configuration is included.
