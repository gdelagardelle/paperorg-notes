# Paperorg Notes — Data Model

## 1. Entity Relationship

```
Note (1) ──────< TranscriptSegment (*)
  │
  ├──────< StructuredSection (*)
  │
  ├──────< Tag (*)
  │
  └─── (optional) Project

TranscriptionJob (1) ──── Note
ProviderBenchmarkResult ─── standalone
UserCorrection ──── TranscriptSegment
```

---

## 2. SwiftData Models

### Note
| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `title` | String | Manual or auto-generated |
| `createdAt` | Date | Creation timestamp |
| `updatedAt` | Date | Last modification |
| `durationSeconds` | Double | Audio length |
| `audioFileName` | String | Relative path in Recordings folder |
| `audioDeletedAt` | Date? | When audio was purged |
| `language` | String | ISO code (lb, de, fr, en, pt) |
| `detectedLanguage` | String? | Auto-detected language |
| `languageConfidence` | Double? | Detection confidence |
| `outputType` | String | meeting, brainstorm, etc. |
| `status` | String | draft, processing, ready, failed |
| `processingStage` | String? | uploading, transcribing, checking, summarizing |
| `isFavorite` | Bool | User favorite |
| `projectName` | String? | Project/folder |
| `rawTranscript` | String? | Immutable original |
| `correctedTranscript` | String? | User-edited version |
| `summaryShort` | String? | Short summary |
| `summaryDetailed` | String? | Detailed summary |
| `structuredOutputJSON` | Data? | Full structured output blob |
| `qualityReportJSON` | Data? | Quality pipeline results |
| `primaryProvider` | String? | Provider used |
| `tags` | [String] | Tag list |

### TranscriptSegment
| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `noteId` | UUID | Foreign key |
| `index` | Int | Order in transcript |
| `text` | String | Segment text |
| `startTime` | Double | Seconds |
| `endTime` | Double | Seconds |
| `confidence` | Double | 0.0–1.0 |
| `speakerLabel` | String? | Speaker ID/name |
| `isUnclear` | Bool | Low confidence flag |
| `isUserCorrected` | Bool | Manual edit applied |
| `originalText` | String? | Pre-correction text |
| `providerId` | String? | Source provider |

### StructuredSection
| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Primary key |
| `noteId` | UUID | Foreign key |
| `type` | String | action_item, decision, question, etc. |
| `title` | String? | Section heading |
| `content` | String | Section body |
| `items` | [String] | Bullet items if applicable |
| `order` | Int | Display order |

### AppSettings (UserDefaults + Keychain)
| Field | Storage | Description |
|-------|---------|-------------|
| `defaultLanguage` | UserDefaults | Default recording language |
| `autoDetectLanguage` | UserDefaults | Bool |
| `providerPreferences` | UserDefaults | JSON map language→provider |
| `defaultOutputType` | UserDefaults | String |
| `summaryLength` | UserDefaults | short / detailed |
| `keepAudioFiles` | UserDefaults | Bool |
| `deleteAudioAfterDays` | UserDefaults | Int? nil = never |
| `emailRecipients` | UserDefaults | [String] |
| `emailPolicy` | UserDefaults | always / ask / never |
| `emailContent` | UserDefaults | summary / transcript / both |
| `emailAttachments` | UserDefaults | audio, pdf, markdown flags |
| `faceIDEnabled` | UserDefaults | Bool |
| `hasAcceptedPrivacyPolicy` | UserDefaults | Bool |
| `consentedProviders` | UserDefaults | [String] provider IDs |
| `openAIAPIKey` | Keychain | Encrypted |
| `elevenLabsAPIKey` | Keychain | Encrypted |
| `luxASRAPIKey` | Keychain | Encrypted |

---

## 3. Codable DTOs (API / Export)

### TranscriptionResult
```swift
struct TranscriptionResult: Codable {
    let providerId: String
    let language: AppLanguage
    let segments: [TranscriptSegmentDTO]
    let fullText: String
    let averageConfidence: Double
    let processingTimeMs: Int
    let metadata: [String: String]
}
```

### StructuredOutput
```swift
struct StructuredOutput: Codable {
    let outputType: OutputType
    let title: String?
    let shortSummary: String
    let detailedSummary: String
    let keyIdeas: [String]
    let decisions: [String]
    let actionItems: [ActionItem]
    let openQuestions: [String]
    let risks: [String]
    let nextSteps: [String]
    let peopleMentioned: [String]
    let datesMentioned: [String]
    let importantNumbers: [String]
    let followUpEmailDraft: String?
    let generatedAt: Date
}

struct ActionItem: Codable, Identifiable {
    let id: UUID
    let text: String
    let assignee: String?
    let dueDate: String?
    let isCompleted: Bool
}
```

### QualityReport
```swift
struct QualityReport: Codable {
    let overallConfidence: Double
    let languageValidationPassed: Bool
    let detectedLanguage: AppLanguage
    let lowConfidenceSegmentIds: [UUID]
    let suspiciousPhrases: [SuspiciousPhrase]
    let mixedLanguageSegments: [MixedLanguageSegment]
    let providersUsed: [String]
    let retranscribedSegmentCount: Int
}

struct SuspiciousPhrase: Codable {
    let segmentIndex: Int
    let reason: String  // low_confidence, repeated_char, language_drift
    let text: String
}
```

---

## 4. File Storage Layout

```
Application Support/
├── Recordings/
│   └── {noteId}.m4a
├── Checkpoints/
│   └── {sessionId}.checkpoint
├── Exports/
│   └── {noteId}-{timestamp}.{ext}
└── GDPR/
    └── export-{timestamp}.zip
```

---

## 5. Indexing & Search

SwiftData `#Predicate` + in-memory fallback for full-text:
- Search fields: `title`, `rawTranscript`, `correctedTranscript`, `summaryShort`, `tags`
- Filters indexed via stored properties on `Note`

---

## 6. Migration Strategy

- SwiftData schema versioning via `VersionedSchema`
- v1: MVP entities
- v2: add `UserCorrection`, `SpeakerProfile`
- v3: CloudKit sync fields
