#!/usr/bin/env bash
# Architect-defined full verification. This is intentionally explicit so a
# worker cannot choose or weaken the runner through mutable project config.
set -euo pipefail

PYTHON_BIN="${PAPERORG_PYTHON_BIN:-/Users/germaind/.local/bin/python3.11}"
VENV_DIR="${PAPERORG_DUO_VENV:-/private/tmp/paperorg-notes-duo-verify-py311}"
SIMULATOR_ID="02F3B1B5-1A64-4BC9-BA3F-0B72A5CA3735"

test -x "$PYTHON_BIN"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install -q -r backend/requirements.txt pytest
PYTHONDONTWRITEBYTECODE=1 "$VENV_DIR/bin/python" -m pytest backend/tests -q

xcodebuild test -project PaperorgNotes.xcodeproj -scheme PaperorgNotes \
  -destination "platform=iOS Simulator,id=$SIMULATOR_ID" \
  -derivedDataPath /private/tmp/paperorg-notes-duo-verify-derived \
  CODE_SIGNING_ALLOWED=NO
