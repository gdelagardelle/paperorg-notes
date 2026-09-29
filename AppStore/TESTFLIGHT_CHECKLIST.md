# App Store Connect — TestFlight Checklist

## Before Upload

- [ ] Xcode: **Product → Archive** (Release configuration)
- [ ] Validate App in Organizer
- [ ] Upload to App Store Connect
- [ ] App Store Connect: create app record `com.paperorg.voicenotes`

## Required in App Store Connect

| Field | Value |
|-------|-------|
| App name | Paperorg Notes |
| Subtitle | Meetings done. Notes sent. |
| Primary category | Productivity |
| Secondary category | Business |
| Privacy Policy URL | *(required — host before external TestFlight)* |
| Age rating | 4+ (no restricted content) |

## App Icon

1024×1024 PNG uploaded automatically from `AppIcon.appiconset/AppIcon-1024.png`.

## Screenshots (required for external TestFlight / App Store)

Minimum iPhone 6.7" (1290×2796) — capture from simulator:
- Record screen
- Note detail (transcript + summary)
- Notes library
- Settings (privacy section)

## Privacy Nutrition Labels

Declare in App Store Connect:
- **Audio Data** — linked to user: No, used for app functionality
- **User Content** (transcripts) — linked to user: No, used for app functionality
- **Tracking** — No

## Export Compliance

When uploading, answer:
- **Uses encryption?** Yes (HTTPS + optional local AES-GCM)
- **Exempt?** Yes — standard HTTPS only qualifies for exemption (ITSAppUsesNonExemptEncryption = NO)

Already set via Info.plist key if needed.

## TestFlight Notes (What to Test)

```
Paperorg Notes MVP — please test:
1. Record a voice note (LB, FR, DE, EN, PT)
2. Verify transcript + summary appear
3. Search notes
4. Export PDF / email
5. Privacy: delete all data in Settings
Report any transcription quality issues for Luxembourgish especially.
```

## Keywords (suggestion)

```
voice notes, transcription, meeting notes, luxembourgish, dictation, AI summary, brainstorm, multilingual
```

## Description (draft)

See **`AppStore/METADATA.md`** for full EN/FR/DE descriptions, promotional text, keywords, and screenshot captions (Grand Slam / Meeting Closure offer).
