# Paperorg Notes — API Provider Strategy

## 1. Provider Abstraction

All transcription backends implement `TranscriptionProvider`:

```swift
protocol TranscriptionProvider: Sendable {
    var identifier: String { get }
    var displayName: String { get }
    var supportedLanguages: Set<AppLanguage> { get }
    var requiresNetwork: Bool { get }
    var sendsAudioOffDevice: Bool { get }
    var supportsDiarization: Bool { get }
    var supportsWordTimestamps: Bool { get }
    
    func transcribe(_ request: TranscriptionRequest) async throws -> TranscriptionResult
}
```

Provider selection is **never hardcoded in UI** — configured via `ProviderRegistry`.

---

## 2. Luxembourgish Strategy (Critical)

### Research Summary (July 2026)

| Provider | LB Support | WER / Quality | Diarization | Latency | GDPR Notes |
|----------|------------|---------------|-------------|---------|------------|
| **LuxASR** (Uni Luxembourg) | Native `lb` | Best for LB; purpose-built | Yes (default on) | Async queue; ~30-40% of audio duration | EU-hosted; contact for commercial API |
| **ElevenLabs Scribe v2** | `ltz` ISO 639-3 | Claims 3.1% FLEURS / 5.5% Common Voice | Yes | Fast batch API | US provider; consent required |
| **OpenAI gpt-4o-transcribe** | Not in high-accuracy list | Often misdetects LB as DE/NL | Via gpt-4o-transcribe-diarize | Fast | US provider; consent required |
| **OpenAI whisper-1** | Multilingual but weak on LB | Poor LB WER in practice | Limited | Moderate | US provider |
| **Apple Speech** | No native LB | Unreliable | No | On-device | Best privacy; not viable for LB |
| **HuggingFace fine-tuned Whisper** | ZLSCompLing, unilux models | Good but self-hosted | Via WhisperX | Requires backend | Self-host option for Phase 2 |

### Recommended Default Chain for Luxembourgish

```
1. LuxASR (primary) — if API key configured & consented
2. ElevenLabs Scribe v2 (fallback) — language_code=ltz
3. OpenAI gpt-4o-transcribe (last resort) — prompt hint in Luxembourgish
```

### Quality Pipeline for LB
1. Run primary (LuxASR)
2. If avg confidence < 0.75 OR language validation fails → run ElevenLabs
3. If segment confidence < 0.5 → re-transcribe that window with fallback
4. Compare overlapping text; prefer higher-confidence words
5. Mark unresolved conflicts as `[unclear]`

---

## 3. Provider Details

### 3.1 LuxASR

**Base URL:** `https://luxasr.uni.lu`

**Flow (v3 queued API):**
```
POST /asr2?language=lb&diarization=Enabled&outfmt=json
  Body: raw audio bytes (NOT multipart)
  Content-Type: audio/mp4 | audio/wav | audio/mpeg | ...
  X-Filename: recording.m4a
  → 202 {"job_id":"<id>","status":"queued"}

GET /v3/asr/jobs/{job_id}
  → {"status":"queued"|"processing"|"completed"|"failed"}

GET /v3/asr/jobs/{job_id}/result
  → JSON transcript (when status=completed)
```

**Parameters:**
- `language=lb`
- `diarization=Enabled|Disabled`
- `outfmt=json|srt|vtt|text`
- `prompt=` optional context hint

**Notes:**
- Requires permission for commercial integration — app shows contact info
- Best diarization + LB accuracy
- Async only (not suitable for live MVP)

### 3.2 OpenAI Transcription

**Endpoint:** `POST https://api.openai.com/v1/audio/transcriptions`

**Models:**
| Model | Use Case |
|-------|----------|
| `gpt-4o-transcribe` | Primary for DE, FR, EN, PT |
| `gpt-4o-mini-transcribe` | Cost-sensitive fallback |
| `gpt-4o-transcribe-diarize` | Phase 2 diarization |
| `whisper-1` | Legacy fallback |

**Request:** multipart form with `file`, `model`, `language`, `response_format=verbose_json`

**Language codes:** `de`, `fr`, `en`, `pt` (use `lb` hint for Luxembourgish attempt)

### 3.3 ElevenLabs Scribe

**Endpoint:** `POST https://api.elevenlabs.io/v1/speech-to-text`

**Model:** `scribe_v2`

**Parameters:**
- `language_code`: `ltz` (LB), `deu`, `fra`, `eng`, `por`
- `diarize=true`
- `timestamps_granularity=word`

**Response:** words with timestamps, speaker_id, confidence

### 3.4 Apple Speech (On-Device)

**Framework:** `Speech` (SFSpeechRecognizer)

**Use:** English offline fallback when user enables privacy mode

**Limitation:** No Luxembourgish locale — excluded from LB chain

---

## 4. Provider Registry Configuration

```swift
// Default registry (user-overridable per language)
let defaultRegistry: [AppLanguage: [String]] = [
    .luxembourgish: ["luxasr", "elevenlabs", "openai"],
    .german:         ["openai", "elevenlabs"],
    .french:         ["openai", "elevenlabs"],
    .english:        ["openai", "apple", "elevenlabs"],
    .portuguese:     ["openai", "elevenlabs"],
]
```

---

## 5. Summary / Structuring Provider

**MVP:** OpenAI Chat Completions (`gpt-4o-mini` or `gpt-4o`)

**System prompt constraints:**
- Only extract information present in transcript
- Use `[not mentioned]` for missing fields
- Output strict JSON matching `StructuredOutput` schema
- Respond in the same language as the transcript unless user requests translation

---

## 6. Benchmark Plan (Luxembourgish)

### Test Set Composition
- 20 clips × 30-120 seconds
- Sources: RTL Lëtzebuergesch snippets (manual collection), user-contributed (with consent), synthetic TTS from Lux corpus
- Conditions: clean studio, meeting room noise, phone quality

### Metrics
- WER (word error rate) vs human reference transcript
- Language detection accuracy
- Diarization DER (Phase 2)
- Latency (p50, p95)
- Cost per minute

### Benchmark Script
Located at `Scripts/benchmark_luxembourgish.sh` — runs all configured providers against `TestFixtures/Luxembourgish/` and outputs comparison CSV.

### Expected MVP Outcome
- **Default LB provider:** LuxASR (when key available), else ElevenLabs
- Document WER in app Settings → About → Transcription Quality

---

## 7. Consent & Disclosure

Before first use of each provider, show:
- Provider name & country
- "Audio will be sent to [provider] for transcription"
- Link to provider privacy policy
- Require explicit toggle per provider

Stored in `consentedProviders: [String]`.

---

## 8. Cost Estimates (MVP)

| Provider | ~Cost / 10 min audio |
|----------|---------------------|
| LuxASR | TBD (institutional pricing) |
| OpenAI gpt-4o-transcribe | ~$0.06-0.12 |
| ElevenLabs Scribe | ~$0.08-0.15 |
| OpenAI summary | ~$0.01-0.03 |

App should show estimated cost in Settings (informational).
