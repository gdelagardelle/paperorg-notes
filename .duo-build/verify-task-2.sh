#!/usr/bin/env bash
# Architect-owned fast verification for task 2.
set -euo pipefail

PYTHON_BIN="${PAPERORG_PYTHON_BIN:-/Users/germaind/.local/bin/python3.11}"
VENV_DIR="${PAPERORG_DUO_VENV:-/private/tmp/paperorg-notes-duo-verify-py311}"

test -x "$PYTHON_BIN"
if [ ! -x "$VENV_DIR/bin/python" ]; then
  "$PYTHON_BIN" -m venv "$VENV_DIR"
fi
"$VENV_DIR/bin/pip" install -q -r backend/requirements.txt pytest
PYTHONDONTWRITEBYTECODE=1 "$VENV_DIR/bin/python" -m pytest \
  backend/tests/test_free_included_quota.py \
  backend/tests/test_apple_identity.py \
  backend/tests/test_platform_tokens.py -q
