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

exec uvicorn main:app --reload --host 0.0.0.0 --port 8080
