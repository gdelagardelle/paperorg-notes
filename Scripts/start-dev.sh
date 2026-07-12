#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

backend_health_ok() {
  curl -sf http://127.0.0.1:8080/health 2>/dev/null | grep -q '"service":"paperorg-pro"'
}

if backend_health_ok; then
  echo "Notes backend already running at http://127.0.0.1:8080"
  echo "In Xcode: PaperorgNotes scheme → iPhone Simulator → ⌘R"
  echo "Pro in simulator: Upgrade → Try Pro Free (Simulator)"
  exit 0
fi

if lsof -i :8080 -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port 8080 is in use by something else (not the Notes backend)."
  echo "Free it with: kill \$(lsof -t -i :8080 -sTCP:LISTEN)"
  exit 1
fi

echo "Starting Paperorg Notes dev backend on http://127.0.0.1:8080"
echo "Then in Xcode: PaperorgNotes scheme → iPhone Simulator → ⌘R"
echo "Pro in simulator: Upgrade → Try Pro Free (Simulator)"
echo

exec "$ROOT/Scripts/start-backend.sh"
