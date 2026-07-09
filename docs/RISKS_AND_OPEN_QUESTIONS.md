# Paperorg Notes — Risks & Open Questions

## 1. Technical Risks

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| LuxASR API access denied or unstable | High — LB quality suffers | Medium | ElevenLabs as primary fallback; pursue Uni Luxembourg partnership early |
| OpenAI removes/changes transcription API | High | Low | Provider abstraction; ElevenLabs as alternate for all languages |
| LB WER worse than expected in noisy environments | Medium | High | Quality pipeline + user correction; set expectations in UI |
| Background recording killed by iOS | High | Medium | UIBackgroundModes audio; checkpoint recovery; user education |
| SwiftData migration issues | Medium | Medium | VersionedSchema from day 1; export before updates |
| Large audio files exhaust storage | Medium | Medium | Retention settings; compression; storage warning |
| API cost surprises for heavy users | Medium | Medium | Show cost estimates; optional usage tracking in Settings |

---

## 2. Product Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Users expect perfect LB transcription | High | Confidence markers, correction flow, transparent provider info |
| GDPR scrutiny (Luxembourg/EU market) | High | Full checklist implementation; legal review |
| Competing with free Apple Notes / Voice Memos | Medium | Differentiate on LB + structuring + multilingual |
| Email via MFMailCompose requires Mail app | Low | Document requirement; Phase 2 server email option |

---

## 3. Legal & Compliance Open Questions

1. **LuxASR commercial licensing:** What are the terms for embedding in a commercial iOS app? Contact: Peter Gilles / Uni Luxembourg FHSE.
2. **Luxembourgish TTS/training data:** Can user-contributed audio be used for benchmark sets under GDPR?
3. **OpenAI DPA:** Is OpenAI API covered under standard DPA for EU business users?
4. **ElevenLabs data retention:** How long is audio retained on their servers?
5. **App Store category:** Productivity vs. Business — affects discoverability.
6. **Privacy policy hosting:** Where will the legal privacy policy URL live?

---

## 4. Technical Open Questions

1. **Live transcription provider:** OpenAI Realtime vs ElevenLabs streaming vs LuxASR (no realtime) — defer to Phase 2?
2. **On-device LB model:** Is Core ML conversion of ZLSCompLing Whisper feasible for offline LB?
3. **Speaker diarization UX:** Show speaker labels in MVP or Phase 2?
4. **Correction learning:** Store corrections locally only, or sync vocabulary to cloud?
5. **Language detection:** Use provider detection vs separate lid model (e.g., fastText)?
6. **Mixed LB/FR/DE meetings:** Single language setting vs per-segment language — how to handle code-switching?
7. **iPad optimization:** iPhone-only MVP or universal from start?

---

## 5. Benchmark Open Questions

1. **Reference transcript source:** Who validates human reference transcripts for LB benchmark set?
2. **Sample size:** Is 20 clips sufficient for provider selection?
3. **Update frequency:** Re-benchmark when providers release new models — automated CI job?

---

## 6. Business Open Questions

1. **Monetization:** Subscription vs one-time purchase vs freemium with API key BYOK?
2. **Target market launch:** Luxembourg-first vs EU-wide?
3. **Branding:** "Paperorg Notes" final name or working title?
4. **Team features timeline:** When does workspace/sharing become priority?

---

## 7. Recommended Immediate Actions

1. **Contact Uni Luxembourg** for LuxASR API commercial terms
2. **Collect 10+ LB audio samples** with human transcripts for benchmark
3. **Run benchmark script** once providers configured
4. **Legal review** of privacy policy before TestFlight external beta
5. **Decide BYOK vs bundled API** cost model before App Store pricing

---

## 8. Assumptions Made in MVP

- User provides their own API keys (BYOK model) OR app ships with trial credits (TBD)
- No user accounts / cloud backend in MVP
- Email sent via device Mail app only
- Luxembourgish UI strings are best-effort (professional translation recommended before launch)
- TestFlight internal beta before public App Store release
