# Continuous segmented recording

Implementation branch: `codex/segmented-recording`. This document is not a
release or real-device certification. Deploy the matching notes-api changes
before installing a build that requires segmented transcription.

## User-facing contract

- One recording remains one note. A microphone capture runs continuously;
  closing an approximately 120-second upload file does not restart the mic.
- Completed segments are persisted locally before upload and processed in
  order. Transcription can run while capture continues. The final summary is
  requested after recording has stopped and all segments have transcripts.
- Losing connectivity must not delete captured audio. Completed segment
  transcripts are saved locally and reused rather than re-uploaded.
- Free's three-minute session cap and Pro's 180-minute session cap remain
  unchanged. The server remains authoritative for monthly usage and total
  recording length. Segmentation does not grant extra minutes.
- A microphone interruption, exhausted storage, or an overloaded capture
  queue is an explicit failure/interruption, not a successful empty recording.

## Client/server protocol

An authenticated `GET /v1/recording-capabilities` must advertise
`segmented_transcription: true` and `segment_seconds: 120`. Do not silently
send segment metadata to an older server that ignores it. Keep local audio
when the capability is absent or the server is unreachable.

Each transcription multipart request includes:

| Field | Meaning |
|---|---|
| `recording_session_id` | Stable UUID for the entire note recording |
| `segment_index` | Stable zero-based segment number |
| `segment_start_seconds` | Offset in captured audio, excluding pauses |

These fields accompany the existing audio, language and duration fields.
The server measures audio duration itself. Identity is scoped to the
authenticated principal and bound to the audio bytes. Retrying an accepted
segment returns its saved result rather than calling a provider again.
`_recording_provider` identifies the provider that produced a cached result.

A `409` pending/conflict/expired response must not trigger a fallback provider
or a new segment identity. In particular, a server crash or upstream timeout
may leave an unknown outcome. Keep the audio and surface this state; do not
claim exactly-once processing across an external provider without evidence.

## Privacy and rollout gate

The backend replay cache adds temporary server-side transcript retention.
The accompanying backend implementation must encrypt replay payloads, bound
their lifetime, and retain only non-content deduplication tombstones after
expiry. Review the actual cleanup schedule and public privacy disclosure
before deployment. Raw audio must not be persisted by this cache.

The implemented cache has a 24-hour replay lifetime, with startup and hourly
cleanup (up to 25 hours of live-database retention while healthy). Backups have
a separate retention policy. Non-content tombstones retain principal/session,
index, audio SHA-256, offset and duration to prevent paid replay. They currently
have no automatic expiry: include them in the account-deletion/privacy review.
Encryption keys are derived from the existing server JWT secret with domain
separation; rotating that secret makes previous replay payloads inaccessible
and returns `segment_expired`, rather than processing the audio again.

Unknown provider outcomes require operator reconciliation. External Platform
usage reporting remains best-effort: a crash between saving the transcript and
reporting usage can omit that external event. The local quota reservation is
retained. Do not describe this as end-to-end exactly-once billing.

Do not enable this by deploying only one component. A simulator/unit build
does not prove background recording, hardware continuity, or store readiness.

## Required device acceptance

Use synthetic/non-sensitive speech; explicitly authorize paid provider calls.

1. Record past two segment boundaries. Compare sample/frame continuity and
   audible speech across both joins, and confirm only one note is created.
2. Lock the screen, background the app, pause/resume, and interrupt with a
   call or route change. Confirm mic release, honest interrupted status and
   retained playable audio. Repeat after idle to cover prior mic regressions.
3. Go offline before a boundary, continue recording, reconnect, and verify
   queued transcription resumes without duplicated text or usage.
4. Terminate/relaunch after a completed chunk. Recover completed audio and
   available tail; never mark missing audio as recovered successfully.
5. Simulate a lost HTTP response after successful transcription. Repeat the
   same identity; verify a cached response and one quota debit.
6. Exhaust the Free session cap and monthly quota; repeat with Pro. Segment
   rotation must not reset either limit.
7. Simulate low disk and slow writes. Preserve earlier segments, surface the
   failure and release the mic. Verify playback/export across all segments.
8. Delete a note and delete all data while queued: remove local segment audio,
   results and pending work; completion must not recreate the deleted note.
9. Verify final summaries cover the complete ordered transcript and email is
   sent only after the final note is ready, never once per segment.

Store submission, provider-backed device tests, and public release are not
authorized or certified by this implementation task.

## Local verification (2026-09-11)

- Backend full regression suite: 234 tests passed using SQLite with native AAC
  fixtures enabled (without the fixture path, that integration case skips).
- Backend segment integration suite: 36 passed against an isolated PostgreSQL
  17.10 cluster, including concurrent claims and cumulative limits. The cluster
  was stopped after testing; no existing database was used.
- Swift standalone protocol harness exercises stable metadata, fail-closed
  capability checks, ambiguous-response fallback blocking, and silent chunks.
- iOS unit suite: 64 passed, one existing skipped, no failures on the isolated
  iOS 26.5 simulator. The full run's UI test failed to obtain an accessibility
  snapshot (`kAXError -25218`), so UI acceptance is not certified.
- Android: 48 unit tests passed on a forced rerun; debug APK built.
- Native iOS-generated AAC fixtures measure exactly 120, 60 and 180 seconds in
  the backend after validated Apple gapless-padding accounting. HTTP tests
  accept the 120+60 Free session and reject another second. This caught and
  corrected a real 120.064-second container-duration mismatch without loosening
  the cap or trusting a duration sent by the client.
- These tests use fixtures rather than paid providers. Device acceptance above
  remains a separate gate; this work has not been deployed or store-uploaded.

## Known limitations

- Android records 16 kHz mono PCM WAV (about 1.92 MB/minute). Keeping both
  segments and assembled playback doubles that storage. iOS also keeps a PCM
  recovery archive during capture; storage checks reserve encoding headroom.
- Retrying failed segmented transcription reuses completed chunks. Changing
  its language is not a new paid transcription operation in this iteration;
  Android explicitly rejects that request. iOS ready-note trimming invalidates
  segment caches only after successfully replacing the audio.
- Summary requests retain the existing retry ambiguity after an unknown
  response; the new audio deduplication ledger does not cover summaries.
- Android recovered background work does not automatically email the finished
  note. Large audio attachments remain subject to existing email size limits.

Backend companion worktree:
`/Users/germaind/dev/paperorg-notes-api/.worktrees/codex-segmented-transcription`
on branch `codex/segmented-transcription`.

Repeatable checks (from the mobile worktree unless specified):

```sh
swiftc PaperorgNotes/Models/SubscriptionPlan.swift Scripts/tests/SegmentProtocolTests.swift -o /tmp/notes-segment-protocol-tests
/tmp/notes-segment-protocol-tests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project PaperorgNotes.xcodeproj -scheme PaperorgNotes -destination 'platform=iOS Simulator,id=7E721ECE-1D6D-4DB5-9F0A-9F912C4FDB23' -only-testing:PaperorgNotesTests CODE_SIGNING_ALLOWED=NO -quiet
cd android
JAVA_HOME='/Applications/Android Studio.app/Contents/jbr/Contents/Home' ANDROID_HOME=/Users/germaind/Library/Android/sdk ./gradlew :app:testDebugUnitTest :app:assembleDebug --console=plain
```

Backend (from its companion worktree):

```sh
../../.venv/bin/python -m pytest -q
```

Do not point the opt-in `RECORDING_SEGMENTS_TEST_POSTGRES_DSN` integration-test
setting at production. Use a disposable local database only.
