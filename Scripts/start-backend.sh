#!/usr/bin/env bash
set -euo pipefail

# The backend is a separate repository, gdelagardelle/paperorg-notes-api. It
# used to be vendored here as backend/, and that copy drifted from the
# deployed service without anyone noticing. Point this at a real checkout
# instead:
#
#   PAPERORG_NOTES_API_DIR=/path/to/paperorg-notes-api Scripts/start-backend.sh
#
# With no override it looks beside this repository, then in ~/dev.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

find_api_dir() {
    if [[ -n "${PAPERORG_NOTES_API_DIR:-}" ]]; then
        echo "$PAPERORG_NOTES_API_DIR"
        return
    fi
    for candidate in "$(dirname "$ROOT")/paperorg-notes-api" "$HOME/dev/paperorg-notes-api"; do
        if [[ -f "$candidate/main.py" ]]; then
            echo "$candidate"
            return
        fi
    done
}

API_DIR="$(find_api_dir)"

if [[ -z "$API_DIR" || ! -f "$API_DIR/main.py" ]]; then
    cat >&2 <<'MSG'
ERROR: cannot find the paperorg-notes-api checkout.

The backend is no longer vendored in this repository. Clone it and either put
it beside this repo or set PAPERORG_NOTES_API_DIR:

    git clone git@github.com:gdelagardelle/paperorg-notes-api.git
    PAPERORG_NOTES_API_DIR=/path/to/paperorg-notes-api Scripts/start-backend.sh
MSG
    exit 1
fi

cd "$API_DIR"
echo "Using backend checkout: $API_DIR"

# 3.10 is the floor; see the Python version section in that repo's README.
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  source .venv/bin/activate
  python -m pip install -r requirements.txt
else
  source .venv/bin/activate
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created $API_DIR/.env — add the provider keys before Pro transcription works."
fi

if curl -sf http://127.0.0.1:8080/health 2>/dev/null | grep -q '"service":"paperorg-pro"'; then
  echo "Notes backend already running at http://127.0.0.1:8080"
  exit 0
fi

if lsof -i :8080 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "ERROR: Port 8080 is already in use."
  echo "Free it with: kill \$(lsof -t -i :8080 -sTCP:LISTEN)"
  exit 1
fi

exec uvicorn main:app --reload --host 0.0.0.0 --port 8080
