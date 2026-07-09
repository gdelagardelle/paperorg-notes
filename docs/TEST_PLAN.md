# Paperorg Notes — Test Plan

## 1. Test Levels

| Level | Scope | Tools |
|-------|-------|-------|
| Unit | Services, providers, pipeline | XCTest |
| Integration | Record → transcribe → store flow | XCTest + mocks |
| UI | Critical user paths | XCUITest |
| Benchmark | LB transcription quality | Shell script + WER tool |
| Manual | Device recording, background | Physical devices |

---

## 2. Unit Tests

### RecordingService
- `testStartRecording_createsAudioFile`
- `testPauseResume_preservesDuration`
- `testCheckpointRecovery_afterSimulatedCrash`
- `testAudioQualityWarning_onLowInput`

### ProviderRegistry
- `testLuxembourgishProviderOrder_luxasrFirst`
- `testFallbackChain_whenPrimaryFails`
- `testEnglishIncludesAppleSpeech`

### QualityPipeline
- `testFlagsLowConfidenceSegments_belowThreshold`
- `testDetectsSuspiciousRepeatedCharacters`
- `testDetectsMixedLanguageSegments`
- `testNeverInventsWords_inMergedOutput`
- `testRetranscribesWeakSegments_withFallback`

### SummaryService
- `testStructuredOutput_matchesSchema`
- `testRejectsHallucinatedNames_notInTranscript`
- `testMeetingNotesOutputType_includesActionItems`

### ExportService
- `testMarkdownExport_includesTranscriptAndSummary`
- `testPDFExport_generatesValidPDF`
- `testPackageExport_includesAudioAndTranscript`

### StorageService
- `testCreateNote_persistsToSwiftData`
- `testCorrectedTranscript_doesNotOverwriteRaw`
- `testDeleteAllData_removesAudioFiles`

### KeychainService
- `testSaveAndRetrieveAPIKey`
- `testDeleteAPIKey_removesFromKeychain`

---

## 3. Integration Tests

### End-to-End (Mock Providers)
- `testRecordStopTranscribeSummarize_readyState`
- `testTranscriptionFailure_audioStillSaved`
- `testRetryTranscription_afterFailure`

### Provider Integration (Requires API Keys — CI optional)
- `testOpenAI_transcribeGermanFixture`
- `testElevenLabs_transcribeLuxembourgishFixture`
- `testLuxASR_queuedJobFlow`

---

## 4. UI Tests

- `testFirstLaunch_showsPrivacyConsent`
- `testRecordFlow_stopShowsProcessing`
- `testNotesList_displaysSavedNote`
- `testSearch_findsTranscriptKeyword`
- `testSettings_saveEmailRecipient`

---

## 5. Luxembourgish Benchmark

### Test Fixtures
```
TestFixtures/Luxembourgish/
├── lb_001_clean_30s.m4a + lb_001.txt (reference)
├── lb_002_meeting_60s.m4a + lb_002.txt
├── lb_003_noisy_45s.m4a + lb_003.txt
├── ...
└── manifest.json
```

### Benchmark Script
`Scripts/benchmark_luxembourgish.sh`:
1. For each fixture, run LuxASR, ElevenLabs, OpenAI
2. Compute WER against reference transcript
3. Output `benchmark_results.csv`

### WER Formula
```
WER = (S + D + I) / N × 100%
S = substitutions, D = deletions, I = insertions, N = reference words
```

### Acceptance Criteria
| Provider | Target WER |
|----------|-----------|
| LuxASR | < 12% (clean), < 20% (noisy) |
| ElevenLabs | < 15% (clean), < 25% (noisy) |
| OpenAI | < 25% (clean) — fallback only |

---

## 6. Manual Test Matrix

| Scenario | Device | Expected |
|----------|--------|----------|
| Background recording 10 min | iPhone 15 | Audio complete, no gaps |
| Lock screen during recording | iPhone | Recording continues |
| Incoming call during recording | iPhone | Graceful pause or continue per iOS |
| Airplane mode + EN | iPhone | Apple Speech fallback or clear error |
| Low storage | iPhone | Warning before record |
| Face ID lock | iPhone | Blocks content until auth |
| GDPR export | iPhone | ZIP with all notes + audio |
| Delete all data | iPhone | Empty library, no orphan files |

---

## 7. Performance Tests

| Metric | Target |
|--------|--------|
| App launch to record-ready | < 2s |
| 5 min audio → transcript (OpenAI) | < 60s |
| 5 min audio → transcript (LuxASR) | < 120s |
| Search 1000 notes | < 500ms |
| Memory during recording | < 100MB |

---

## 8. Regression Checklist (Pre-Release)

- [ ] All unit tests pass
- [ ] UI smoke tests pass
- [ ] LB benchmark run documented
- [ ] No API keys in repo
- [ ] Privacy consent blocks API calls
- [ ] Background recording works on iOS 17 and 18
- [ ] iPad layout acceptable (iPhone-first MVP)
