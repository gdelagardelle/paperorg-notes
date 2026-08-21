# App Store Privacy — Nutrition Labels & Metadata

Use this when completing **App Store Connect → App Privacy** and listing metadata.

**Privacy policy URL:** `https://gdelagardelle.github.io/paperorg-notes/privacy.html`  
(Update if you host elsewhere.)

---

## Data linked to the user

| Data type | Collected | Purpose | Notes |
|-----------|-----------|---------|-------|
| **User ID / Device ID** | Yes (cloud processing) | App functionality | Random device UUID sent to Paperorg backend to enforce Free and Pro usage limits |
| **Purchase history** | Yes (Pro) | App functionality | StoreKit subscription; verified server-side |
| **Audio data** | Yes (cloud processing) | App functionality | Sent to Paperorg and enabled AI processors for transcription |
| **Other user content** | Yes (cloud processing) | App functionality | Transcript text sent to Paperorg and enabled AI processors for requested summaries; originals remain on device |
| **Email address** | Optional | App functionality | Only if user configures SMTP recipients in Settings |

## Data not collected

- Location
- Contacts
- Browsing history
- Advertising data
- Health/fitness

---

## Third-party data sharing (included Free and Pro cloud processing)

When the user accepts the in-app privacy policy and uses the included Free allowance or Pro:

| Recipient | Data | Purpose |
|-----------|------|---------|
| Paperorg backend | Audio, transcript text, random device ID, monthly usage | Cloud transcription and summaries; enforce usage limits |
| OpenAI / ElevenLabs / LuxASR | Audio and/or transcript text (via Paperorg backend) | Transcription & summarisation |
| Apple | Purchase data (Pro only) | Subscription billing |

## Third-party data sharing (optional personal keys)

When a user adds their own provider key and consents to the provider in Settings:

| Recipient | Data | Purpose |
|-----------|------|---------|
| OpenAI | Audio, transcript text | Direct transcription & summarisation |
| ElevenLabs | Audio | Direct transcription |
| LuxASR | Audio | Direct transcription (Luxembourgish) |

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
Record meetings and voice notes in Lëtzebuergesch, French, German, and more. AI summaries, action items, and PDF export — 30 Free cloud minutes each month, with Pro for more.

**Description (opening):**  
Paperorg Notes turns voice into structured notes. Record on your iPhone, transcribe in Luxembourgish and multiple languages, and get meeting summaries, action items, and email drafts.

**Free plan:** 30 minutes/month of cloud transcription and AI summaries. No API key or sign-in required; personal keys are optional.
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
- Free and Pro cloud processing require the Paperorg backend; personal keys are an optional direct-processing path

---

*Last updated: 2026-07-12*
