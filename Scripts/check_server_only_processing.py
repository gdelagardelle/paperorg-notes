#!/usr/bin/env python3
"""Regression guard for the server-only processing policy.

Every transcription and summary request goes to the Paperorg backend, which
holds the provider credentials. The app never asks a user for an OpenAI,
ElevenLabs or LuxASR key, never stores one, and never calls a provider
directly. That was a deliberate removal, and this guard is what stops it
growing back a line at a time.

It began life as backend/tests/test_server_only_processing.py inside this
repository's vendored copy of the backend, reaching the Swift sources by
walking two directories up. The backend moved to its own repository and the
test could not follow it -- its subject is this app, not the server -- so it
lives here now, as a guard beside the others rather than as a pytest case in
a directory with no pytest.
"""

from __future__ import annotations

import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


def check_settings_offer_no_personal_provider_keys() -> list[str]:
    """Settings must not collect provider keys or offer provider choice."""
    settings = source("PaperorgNotes/Views/Settings/SettingsView.swift")
    included = source("PaperorgNotes/Views/Subscription/IncludedMinutesAccessView.swift")

    failures = [
        f"SettingsView still references {name}"
        for name in ("openAIKey", "elevenLabsKey", "luxASRKey", "ProviderID.allCases")
        if name in settings
    ]
    if "L10n.Included.useOwnKeys" in included:
        failures.append("IncludedMinutesAccessView still offers bring-your-own-key")
    return failures


def check_recording_requires_no_personal_key() -> list[str]:
    record = source("PaperorgNotes/Views/Record/RecordView.swift")
    if "openAIAPIKey?.isEmpty" in record:
        return ["RecordView still gates recording on a personal OpenAI key"]
    return []


def check_processing_goes_only_through_the_backend() -> list[str]:
    summary = source("PaperorgNotes/Services/Summary/SummaryService.swift")
    providers = source("PaperorgNotes/Services/Transcription/TranscriptionProvider.swift")

    failures = []
    if "https://api.openai.com/v1/chat/completions" in summary:
        failures.append("SummaryService calls OpenAI directly instead of the backend")
    if "let providers = registry.orderedProviders" in providers:
        failures.append("TranscriptionProvider enumerates providers on device")

    routed = providers.count("return try await proRouter.transcribe(request)")
    if routed < 2:
        failures.append(
            f"TranscriptionProvider routes through proRouter at {routed} site(s), expected at least 2"
        )
    return failures


def main() -> None:
    failures: list[str] = []
    for check in (
        check_settings_offer_no_personal_provider_keys,
        check_recording_requires_no_personal_key,
        check_processing_goes_only_through_the_backend,
    ):
        failures.extend(check())

    if failures:
        sys.exit("server-only processing policy violated:\n  - " + "\n  - ".join(failures))

    print("Transcription and summaries go only through the Paperorg backend.")


if __name__ == "__main__":
    main()
