#!/usr/bin/env python3
"""Validate complete catalog coverage for every supported spoken language."""

from __future__ import annotations

import json
import re
from pathlib import Path


CATALOG = Path(__file__).parents[1] / "PaperorgNotes/Resources/Localizable.xcstrings"
ENUMS = Path(__file__).parents[1] / "PaperorgNotes/Models/Enums.swift"
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|f|@)")


def localized_value(entry: dict, language: str) -> str:
    return (
        entry.get("localizations", {})
        .get(language, {})
        .get("stringUnit", {})
        .get("value", "")
    )


def normalized_placeholders(value: str) -> list[str]:
    return sorted(re.sub(r"\d+\$", "", item) for item in PLACEHOLDER.findall(value))


def spoken_language_codes() -> tuple[str, ...]:
    source = ENUMS.read_text(encoding="utf-8")
    app_language = source.split("enum AppLanguage", 1)[1].split("enum TranscriptionProvider", 1)[0]
    codes = re.findall(r'^\s*case\s+\w+\s*=\s*"([a-z]{2})"', app_language, re.MULTILINE)
    if not codes:
        raise SystemExit("No spoken AppLanguage codes found")
    return tuple(sorted(set(codes)))


def main() -> None:
    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    strings = catalog.get("strings", {})
    languages = spoken_language_codes()
    failures: list[str] = []
    german_luxembourgish_pairs: list[tuple[str, str, str]] = []

    for key, entry in strings.items():
        source = localized_value(entry, "en") or key
        expected_placeholders = normalized_placeholders(source)
        for language in languages:
            value = localized_value(entry, language)
            if not value:
                failures.append(f"missing {language}: {key}")
                continue
            if normalized_placeholders(value) != expected_placeholders:
                failures.append(f"placeholder mismatch {language}: {key}")

        german = localized_value(entry, "de").strip()
        luxembourgish = localized_value(entry, "lb").strip()
        if len(source.strip()) >= 4 and german and luxembourgish:
            german_luxembourgish_pairs.append((key, german, luxembourgish))

    duplicate_count = sum(
        1 for _, german, luxembourgish in german_luxembourgish_pairs
        if german.casefold() == luxembourgish.casefold()
    )
    duplicate_ratio = duplicate_count / max(len(german_luxembourgish_pairs), 1)
    if duplicate_ratio > 0.35:
        failures.append(
            f"Luxembourgish duplicates German for {duplicate_count}/"
            f"{len(german_luxembourgish_pairs)} strings ({duplicate_ratio:.0%})"
        )

    if failures:
        raise SystemExit("\n".join(failures))
    print(
        f"{len(strings)} keys complete in {'/'.join(languages)}; "
        f"Luxembourgish/German duplicate ratio {duplicate_ratio:.1%}."
    )


if __name__ == "__main__":
    main()
