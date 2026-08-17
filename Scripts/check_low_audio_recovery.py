#!/usr/bin/env python3
from pathlib import Path


reader = Path("PaperorgNotes/Utilities/AudioFileReader.swift").read_text()
provider = Path(
    "PaperorgNotes/Services/Transcription/Providers/LuxASRProvider.swift"
).read_text()
tests = Path("PaperorgNotesTests/PaperorgNotesTests.swift").read_text()

requirements = {
    "quiet-audio analysis": all(
        marker in reader
        for marker in (
            "prepareForTranscription",
            "quietPeakThreshold",
            "peakDecibels",
        )
    ),
    "bounded gain": all(
        marker in reader
        for marker in ("maximumGain", "min(maximumGain", "gainAppliedDecibels")
    ),
    "temporary leveled payload": all(
        marker in reader for marker in ("paperorg-transcription-", "audio/wav")
    ),
    "LuxASR uses leveled audio": all(
        marker in provider
        for marker in ("prepareForTranscription", "audioGainDB")
    ),
    "functional regression tests": all(
        marker in tests
        for marker in (
            "testQuietAudioIsAmplifiedForTranscription",
            "testNormalAudioIsNotReencoded",
            "originalData",
        )
    ),
}

missing = [name for name, present in requirements.items() if not present]
if missing:
    raise SystemExit("Missing low-audio recovery behavior: " + ", ".join(missing))

print("Low-audio recovery contract present")
