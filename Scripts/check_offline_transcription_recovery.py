#!/usr/bin/env python3
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def source(relative: str) -> str:
    return (ROOT / relative).read_text(encoding="utf-8")


def require(relative: str, fragments: tuple[str, ...]) -> None:
    text = source(relative)
    missing = [fragment for fragment in fragments if fragment not in text]
    assert not missing, f"{relative} is missing: {', '.join(missing)}"


require("PaperorgNotes/Models/Enums.swift", (
    "case waitingForNetwork",
    "enum OfflineTranscriptionRecoveryPolicy",
    "isConnectivityFailure",
    "shouldRetry",
))
require("PaperorgNotes/App/AppEnvironment.swift", (
    "import Network",
    "NWPathMonitor",
    "connectivityMonitor",
))
require("PaperorgNotes/App/MainTabView.swift", (
    "retryingNoteIDs",
    "retryWaitingTranscriptions",
    "connectivityMonitor.isConnected",
    "processRecordingUseCase.transcribeAgain",
))
require("PaperorgNotes/UseCases/ProcessRecordingUseCase.swift", (
    "OfflineTranscriptionRecoveryPolicy.isConnectivityFailure",
    "NoteStatus.waitingForNetwork.rawValue",
))
require("PaperorgNotes/Views/Record/RecordView.swift", (
    "note.noteStatus != .waitingForNetwork",
))
require("PaperorgNotes/Views/Notes/NoteDetailView.swift", (
    "note.noteStatus == .waitingForNetwork",
    "L10n.OfflineRecovery.waitingMessage",
    "transcribeAgain()",
))
require("PaperorgNotes/Views/Components/AppDesignSystem.swift", (
    "case .waitingForNetwork",
    "L10n.OfflineRecovery.waitingStatus",
))
require("PaperorgNotes/Utilities/L10n.swift", (
    'String(localized: "offline_recovery.waiting_status")',
    'String(localized: "offline_recovery.waiting_message")',
))

process = source("PaperorgNotes/UseCases/ProcessRecordingUseCase.swift")
failure_block = process[process.index("} catch {"):process.index("    func transcribeAgain")]
assert "deleteAudio" not in failure_block, "processing failure path must retain recorded audio"

catalog = json.loads(source("PaperorgNotes/Resources/Localizable.xcstrings"))
for key in ("offline_recovery.waiting_status", "offline_recovery.waiting_message"):
    entry = catalog["strings"].get(key)
    assert entry is not None, f"missing localization key: {key}"
    localizations = entry.get("localizations", {})
    for language in ("en", "de", "fr", "lb", "pt"):
        value = localizations.get(language, {}).get("stringUnit", {}).get("value", "").strip()
        assert value, f"{key} is missing a {language} translation"

print("Offline transcription recovery contract is present in all five languages.")
