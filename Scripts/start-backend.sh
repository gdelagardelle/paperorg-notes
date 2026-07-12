#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT/backend"

if [[ ! -d .venv ]]; then
  python3 -m venv .venv
  source .venv/bin/activate
  pip install -r requirements.txt
else
  source .venv/bin/activate
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Created backend/.env — add OPENAI_API_KEY and ELEVENLABS_API_KEY before Pro transcription works."
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
