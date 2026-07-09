# Paperorg Notes

A production-grade native iOS app for voice recording, multilingual transcription, and AI-structured notes — with **Luxembourgish (Lëtzebuergesch) as a first-class language**.

## Features (MVP)

- **Record** — one-tap recording with pause/resume, background support, crash-safe checkpoints
- **Transcribe** — provider abstraction supporting LuxASR, OpenAI, ElevenLabs Scribe, Apple Speech
- **Quality pipeline** — confidence flags, suspicious phrase detection, fallback re-transcription
- **AI structuring** — meeting notes, brainstorms, action items, decisions, email drafts
- **Library & search** — local SwiftData storage with full-text search
- **Export & email** — TXT, Markdown, PDF, RTF; Mail compose with attachments
- **Privacy/GDPR** — consent flows, data export, delete all, Keychain API keys

## Supported Languages

| Language | Code | Primary Provider |
|----------|------|------------------|
| Lëtzebuergesch | `lb` | LuxASR → ElevenLabs → OpenAI |
| Deutsch | `de` | OpenAI → ElevenLabs |
| Français | `fr` | OpenAI → ElevenLabs |
| English | `en` | OpenAI → Apple Speech → ElevenLabs |
| Português | `pt` | OpenAI → ElevenLabs |

## Requirements

- Xcode 16+
- iOS 17.0+
- Swift 5.9+
- API keys for transcription providers (BYOK model)

## Getting Started

### 1. Generate Xcode Project

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

Generate the project:

```bash
cd "Paperorg Notes"
xcodegen generate
open PaperorgNotes.xcodeproj
```

### 2. Configure Signing

In Xcode, set your **Development Team** for the `PaperorgNotes` target.

### 3. Add API Keys

Launch the app → **Settings** → enter API keys and consent to providers:

- **OpenAI** — required for DE/FR/EN/PT transcription and AI summaries
- **ElevenLabs** — recommended fallback, especially for Luxembourgish
- **LuxASR** — best Luxembourgish accuracy ([luxasr.uni.lu](https://luxasr.uni.lu))

### 4. Run Luxembourgish Benchmark

Add test clips to `TestFixtures/Luxembourgish/` (`.m4a` + matching `.txt` reference transcript), then:

```bash
export OPENAI_API_KEY=sk-...
export ELEVENLABS_API_KEY=...
chmod +x Scripts/benchmark_luxembourgish.sh
./Scripts/benchmark_luxembourgish.sh
```

## Architecture

```
SwiftUI Views → ViewModels/UseCases → Services → TranscriptionProvider protocol → REST APIs
                                      ↓
                                  SwiftData + FileManager
```

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for full details.

## Documentation

| Document | Description |
|----------|-------------|
| [PRODUCT_SPEC.md](docs/PRODUCT_SPEC.md) | Full product specification |
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | iOS architecture plan |
| [DATA_MODEL.md](docs/DATA_MODEL.md) | SwiftData entities & DTOs |
| [API_PROVIDER_STRATEGY.md](docs/API_PROVIDER_STRATEGY.md) | ASR provider strategy & LB benchmark plan |
| [UI_FLOW.md](docs/UI_FLOW.md) | Screen flows & design system |
| [MVP_TASK_LIST.md](docs/MVP_TASK_LIST.md) | Sprint task checklist |
| [SECURITY_GDPR_CHECKLIST.md](docs/SECURITY_GDPR_CHECKLIST.md) | Privacy compliance |
| [TEST_PLAN.md](docs/TEST_PLAN.md) | Unit, integration, benchmark tests |
| [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | 12-week delivery plan |
| [RISKS_AND_OPEN_QUESTIONS.md](docs/RISKS_AND_OPEN_QUESTIONS.md) | Risks & decisions |

## Project Structure

```
PaperorgNotes/
├── App/                    # Entry point, DI, tab navigation
├── Models/                 # SwiftData models, DTOs, enums
├── Services/
│   ├── Recording/          # AVAudioRecorder, playback
│   ├── Transcription/      # Provider protocol, orchestrator, quality pipeline
│   │   └── Providers/      # LuxASR, OpenAI, ElevenLabs, Apple
│   ├── Summary/            # OpenAI structuring
│   ├── Email/              # MFMailComposeViewController
│   ├── Export/             # PDF, MD, TXT, RTF
│   ├── Storage/            # Files, encryption, GDPR export
│   └── Settings/           # UserDefaults + Keychain
├── UseCases/               # ProcessRecordingUseCase
├── Views/                  # SwiftUI screens
└── Utilities/              # Theme, formatters
```

## Luxembourgish Strategy

Based on research (University of Luxembourg LuxASR project, ElevenLabs FLEURS benchmarks, OpenAI limitations):

1. **LuxASR** — purpose-built Luxembourgish ASR with diarization; best accuracy
2. **ElevenLabs Scribe v2** (`ltz`) — strong fallback with word timestamps
3. **OpenAI gpt-4o-transcribe** — last resort; often misdetects LB as DE/NL

The quality pipeline automatically flags low-confidence segments, attempts fallback re-transcription, and marks unresolved text as `[unclear]` — never inventing missing words.

## License

Proprietary — Paperorg Notes. Contact for licensing.
