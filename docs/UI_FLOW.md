# Paperorg Notes — UI Flow

## 1. Navigation Structure

```
TabView
├── Record (mic.fill)
├── Notes (doc.text.fill)
├── Search (magnifyingglass)
└── Settings (gearshape.fill)
```

First launch → **PrivacyConsentView** (full screen modal, must accept to proceed)

Optional → **FaceIDLockView** on app foreground if enabled

---

## 2. Screen Flows

### 2.1 Record Tab (Home)

```
┌─────────────────────────────────────┐
│  Paperorg Notes          [LB ▾]    │  ← language picker
├─────────────────────────────────────┤
│                                     │
│         ┌─────────────┐             │
│         │   ● REC     │             │  ← large record button
│         │   00:00     │             │  ← duration
│         └─────────────┘             │
│                                     │
│  Output: Meeting notes ▾            │  ← output type picker
│                                     │
│  ⚠ Low microphone input             │  ← quality warning (conditional)
│                                     │
│  Recent                             │
│  ┌─────────────────────────────┐   │
│  │ Team standup · 12 min · LB  │   │
│  │ Brainstorm Q3 · 8 min · DE  │   │
│  └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**States:**
- Idle → tap Record → Recording (pulse animation, pause/stop)
- Recording → Pause/Resume available
- Stop → navigate to ProcessingView

### 2.2 Processing View (Modal / Push)

```
┌─────────────────────────────────────┐
│  Processing your recording          │
├─────────────────────────────────────┤
│  ✓ Saved audio                      │
│  ● Transcribing…          [====    ]│
│  ○ Checking quality                 │
│  ○ Summarizing                      │
│                                     │
│  Using LuxASR for Lëtzebuergesch    │
└─────────────────────────────────────┘
```

Stages map to `ProcessingStage` enum.

### 2.3 Note Detail View

```
┌─────────────────────────────────────┐
│  ← Team Standup        ♡  •••     │
├─────────────────────────────────────┤
│  [Transcript] [Summary] [Actions]   │  ← segmented control
├─────────────────────────────────────┤
│  ▶ 0:42  Mir hunn haut mat dem...  │  ← tap ▶ replays segment
│  ▶ 1:15  D'Projet muss bis...      │
│     ⚠ unclear (0.42 confidence)    │  ← low confidence highlight
├─────────────────────────────────────┤
│  [Edit] [Export] [Email] [Share]    │
└─────────────────────────────────────┘
```

**Transcript editing:**
- Tap segment → inline edit
- Saves to `correctedTranscript`; preserves `rawTranscript`
- `[unclear]` markers shown in amber

### 2.4 Notes Tab

```
┌─────────────────────────────────────┐
│  Notes                    + Filter  │
├─────────────────────────────────────┤
│  Today                              │
│  ┌─────────────────────────────┐   │
│  │ ♡ Team Standup              │   │
│  │ LB · 12 min · Meeting       │   │
│  │ 3 action items              │   │
│  └─────────────────────────────┘   │
│  Yesterday                          │
│  ...                                │
└─────────────────────────────────────┘
```

Swipe actions: Favorite, Delete, Export

### 2.5 Search Tab

```
┌─────────────────────────────────────┐
│  🔍 Search transcripts…             │
├─────────────────────────────────────┤
│  Filters: Language | Date | Tag     │
├─────────────────────────────────────┤
│  Results (12)                       │
│  "...Projet muss bis Freideg..."    │
│  Team Standup · Jul 8               │
└─────────────────────────────────────┘
```

### 2.6 Settings Tab

Sections:
1. **Language** — default, auto-detect
2. **Transcription** — provider per language, API keys
3. **Output** — default type, summary length
4. **Email** — recipients, policy, content, attachments
5. **Privacy** — keep audio, retention, delete all, export data
6. **Security** — Face ID lock
7. **About** — version, privacy policy, provider info

### 2.7 Privacy Consent (First Launch)

```
┌─────────────────────────────────────┐
│  Your privacy matters               │
├─────────────────────────────────────┤
│  Paperorg Notes records audio on    │
│  your device. Transcription may     │
│  send audio to third-party services │
│  you configure.                     │
│                                     │
│  ☐ I understand and agree           │
│                                     │
│  [View Privacy Policy]              │
│                                     │
│  [Continue]                         │
└─────────────────────────────────────┘
```

### 2.8 Provider Consent (Per Provider)

Shown before first API call to each provider:
- Provider name, data handling, country
- Toggle: "Allow sending audio to [Provider]"

---

## 3. Design System

| Token | Value |
|-------|-------|
| Primary | `#1A6B6B` (deep teal) |
| Background | `#FAF8F5` (warm paper) |
| Surface | `#FFFFFF` |
| Text primary | `#1C1C1E` |
| Text secondary | `#6B6B6B` |
| Warning | `#E8A838` |
| Error | `#D64545` |
| Unclear highlight | `#FFF3CD` |
| Font | SF Pro (system) |
| Corner radius | 16pt cards, 12pt buttons |
| Record button | 88pt circle, red when recording |

**Motion:**
- Record button: subtle scale pulse when active
- Processing: linear progress with stage checkmarks
- Tab transitions: default SwiftUI

---

## 4. Accessibility

- VoiceOver labels on all controls
- Dynamic Type support
- High contrast mode compatible
- Haptic feedback on record start/stop

---

## 5. Localization

App UI strings in: EN, FR, DE, LB (best effort), PT

Transcription output language = spoken language (not translated unless export option selected).
