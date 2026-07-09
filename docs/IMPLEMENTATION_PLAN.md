# Paperorg Notes — Implementation Plan

## Timeline Overview (12 Weeks to MVP)

```
Week  1-2   ████ Foundation + Recording
Week  3-5   ██████ Transcription + Providers
Week  5-6   ████ Quality Pipeline
Week  6-7   ███ AI Structuring
Week  7-8   ████ Library + Search
Week  8-9   ███ Export + Email
Week  9-10  ███ Privacy + Security
Week 10-12  ████ Polish + TestFlight
```

---

## Sprint Breakdown

### Sprint 1 (Week 1-2): Skeleton + Record
**Goal:** User can record and save audio locally.

**Deliverables:**
- Xcode project with SwiftUI tab navigation
- SwiftData Note model (draft status)
- RecordingService with background support
- RecordView with timer and quality warning
- Privacy consent gate

**Exit criteria:** 5-minute background recording saves playable `.m4a`.

---

### Sprint 2 (Week 3-4): Transcription Core
**Goal:** Audio transcribed via OpenAI for DE/FR/EN/PT.

**Deliverables:**
- TranscriptionProvider protocol + registry
- OpenAITranscriptionProvider
- TranscriptionOrchestrator
- ProcessingView with progress stages
- Store raw transcript + segments

**Exit criteria:** Stop recording → see timestamped transcript for English test clip.

---

### Sprint 3 (Week 4-5): Luxembourgish Providers
**Goal:** LB transcription with LuxASR + ElevenLabs.

**Deliverables:**
- LuxASRProvider (queued API)
- ElevenLabsScribeProvider
- LB fallback chain in registry
- Provider consent UI
- API key settings screens

**Exit criteria:** Luxembourgish test clip transcribed via LuxASR or ElevenLabs fallback.

---

### Sprint 4 (Week 5-6): Quality Pipeline
**Goal:** Confidence flags, re-transcription, uncertainty markers.

**Deliverables:**
- QualityPipeline service
- Segment-level confidence UI
- Audio replay per segment
- Manual correction flow
- Benchmark script + initial fixtures

**Exit criteria:** Low-confidence segments highlighted; user can edit and replay.

---

### Sprint 5 (Week 6-7): AI Structuring
**Goal:** Meeting notes, brainstorm, and other output types.

**Deliverables:**
- SummaryService with JSON schema
- NoteDetailView tabs (Transcript, Summary, Actions)
- Output type picker on Record screen
- Anti-hallucination validation

**Exit criteria:** Meeting recording produces summary + action items + decisions.

---

### Sprint 6 (Week 7-8): Library + Search
**Goal:** Full note management.

**Deliverables:**
- Notes list with filters (language, date, tag)
- Search across transcripts
- Favorites, tags, projects
- Auto-title generation

**Exit criteria:** 50+ notes searchable in < 500ms.

---

### Sprint 7 (Week 8-9): Export + Email
**Goal:** Share and email workflows.

**Deliverables:**
- ExportService (TXT, MD, PDF, RTF, ZIP)
- EmailService with MFMailComposeViewController
- Email settings (recipients, policy, attachments)

**Exit criteria:** Export PDF; compose email with transcript + audio attachment.

---

### Sprint 8 (Week 9-10): Privacy + Security
**Goal:** GDPR compliance and encryption.

**Deliverables:**
- GDPR export/delete all data
- Audio retention settings
- Keychain for API keys
- Face ID lock
- EncryptionService (optional audio encryption)

**Exit criteria:** GDPR checklist 100% for MVP items.

---

### Sprint 9 (Week 10-12): Polish + Release
**Goal:** TestFlight beta.

**Deliverables:**
- Error/retry UX
- Empty states, loading states
- App icon, launch screen
- TestFlight build
- App Store Connect metadata

**Exit criteria:** TestFlight build approved for internal testing.

---

## Team Roles (Recommended)

| Role | Responsibility |
|------|---------------|
| iOS Engineer | SwiftUI, services, recording |
| AI/Backend Engineer | Provider integration, quality pipeline, prompts |
| Product Designer | UI/UX, design system |
| QA | Test plan execution, LB benchmark |
| Legal/Privacy | GDPR review, privacy policy |

---

## Technical Decisions (Locked for MVP)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Min iOS | 17.0 | SwiftData, Observation |
| Persistence | SwiftData | Native, simple |
| DI | AppEnvironment struct | No third-party DI |
| Networking | URLSession | Native, async/await |
| Email | MFMailComposeViewController | No backend needed |
| LB primary | LuxASR | Best native LB ASR |
| Summary LLM | OpenAI gpt-4o-mini | Cost/quality balance |

---

## CI/CD (Recommended)

```yaml
# .github/workflows/ios.yml
- Build on macOS runner
- Run unit tests
- Skip provider integration tests unless secrets present
- Archive for TestFlight on tag push
```

---

## Repository Structure (Final)

```
Paperorg Notes/
├── docs/                    # This documentation
├── PaperorgNotes/           # iOS app source
├── PaperorgNotesTests/      # Unit + integration tests
├── Scripts/                 # Benchmark scripts
├── TestFixtures/            # Audio fixtures for benchmark
├── project.yml              # XcodeGen spec
└── README.md
```
