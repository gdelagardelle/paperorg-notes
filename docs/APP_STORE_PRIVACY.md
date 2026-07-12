# App Store Privacy — Nutrition Labels & Metadata

Use this when completing **App Store Connect → App Privacy** and listing metadata.

**Privacy policy URL:** `https://gdelagardelle.github.io/paperorg-notes/privacy.html`  
(Update if you host elsewhere.)

---

## Data linked to the user

| Data type | Collected | Purpose | Notes |
|-----------|-----------|---------|-------|
| **User ID** | Yes (Pro) | App functionality | Random device UUID sent to Paperorg backend |
| **Purchase history** | Yes (Pro) | App functionality | StoreKit subscription; verified server-side |
| **Audio data** | Yes | App functionality | Recorded on device; sent to AI providers for transcription |
| **Other user content** | Yes | App functionality | Transcripts, summaries (stored on device) |
| **Email address** | Optional | App functionality | Only if user configures SMTP recipients in Settings |

## Data not collected

- Location
- Contacts
- Browsing history
- Advertising data
- Health/fitness

---

## Third-party data sharing (Free plan)

When user configures BYOK and consents per provider:

| Recipient | Data | Purpose |
|-----------|------|---------|
| OpenAI | Audio, transcript text | Transcription & summarisation |
| ElevenLabs | Audio | Transcription |
| LuxASR | Audio | Transcription (Luxembourgish) |

## Third-party data sharing (Pro plan)

| Recipient | Data | Purpose |
|-----------|------|---------|
| Paperorg backend | Audio, device ID, usage minutes | Pro transcription proxy |
| OpenAI / ElevenLabs / LuxASR | Audio (via our backend) | Transcription & summarisation |
| Apple | Purchase data | Subscription billing |

---

## Tracking

**No** — the app does not track users across apps or websites for advertising.

`NSUserTrackingUsageDescription` is **not** required.

---

## Encryption

`ITSAppUsesNonExemptEncryption = NO` — standard HTTPS only.

---

## Suggested App Store description (EN)

**Subtitle:** Voice notes with Luxembourgish transcription

**Promotional text (170 chars):**  
Record meetings and voice notes in Lëtzebuergesch, French, German, and more. AI summaries, action items, and PDF export — Free with your keys or Pro with everything included.

**Description (opening):**  
Paperorg Notes turns voice into structured notes. Record on your iPhone, transcribe in Luxembourgish and multiple languages, and get meeting summaries, action items, and email drafts.

**Free plan:** Use your own OpenAI and ElevenLabs API keys.  
**Paperorg Pro:** 600 minutes/month included — no API setup required.

**Keywords:** voice notes, transcription, Luxembourgish, Lëtzebuergesch, meeting notes, AI summary, dictation, minutes

---

## French metadata (FR)

**Subtitle:** Notes vocales avec transcription luxembourgeoise

**Keywords:** notes vocales, transcription, luxembourgeois, lëtzebuergesch, compte rendu, réunion

---

## German metadata (DE)

**Subtitle:** Sprachnotizen mit luxemburgischer Transkription

**Keywords:** Sprachnotizen, Transkription, Luxemburgisch, Lëtzebuergesch, Meeting, Protokoll

---

## Review notes for Apple

- Microphone used for voice recording only
- Pro subscription: `com.paperorg.notes.pro.monthly`
- Sandbox test account available on request
- Backend URL: `[your production URL]` — required for Pro transcription
- Free tier works without backend (BYOK direct to OpenAI)

---

*Last updated: 2026-07-12*
