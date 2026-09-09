# Paperorg Pro on Android — Google Play Billing setup

Android sells Pro through Google Play. iOS keeps selling through StoreKit and
is not touched by any of this: Apple requires its own in-app purchase for
digital subscriptions, and Google requires Play Billing on a Play listing, so
the two paths stay separate and both grant the same server-side entitlement.

The app code and the notes-api endpoints are written and unit-tested. Nothing
below can be verified end to end until the Play Console side exists, because
Play returns no products for an app that is not on a track.

## Deadlines that apply right now

| Requirement | Deadline | Status |
|---|---|---|
| Play Billing Library 8.0.0+ for new apps and updates | 31 Aug 2026 | Met — the app ships 9.1.0 |
| targetSdk 36 | 31 Aug 2026 | Met — already targetSdk 36 |

Extensions for either run to 1 Nov 2026 on request, through the Policy status
page in Play Console.

## 1. Create the app in Play Console

Package name must be exactly `com.paperorg.notes`, matching
`android/app/build.gradle.kts` and `PLAY_INTEGRITY_PACKAGE_NAME` on the server.

Fill in the store listing, content rating, data safety, and privacy policy far
enough that an **internal testing** track will accept a build. Purchases cannot
be tested from a locally installed debug APK — the build has to come from Play.

## 2. Signing — done

The release build signs with an upload key, so Play holds the app signing key
that users actually verify. That is the recoverable arrangement: if the upload
key is ever lost, Google can reset it, whereas a lost self-managed app signing
key would end the app's ability to ship updates.

| What | Where |
|---|---|
| Keystore | `~/.android-keystores/paperorg-notes-upload.p12`, 4096-bit RSA, valid to 2054 |
| Alias | `paperorg-upload` |
| Password | macOS login keychain, `paperorg-notes-upload-keystore` |

The keystore lives outside the repository so it cannot be committed, and the
password is never written to disk in the clear. Build the bundle with:

```
cd android
python3 ~/Documents/AgenticOS/.agents/skills/secure-secret-intake/scripts/secret_run.py \
  --name paperorg-notes-upload-keystore --env PAPERORG_UPLOAD_STORE_PASSWORD \
  -- ./gradlew :app:bundleRelease
```

Output lands at `android/app/build/outputs/bundle/release/app-release.aab`.

Without that environment variable the release build configures with no signing
config and produces an unsigned bundle rather than failing, so ordinary debug
work and any other machine are unaffected.

`versionCode` is still `1`, which is correct for a first upload and must be
raised for every subsequent one.

## 3. Create the subscription

Monetise with Play → Products → Subscriptions → Create subscription.

- Product ID: `pro` — must match `PLAY_PRO_PRODUCT_ID` on the server and
  `BillingRepository.PRO_PRODUCT_ID` in the app. It cannot be changed later.
- Name: Paperorg Pro

Then add two auto-renewing base plans inside that one subscription, so
subscribers can move between billing periods without losing entitlement:

| Base plan ID | Period | Price |
|---|---|---|
| `monthly` | 1 month | €5.99 |
| `annual` | 1 year | €49.99 |

Base plan IDs cannot be changed or reused after activation. Set country
availability and activate both. The app reads prices from Play, so nothing in
the code needs to know these numbers.

Note the divergence from iOS, which sells monthly only. If annual should exist
on iOS too, that is separate App Store Connect work.

## 4. License testers

Play Console → Settings → License testing. Add the Google account used on the
Samsung. License testers get real purchase flows without being charged, and
renewals are compressed so a monthly subscription renews in minutes.

## 5. Grant the service account Android Publisher access

The server already has a Google service account for Play Integrity. Reuse it
rather than creating a second key:

1. Play Console → Users and permissions → Invite the service account email.
2. Grant **View financial data** and **Manage orders and subscriptions** for
   the Paperorg Notes app.
3. Confirm the same key is readable at the path in
   `PLAY_INTEGRITY_SERVICE_ACCOUNT_FILE`, or set
   `PLAY_BILLING_SERVICE_ACCOUNT_FILE` to a separate key.

Permission changes can take up to 24 hours to take effect on the API.

## 6. Real-time Developer Notifications

Renewals, cancellations, expiries, refunds, and holds arrive as Pub/Sub pushes.
Without this, a cancellation only takes effect when the app next launches.

The Google Cloud project is `paperorg-notes` (number `357171624667`) — the same
one Play Integrity uses, which is hard-wired as `playCloudProjectNumber` in
`android/app/build.gradle.kts`. Keep RTDN there rather than in a new project, so
there is one service account and one place to look.

1. Create a Pub/Sub topic named `play-notes-rtdn`, without a default
   subscription. Its full name is
   `projects/paperorg-notes/topics/play-notes-rtdn`, which is what Play Console
   wants in the Monetisation setup field.
2. Grant `google-play-developer-notifications@system.gserviceaccount.com` the
   **Pub/Sub Publisher** role on that topic.
3. Create a **push** subscription on the topic with endpoint
   `https://notes-api.paperorg.com/v1/webhooks/play`.
4. Under Authentication, select a service account and set the audience to the
   same URL. That service account email and audience go into
   `PLAY_RTDN_SERVICE_ACCOUNT_EMAIL` and `PLAY_RTDN_AUDIENCE`. The webhook
   refuses any push it cannot verify, so both must be set.
5. Play Console → Monetise with Play → Monetisation setup → paste the full topic
   name, then use **Send test notification**. A correct setup answers
   `{"status":"test"}`.

## 7. Server configuration

On the VPS, in the notes-api environment:

```
PLAY_BILLING_ENABLED=true
PLAY_PRO_PRODUCT_ID=pro
PLAY_RTDN_SERVICE_ACCOUNT_EMAIL=<the push service account>
PLAY_RTDN_AUDIENCE=https://notes-api.paperorg.com/v1/webhooks/play
```

Startup refuses to boot with billing enabled and either the service account
file or the push identity missing, so a half-configured deployment fails loudly
instead of silently accepting unverifiable purchases.

The `play_purchase_tokens` table is created by `init_db()` on boot; no manual
migration is needed.

## 8. Verify on the device

1. Upload the AAB to internal testing and install from the Play link.
2. Settings → Plan shows Pro billed per month and per year, priced by Play.
3. Subscribe with the license-tester account. `GET /v1/usage` should then
   return `is_pro: true`.
4. Uninstall and reinstall. Pro should come back on its own — the app queries
   Play for existing purchases at launch. "Restore purchase" does the same on
   demand.
5. Cancel in Play. Pro stays active until the period ends, which is Google's
   behaviour and what the server records.
6. Refund the order in Play Console. Pro should drop within moments, via the
   voided-purchase notification.

## What the server trusts

The app never asserts that it is Pro. It forwards the Play purchase token, and
notes-api reads the subscription from the Play Developer API to decide.
Notifications are only a trigger to read again, so a replayed or forged push
cannot grant anything.

A purchase token is bound to the first install that claims it. A second device
offering the same token is refused rather than being granted a share of one
subscription.

Purchases are acknowledged only after the server confirms them. Google refunds
anything left unacknowledged for three days, which makes a silent verification
failure visible as a refund rather than as free Pro.
