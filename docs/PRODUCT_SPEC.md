# Paperorg Notes — Product Specification

**Version:** 1.0 MVP  
**Platform:** iOS 17+  
**Codename:** Paperorg Notes  
**Last updated:** July 2026

---

## 1. Vision

Paperorg Notes is a premium native iOS app that captures spoken thoughts, meetings, brainstorms, and conversations, then transforms them into accurate transcripts and structured, actionable documents — with **Luxembourgish (Lëtzebuergesch) as a first-class language**, not an afterthought.

The app serves professionals, teams, and multilingual users in Luxembourg and beyond who need reliable transcription across **Luxembourgish, German, French, English, and Portuguese**.

---

## 2. Target Users

| Persona | Need |
|---------|------|
| **Luxembourg professional** | Meeting notes in LB/FR/DE mix, GDPR-aware |
| **Consultant / freelancer** | Client call summaries, action items, email drafts |
| **Team lead** | Brainstorm capture, decisions, follow-ups |
| **Multilingual household / expat** | Voice memos in PT/FR/EN with clean export |
| **Journalist / researcher** | Interview transcription with manual correction |

---

## 3. Supported Languages

| Language | ISO Code | Primary Provider (MVP) | Fallback |
|----------|----------|------------------------|----------|
| Luxembourgish | `lb` | LuxASR | ElevenLabs Scribe → OpenAI |
| German | `de` | OpenAI gpt-4o-transcribe | ElevenLabs Scribe |
| French | `fr` | OpenAI gpt-4o-transcribe | ElevenLabs Scribe |
| English | `en` | OpenAI gpt-4o-transcribe | Apple Speech (on-device) |
| Portuguese | `pt` | OpenAI gpt-4o-transcribe | ElevenLabs Scribe |

Language can be **auto-detected** or **manually selected** before/during recording.

---

## 4. Core User Journeys

### 4.1 Quick Voice Note
1. Open app → tap Record
2. Speak → tap Stop
3. Progress: Transcribing → Summarizing → Ready
4. Review transcript + summary + action items
5. Optional: send to configured email

### 4.2 Meeting Recording
1. Select language (or auto-detect)
2. Choose output type: **Meeting notes**
3. Record with pause/resume; background-safe
4. Receive structured output: summary, decisions, action items, open questions
5. Export PDF or email to team

### 4.3 Luxembourgish Brainstorm
1. Set language to Lëtzebuergesch
2. Record brainstorm session
3. Quality pipeline runs LuxASR + confidence check
4. Low-confidence segments highlighted; user can replay & correct
5. Structured brainstorm: key ideas, themes, next steps

### 4.4 Search & Archive
1. Browse Notes library
2. Full-text search across transcripts
3. Filter by language, date, tag, project
4. Open note → replay audio at sentence level

---

## 5. Feature Specification

### 5.1 Recording
- One-tap record / pause / resume / stop
- Background recording with `AVAudioSession` + UIBackgroundModes
- Crash-safe incremental audio write (chunked `.m4a`)
- Duration display, waveform optional (Phase 2)
- Audio quality warning (RMS/clipping detection)
- Original audio always saved locally (unless user opts to delete)

### 5.2 Transcription
- Post-recording transcription (MVP)
- Live transcription (Phase 2)
- Timestamped segments with word-level alignment where provider supports
- Speaker diarization when provider supports (LuxASR, ElevenLabs, OpenAI diarize)
- Confidence scores per segment/word
- Raw transcript stored immutably; corrected transcript stored separately

### 5.3 AI Structuring
After transcription, generate based on **output type**:

| Output Type | Generated Sections |
|-------------|-------------------|
| Meeting notes | Summary, attendees/topics, decisions, actions, questions |
| Brainstorm | Key ideas, themes, wild ideas, next steps |
| Personal memo | Short summary, key points |
| Client call | Summary, commitments, follow-ups, email draft |
| Interview | Q&A structure, quotes, themes |
| Task list | Action items only |
| Clean résumé | Polished prose summary |
| Raw transcript | Transcript only, no AI structuring |

Sections always labeled as AI-generated; never silently invent missing content.

### 5.4 Search & Archive
- Local library with SwiftData
- Full-text search (transcript + summary + title + tags)
- Filters: language, date range, tag, project, favorite
- Auto-title from first sentence or AI-generated title
- Manual title override

### 5.5 Export & Sharing
- Plain text, Markdown, PDF, RTF (Word-compatible)
- Email body composition
- Audio file share
- Bundle: transcript + audio + metadata JSON

### 5.6 Email Settings
- Multiple recipient addresses
- Policies: always send / ask before send / never
- Content: summary only / full transcript / both
- Attachments: audio, PDF, Markdown
- Uses `MFMailComposeViewController` (device Mail) — no server-side email in MVP

### 5.7 Privacy & GDPR
- First-launch privacy consent screen
- Per-provider disclosure (what leaves device)
- Toggle: delete audio after transcription
- Toggle: keep audio / auto-delete after N days
- Export all data (JSON + audio zip)
- Delete all data
- API keys in Keychain
- No training on user data unless explicit opt-in (Phase 2)
- Face ID app lock (optional)

### 5.8 Settings
- Default language, auto-detect on/off
- Preferred transcription provider per language
- Email recipients & auto-send policy
- Default output format & note style
- Summary length (short / detailed)
- Keep audio / retention days
- Cloud sync (Phase 2)
- Face ID lock
- App UI language (EN, FR, DE, LB, PT)

### 5.9 Quality Control Pipeline
1. Initial transcription via primary provider
2. Language validation (detect mismatches)
3. Confidence threshold check
4. Flag suspicious phrases (repeated chars, empty segments, language drift)
5. Detect mixed-language segments
6. Re-transcribe weak segments with fallback provider
7. Compare outputs if multi-provider mode enabled
8. Merge into final transcript with `[unclear]` / confidence markers
9. Never fill gaps with invented words

---

## 6. Non-Goals (MVP)

- Cloud sync / team workspaces
- Calendar integration
- Real-time multi-speaker live captions
- Server-side email delivery
- On-device LLM (uses API for structuring in MVP)

---

## 7. Success Metrics

| Metric | Target |
|--------|--------|
| Recording crash/data loss | 0% |
| LB word error rate (benchmark set) | < 15% WER with LuxASR primary |
| Time to transcript (5 min audio) | < 90 seconds |
| User correction rate | Track; aim to decrease over time |
| GDPR consent completion | 100% before first API call |

---

## 8. App Identity

- **Display name:** Paperorg Notes
- **Bundle ID:** `com.paperorg.notes`
- **Primary accent:** Deep teal / warm paper tones
- **Tone:** Premium, calm, trustworthy, multilingual
