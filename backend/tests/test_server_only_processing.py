"""Regression guard for the consumer app's server-only processing policy."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def source(relative_path: str) -> str:
    return (ROOT / relative_path).read_text()


def test_settings_never_offer_personal_provider_keys_or_consent() -> None:
    settings = source("PaperorgNotes/Views/Settings/SettingsView.swift")
    included_access = source("PaperorgNotes/Views/Subscription/IncludedMinutesAccessView.swift")

    for forbidden in ("openAIKey", "elevenLabsKey", "luxASRKey", "ProviderID.allCases"):
        assert forbidden not in settings
    assert "L10n.Included.useOwnKeys" not in included_access


def test_recording_never_requires_a_personal_openai_key() -> None:
    record = source("PaperorgNotes/Views/Record/RecordView.swift")

    assert "openAIAPIKey?.isEmpty" not in record


def test_summary_and_transcription_use_only_paperorg_backend() -> None:
    summary = source("PaperorgNotes/Services/Summary/SummaryService.swift")
    providers = source("PaperorgNotes/Services/Transcription/TranscriptionProvider.swift")

    assert "https://api.openai.com/v1/chat/completions" not in summary
    assert "let providers = registry.orderedProviders" not in providers
    assert providers.count("return try await proRouter.transcribe(request)") >= 2
