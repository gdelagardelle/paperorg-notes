#!/usr/bin/env python3
"""Verify the record-home journey is localized in every supported UI language."""

from __future__ import annotations

import json
from pathlib import Path


ROOT = Path(__file__).parents[1]
LANGUAGES = ("en", "de", "fr", "lb", "pt")
REQUIRED_KEYS = (
    "output.meeting",
    "output.brainstorm",
    "output.memo",
    "output.client_call",
    "output.interview",
    "output.tasks",
    "output.resume",
    "output.transcript_only",
    "record.resume",
    "record.pause",
    "home.recent_notes",
    "home.recent_subtitle",
    "record.status.idle",
    "record.status.recording",
    "record.status.paused",
    "record.start",
    "record.stop",
    "record.banner.paused",
    "record.banner.active",
    "record.banner.hint",
)
FORBIDDEN_LITERALS = (
    'return "Meeting"',
    'return "Transcript only"',
    'title: "Recent notes"',
    'case .idle: return "Tap to start recording"',
    'case .idle: return "Start recording"',
    'Text(state == .paused ? "Recording paused"',
)


def value(entry: dict, language: str) -> str:
    return (
        entry.get("localizations", {})
        .get(language, {})
        .get("stringUnit", {})
        .get("value", "")
        .strip()
    )


def main() -> None:
    catalog = json.loads(
        (ROOT / "PaperorgNotes/Resources/Localizable.xcstrings").read_text(encoding="utf-8")
    )["strings"]
    failures: list[str] = []
    for key in REQUIRED_KEYS:
        entry = catalog.get(key)
        if entry is None:
            failures.append(f"missing key: {key}")
            continue
        for language in LANGUAGES:
            if not value(entry, language):
                failures.append(f"missing {language}: {key}")

    source = "\n".join(
        (ROOT / path).read_text(encoding="utf-8")
        for path in (
            "PaperorgNotes/Models/Enums.swift",
            "PaperorgNotes/Views/Record/RecordView.swift",
            "PaperorgNotes/Views/Components/AppDesignSystem.swift",
        )
    )
    failures.extend(
        f"hard-coded home label: {literal}"
        for literal in FORBIDDEN_LITERALS
        if literal in source
    )
    if failures:
        raise SystemExit("\n".join(failures))
    print("Record-home UI is localized in en, de, fr, lb, and pt.")


if __name__ == "__main__":
    main()
