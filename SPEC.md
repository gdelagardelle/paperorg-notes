# Paperorg Notes — included minutes launch

## Approved product decision

Paperorg Notes offers 30 included, server-funded transcription minutes per
calendar month to a signed-in Free user. Included processing contains both
transcription and the requested AI summary. Pro remains 600 minutes per
calendar month and uses the App Store price returned by StoreKit.

## Users and outcome

A new user can record and receive a useful note without supplying an AI key.
They sign in with Apple before included processing begins, see their remaining
minutes, and can still choose BYOK for self-funded processing. A Free user is
shown an upgrade offer after three completed notes or 20 used included minutes;
the server enforces a hard stop at 30 minutes.

## Non-goals

- Recording normal Phone/FaceTime calls (iOS does not expose that audio).
- Adding an annual subscription product before it exists in App Store Connect.
- Enabling the production flag, deploying the backend, changing App Store
  Connect pricing, or submitting a build.
- Claiming speaker labels or automatic email delivery beyond their verified
  existing capability.

## Security and launch constraints

- The entitlement identity is the verified Apple `sub`, never a resettable
  device ID.
- The feature is off by default in every environment. Both flag states are
  tested. Launch is an explicit backend configuration change after review.
- The server, not a client-supplied duration field, determines metered audio
  duration before an included/pro provider call.
- StoreKit remains the source of the displayed subscription price.

## Approval

Approved by Germain on 2026-08-13: 30 included minutes/month and the
Sign in with Apple entitlement model.
