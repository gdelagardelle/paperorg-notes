#!/usr/bin/env python3
"""Run the Release analyzer with Swift warnings promoted to errors."""

from __future__ import annotations

import subprocess
import tempfile


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="paperorg-release-warnings-") as derived_data:
        command = [
            "xcodebuild",
            "-project",
            "PaperorgNotes.xcodeproj",
            "-scheme",
            "PaperorgNotes",
            "-configuration",
            "Release",
            "-destination",
            "generic/platform=iOS Simulator",
            "-derivedDataPath",
            derived_data,
            "CODE_SIGNING_ALLOWED=NO",
            "SWIFT_TREAT_WARNINGS_AS_ERRORS=YES",
            "analyze",
        ]
        result = subprocess.run(command, check=False)
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
