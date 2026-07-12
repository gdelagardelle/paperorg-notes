#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

echo "Starting Paperorg Notes dev backend on http://127.0.0.1:8080"
echo "Then in Xcode: PaperorgNotes scheme → iPhone Simulator → ⌘R"
echo "Pro in simulator: Upgrade → Try Pro Free (Simulator)"
echo

exec "$ROOT/Scripts/start-backend.sh"
