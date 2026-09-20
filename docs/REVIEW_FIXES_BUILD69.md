# Review fixes — build 69

This candidate addresses all seven findings from the build-68 launch review.

## Changes

- Selected language/style chips, recording playback controls and completed processing steps use matching foreground/background colors in both themes.
- Primary buttons use navy lettering on orange in dark mode. Orange filter chips, accent buttons and the recording icon also use navy. Press feedback preserves contrast.
- Speaker labels adapt to each theme. Orange text uses a darker shade on pale backgrounds.
- The global accent asset restores its light/dark variants, and the privacy-policy link has an explicit readable text tint.
- Explicit Restore Purchases calls `AppStore.sync()` before inspecting local entitlements. Background checks stay silent.
- Verified refund, expiry and upgrade updates re-read current entitlements and clear obsolete local trust. An old transaction does not blindly revoke a newer valid renewal; server grants remain independently checked.
- Purchase-presentation and internal Apple errors use the translation catalog in English, French, German, Luxembourgish and Portuguese, including wrapped StoreKit system errors.

## Verification

The new contrast and rendered-chip tests reproduced the original failures. Real StoreKit Test purchases also reproduced the missing restore sync and sticky local access after a refund before those paths were fixed.

The checked-in test plan enables the local StoreKit configuration for automated tests. CI avoids iOS 26.4/26.5 runtimes affected by Apple's StoreKit Test configuration issue ([FB22237318 discussion](https://developer.apple.com/forums/thread/826971)); it must use a working installed runtime instead of skipping these tests.

Targeted purchase/refund/restore checks and both-theme contrast checks passed. The Release analyzer and signed archive/export passed. The exported app and widget are both build 69, with production App Attest, debugging disabled and a valid distribution signature. Full-suite results and rendered images are retained in the local `Exports/build69/` evidence folder; the PR description records the final test outcome.

## Launch boundary

These are code and local test changes. App Store upload, TestFlight processing, physical-device acceptance, native-speaker copy acceptance and live purchase/restore remain separate checks. The Platform purchase-environment changes in PR 27 are unchanged and still require deployment before launch acceptance.
