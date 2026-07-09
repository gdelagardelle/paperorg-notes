# Paperorg Notes — MVP Task List

## Phase 1: Foundation (Week 1-2)

- [x] Product specification
- [x] Architecture plan
- [x] Data model design
- [ ] Xcode project setup, bundle ID, signing
- [ ] SwiftData models: Note, TranscriptSegment
- [ ] AppEnvironment + dependency injection
- [ ] MainTabView navigation shell
- [ ] SettingsService + KeychainService
- [ ] Privacy consent flow

## Phase 2: Recording (Week 2-3)

- [ ] RecordingService with AVAudioRecorder
- [ ] Pause / resume / stop
- [ ] Background audio session configuration
- [ ] Info.plist: UIBackgroundModes audio, microphone usage
- [ ] Crash-safe chunked audio writes
- [ ] Recording checkpoint recovery
- [ ] AudioQualityMonitor (RMS/clipping)
- [ ] RecordView UI with duration + quality warning

## Phase 3: Transcription (Week 3-5)

- [ ] TranscriptionProvider protocol
- [ ] ProviderRegistry with language routing
- [ ] OpenAITranscriptionProvider
- [ ] ElevenLabsScribeProvider
- [ ] LuxASRProvider (queued job flow)
- [ ] AppleSpeechProvider (EN fallback)
- [ ] TranscriptionOrchestrator with fallback chain
- [ ] ProcessingView with stage progress
- [ ] Provider consent gates

## Phase 4: Quality Pipeline (Week 5-6)

- [ ] QualityPipeline service
- [ ] Confidence threshold detection
- [ ] Suspicious phrase heuristics
- [ ] Mixed-language segment detection
- [ ] Weak segment re-transcription
- [ ] Uncertainty markers in UI
- [ ] Luxembourgish benchmark script + fixtures

## Phase 5: AI Structuring (Week 6-7)

- [ ] SummaryService + OpenAI provider
- [ ] OutputType templates (meeting, brainstorm, etc.)
- [ ] StructuredOutput JSON schema validation
- [ ] Anti-hallucination checks
- [ ] NoteDetailView: Summary + Actions tabs

## Phase 6: Storage & Library (Week 7-8)

- [ ] StorageService (SwiftData + FileManager)
- [ ] Notes list view with filters
- [ ] Note detail with segment playback
- [ ] Manual transcript correction
- [ ] Tags + favorites + projects
- [ ] Search with full-text

## Phase 7: Export & Email (Week 8-9)

- [ ] ExportService: TXT, MD, PDF, RTF
- [ ] Audio share
- [ ] Transcript + audio package (zip)
- [ ] EmailService + MFMailComposeViewController
- [ ] Email settings UI

## Phase 8: Privacy & Security (Week 9-10)

- [ ] EncryptionService (AES-GCM for audio option)
- [ ] GDPR export all data
- [ ] Delete all data
- [ ] Delete audio after transcription option
- [ ] Auto-delete after N days
- [ ] Face ID lock

## Phase 9: Polish & Ship (Week 10-12)

- [ ] Error states + retry flows
- [ ] Empty states
- [ ] App icon + launch screen
- [ ] TestFlight build
- [ ] App Store metadata (EN, FR, DE)
- [ ] Privacy nutrition labels

---

## Phase 2 Backlog (Post-MVP)

- [ ] Live transcription
- [ ] Speaker diarization UI
- [ ] Multi-provider comparison mode
- [ ] Correction learning / custom vocabulary
- [ ] CloudKit sync
- [ ] Team / workspace mode
- [ ] Calendar integration
- [ ] Auto meeting title detection
- [ ] Widget for quick record
- [ ] watchOS companion

---

## Definition of Done (MVP)

1. User can record audio with pause/resume in background
2. Audio survives app kill mid-recording (checkpoint)
3. Transcription works for all 5 languages with provider fallback
4. Luxembourgish uses LuxASR → ElevenLabs fallback chain
5. Quality pipeline flags low-confidence segments
6. User can replay audio per sentence and edit transcript
7. Structured summary generated for all output types
8. Notes searchable and filterable locally
9. Export to TXT, MD, PDF; share audio
10. Email compose with configured recipients
11. GDPR consent, export, delete
12. API keys stored in Keychain
