# Changelog

## 1.0.0 (57) — 2026-09-11

- Continuously capture audio into durable two-minute segments on iOS and Android.
- Queue transcription during capture; combine results into one final note.
- Preserve completed chunks and recover unfinished audio after interruption.
- Preserve recording and monthly usage limits with stable backend segment identities.
- Archive prepared with Xcode 27 RC. Device acceptance and backend/privacy rollout
  remain separate gates; an archive is not a store release.

Rollback: use the prior mobile build and the backend revision recorded before
deployment. Do not remove recordings or segment caches during rollback.
