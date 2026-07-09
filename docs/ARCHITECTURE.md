# Paperorg Notes — iOS Architecture Plan

## 1. Architecture Style

**Clean Architecture + MVVM + Coordinator-lite**

```
┌─────────────────────────────────────────────────────────┐
│                      SwiftUI Views                       │
│  RecordView │ NotesView │ SearchView │ SettingsView     │
└──────────────────────────┬──────────────────────────────┘
                           │ @Observable ViewModels
┌──────────────────────────▼──────────────────────────────┐
│                    Domain / Use Cases                    │
│  ProcessRecordingUseCase │ SearchNotesUseCase │ ...      │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│                       Services                           │
│ Recording │ Transcription │ Summary │ Email │ Export    │
│ Storage │ Settings │ QualityPipeline │ Keychain         │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│              Providers (Protocol-based)                  │
│ TranscriptionProvider │ SummaryProvider │ EmailProvider  │
└──────────────────────────┬──────────────────────────────┘
                           │
┌──────────────────────────▼──────────────────────────────┐
│           Infrastructure / External APIs                 │
│ LuxASR │ OpenAI │ ElevenLabs │ Apple Speech │ Keychain  │
│ SwiftData │ FileManager │ AVFoundation │ CryptoKit      │
└─────────────────────────────────────────────────────────┘
```

**Principles:**
- UI never imports provider SDKs directly
- All async work via `async/await` + structured concurrency
- Dependency injection via `AppEnvironment` / `@Environment`
- Protocol-first for every external boundary

---

## 2. Module Layout

```
PaperorgNotes/
├── App/
│   ├── PaperorgNotesApp.swift
│   ├── AppEnvironment.swift
│   └── MainTabView.swift
├── Models/
│   ├── Note.swift
│   ├── Transcript.swift
│   ├── StructuredOutput.swift
│   └── Enums/
├── Services/
│   ├── Recording/
│   │   ├── RecordingService.swift
│   │   └── AudioQualityMonitor.swift
│   ├── Transcription/
│   │   ├── TranscriptionService.swift
│   │   ├── TranscriptionProvider.swift
│   │   ├── TranscriptionOrchestrator.swift
│   │   ├── QualityPipeline.swift
│   │   └── Providers/
│   │       ├── LuxASRProvider.swift
│   │       ├── OpenAITranscriptionProvider.swift
│   │       ├── ElevenLabsScribeProvider.swift
│   │       └── AppleSpeechProvider.swift
│   ├── Summary/
│   │   ├── SummaryService.swift
│   │   └── OpenAISummaryProvider.swift
│   ├── Email/
│   │   └── EmailService.swift
│   ├── Storage/
│   │   ├── StorageService.swift
│   │   └── EncryptionService.swift
│   ├── Settings/
│   │   └── SettingsService.swift
│   └── Export/
│       └── ExportService.swift
├── ViewModels/
├── Views/
├── Utilities/
└── Resources/
```

---

## 3. Key Services

### 3.1 RecordingService
- `AVAudioRecorder` with `.m4a` (AAC) format
- Chunked writes every 5s to temp file → rename on success
- Background audio session category `.playAndRecord`
- Publishes: duration, audio level, quality warnings
- `RecordingCheckpoint` persisted to disk for crash recovery

### 3.2 TranscriptionService
- Delegates to `TranscriptionOrchestrator`
- Selects provider via `ProviderRegistry` based on language + user preference
- Returns `TranscriptionResult` with segments, confidence, provider metadata

### 3.3 TranscriptionOrchestrator
```swift
protocol TranscriptionProvider {
    var identifier: String { get }
    var supportedLanguages: Set<AppLanguage> { get }
    func transcribe(request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

- Registry maps `(AppLanguage, ProviderPreference) → [TranscriptionProvider]` ordered by priority
- Fallback chain on error or low confidence

### 3.4 QualityPipeline
- Input: primary `TranscriptionResult`
- Steps: language validation → confidence filter → suspicious phrase detection → optional re-transcribe weak windows → merge
- Output: `QualityReport` + `FinalTranscript`

### 3.5 SummaryService
- Takes `FinalTranscript` + `OutputType` + user preferences
- Calls LLM provider (OpenAI) with strict JSON schema
- Validates response; rejects hallucinated entities not in transcript

### 3.6 StorageService
- SwiftData for metadata + transcript text
- FileManager for audio files in `Application Support/Recordings/`
- Optional AES-GCM encryption at rest via `EncryptionService`

### 3.7 SettingsService
- UserDefaults for non-sensitive prefs
- Keychain for API keys via `KeychainService`
- `@Observable` for SwiftUI binding

### 3.8 EmailService
- Builds `EmailPayload` from note + settings
- Presents `MFMailComposeViewController` via UIViewControllerRepresentable
- Never sends silently — always user-visible Mail sheet unless "always send" with pre-filled draft

### 3.9 ExportService
- Generates TXT, MD, PDF (via PDFKit), RTF
- Package builder for transcript + audio zip

---

## 4. Data Flow: Record → Ready

```
User taps Stop
    │
    ▼
RecordingService.finalize() → audio URL
    │
    ▼
StorageService.createNote(draft)
    │
    ▼
TranscriptionOrchestrator.transcribe(audio, language)
    │  ├─ Primary provider
    │  └─ Fallback if needed
    ▼
QualityPipeline.process(result)
    │
    ▼
StorageService.saveRawTranscript()
    │
    ▼
SummaryService.generate(transcript, outputType)
    │
    ▼
StorageService.saveStructuredOutput()
    │
    ▼
EmailService.prepareIfConfigured(note) → optional Mail sheet
    │
    ▼
UI: Ready state
```

---

## 5. Concurrency Model

| Operation | Executor |
|-----------|----------|
| Recording / audio I/O | Main + dedicated serial queue |
| Network (transcription) | `URLSession` background |
| SwiftData writes | `@ModelActor` or main actor |
| Quality pipeline | TaskGroup for parallel segment re-transcription |

---

## 6. Error Handling

- Typed errors: `RecordingError`, `TranscriptionError`, `SummaryError`
- User-facing: localized `LocalizedError` descriptions
- Retry with exponential backoff for network providers
- Partial success: save audio even if transcription fails; allow retry

---

## 7. Testing Strategy

- **Unit:** Provider selection, quality pipeline, export formatting
- **Integration:** Mock providers with fixture JSON
- **UI:** XCTest UI for record flow smoke test
- **Benchmark:** Luxembourgish test set script (see TEST_PLAN.md)

---

## 8. Dependencies (MVP)

| Dependency | Purpose |
|------------|---------|
| SwiftUI + SwiftData | UI + persistence |
| AVFoundation | Recording/playback |
| PDFKit | PDF export |
| CryptoKit | Encryption |
| Security.framework | Keychain |
| MessageUI | Email compose |

No third-party SDKs required for MVP — all providers via REST.

---

## 9. Future Extensions

- **Phase 2:** Live transcription via WebSocket (OpenAI Realtime / ElevenLabs streaming)
- **Phase 2:** On-device Whisper via Core ML for offline EN
- **Phase 3:** CloudKit sync with encrypted blobs
- **Phase 3:** Correction learning → custom vocabulary store
