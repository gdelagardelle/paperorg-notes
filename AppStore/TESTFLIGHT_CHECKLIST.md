# App Store Connect — TestFlight Checklist

## Before Upload

- [ ] Xcode: **Product → Archive** (Release configuration)
- [ ] Validate App in Organizer
- [ ] Upload to App Store Connect
- [ ] App Store Connect: create app record `com.paperorg.notes`

## Required in App Store Connect

| Field | Value |
|-------|-------|
| App name | Paperorg Notes |
| Subtitle | Voice notes & transcription |
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

```
Paperorg Notes turns your voice into structured notes.

Record meetings, brainstorms, and voice memos — then get an accurate transcript, summary, action items, and decisions. Built for multilingual professionals with first-class support for Lëtzebuergesch, German, French, English, and Portuguese.

• One-tap recording with background support
• AI-structured meeting notes and brainstorms
• Search your entire transcript library
• Export PDF, Markdown, or email
• GDPR-aware: you control your data and providers

Transcription uses providers you configure (OpenAI, ElevenLabs, LuxASR). Audio is stored on your device unless you choose otherwise.
```
