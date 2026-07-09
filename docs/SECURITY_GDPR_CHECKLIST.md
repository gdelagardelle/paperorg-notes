# Paperorg Notes — Security & GDPR Checklist

## 1. Data Classification

| Data Type | Sensitivity | Storage | Encryption |
|-----------|-------------|---------|------------|
| Audio recordings | High | Local filesystem | Optional AES-GCM |
| Transcripts | High | SwiftData | OS file protection |
| API keys | Critical | Keychain | Keychain native |
| Settings | Low | UserDefaults | None required |
| Structured summaries | Medium | SwiftData | OS file protection |

---

## 2. GDPR Compliance Checklist

### Lawful Basis & Transparency
- [ ] Privacy policy accessible in-app and on website
- [ ] First-launch consent screen before any data processing
- [ ] Clear explanation of which data leaves the device
- [ ] Per-provider consent before sending audio to third parties
- [ ] No pre-checked consent boxes
- [ ] Privacy policy lists all sub-processors (OpenAI, ElevenLabs, LuxASR)

### Data Minimization
- [ ] Only audio necessary for transcription is sent
- [ ] Option to delete audio immediately after transcription
- [ ] Auto-delete audio after configurable retention period
- [ ] No collection of contacts, location, or analytics without consent (MVP: no analytics)

### User Rights
- [ ] **Right of access:** Export all data (JSON + audio ZIP)
- [ ] **Right to erasure:** Delete all data (notes, audio, settings, keys)
- [ ] **Right to rectification:** Manual transcript correction stored separately
- [ ] **Right to portability:** Export in standard formats (TXT, MD, JSON)
- [ ] **Right to object:** Can disable cloud providers; use on-device only (EN via Apple Speech)

### Data Processing Agreements
- [ ] Document DPA requirements for each API provider
- [ ] LuxASR: contact Uni Luxembourg for commercial terms
- [ ] OpenAI: API data not used for training (verify current policy)
- [ ] ElevenLabs: verify enterprise/data retention terms

### Breach Preparedness
- [ ] No server-side storage in MVP (reduces breach surface)
- [ ] Document incident response plan for future cloud sync

---

## 3. Security Checklist

### At Rest
- [ ] API keys in Keychain (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- [ ] Audio files in Application Support with `NSFileProtectionComplete`
- [ ] SwiftData store protected by iOS Data Protection
- [ ] Optional user-enabled encryption for audio files

### In Transit
- [ ] All API calls over HTTPS (TLS 1.2+)
- [ ] Certificate pinning (Phase 2 — optional for MVP)
- [ ] No API keys in URLs or logs

### Authentication
- [ ] Face ID / Touch ID app lock (optional)
- [ ] No user accounts in MVP (device-bound data)

### Code Security
- [ ] No hardcoded API keys
- [ ] No secrets in git repository
- [ ] `.gitignore` excludes `.env`, keys, local configs
- [ ] Debug logging strips audio content and API keys

### App Store Privacy
- [ ] Privacy Nutrition Labels: Audio Data, User Content
- [ ] Declare data linked to user: No (MVP — no accounts)
- [ ] Declare data used for tracking: No

---

## 4. Third-Party Data Flow Disclosure

| Provider | Data Sent | Purpose | Retention (verify) |
|----------|-----------|---------|-------------------|
| LuxASR | Audio bytes | Transcription | Per Uni Luxembourg policy |
| OpenAI | Audio + transcript text | Transcription + summary | API default retention |
| ElevenLabs | Audio bytes | Transcription | Per ElevenLabs policy |
| Apple Speech | Audio (on-device) | EN transcription | Not sent off-device |

User must consent to each provider before first use.

---

## 5. Audio Deletion Policy

| Setting | Behavior |
|---------|----------|
| Keep audio (default ON) | Audio retained until user deletes note |
| Delete after transcription | Audio file removed after successful transcript save |
| Auto-delete after N days | Background task purges old audio files |
| Delete note | Removes audio + all associated data |
| Delete all data | Wipes library, audio, settings, keychain keys |

---

## 6. Pre-Release Audit

- [ ] Run `strings` on binary — no leaked keys
- [ ] Verify microphone permission string is accurate
- [ ] Verify background audio justification for App Review
- [ ] Test GDPR export produces complete data set
- [ ] Test delete all data leaves no residual files
- [ ] Legal review of privacy policy (recommended)
