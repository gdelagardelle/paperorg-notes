#!/bin/bash
# Luxembourgish ASR Benchmark Script
# Compares LuxASR, ElevenLabs Scribe, and OpenAI on test fixtures.
#
# Usage:
#   export OPENAI_API_KEY=...
#   export ELEVENLABS_API_KEY=...
#   export LUXASR_API_KEY=...  # optional
#   ./Scripts/benchmark_luxembourgish.sh

set -euo pipefail

FIXTURES_DIR="${FIXTURES_DIR:-TestFixtures/Luxembourgish}"
OUTPUT_CSV="${OUTPUT_CSV:-benchmark_results.csv}"

if [ ! -d "$FIXTURES_DIR" ]; then
  echo "Fixtures directory not found: $FIXTURES_DIR"
  echo "Create test clips with matching .txt reference transcripts."
  echo "See docs/TEST_PLAN.md for format."
  exit 1
fi

echo "provider,file,wer,latency_ms" > "$OUTPUT_CSV"

wer() {
  python3 - "$1" "$2" <<'PY'
import sys, re
def norm(t): return re.sub(r'\s+', ' ', t.lower().strip())
def words(t): return norm(t).split()
ref, hyp = words(open(sys.argv[1]).read()), words(open(sys.argv[2]).read())
n = max(len(ref), 1)
# Levenshtein word-level
d = [[0]*(len(hyp)+1) for _ in range(len(ref)+1)]
for i in range(len(ref)+1): d[i][0] = i
for j in range(len(hyp)+1): d[0][j] = j
for i,r in enumerate(ref,1):
  for j,h in enumerate(hyp,1):
    d[i][j] = min(d[i-1][j]+1, d[i][j-1]+1, d[i-1][j-1]+(r!=h))
print(f"{100*d[len(ref)][len(hyp)]/n:.2f}")
PY
}

for audio in "$FIXTURES_DIR"/*.m4a "$FIXTURES_DIR"/*.wav; do
  [ -f "$audio" ] || continue
  base="${audio%.*}"
  ref="${base}.txt"
  [ -f "$ref" ] || continue
  name=$(basename "$audio")
  
  echo "Benchmarking: $name"
  
  # OpenAI
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    start=$(python3 -c 'import time; print(int(time.time()*1000))')
    hyp="/tmp/hyp_openai_${name}.txt"
    curl -sf https://api.openai.com/v1/audio/transcriptions \
      -H "Authorization: Bearer $OPENAI_API_KEY" \
      -F file="@$audio" \
      -F model="gpt-4o-transcribe" \
      -F language="lb" \
      -F response_format="text" \
      -o "$hyp" || echo "[error]" > "$hyp"
    end=$(python3 -c 'import time; print(int(time.time()*1000))')
    w=$(wer "$ref" "$hyp")
    echo "openai,$name,$w,$((end-start))" >> "$OUTPUT_CSV"
  fi
  
  # ElevenLabs
  if [ -n "${ELEVENLABS_API_KEY:-}" ]; then
    start=$(python3 -c 'import time; print(int(time.time()*1000))')
    hyp="/tmp/hyp_eleven_${name}.txt"
    curl -sf https://api.elevenlabs.io/v1/speech-to-text \
      -H "xi-api-key: $ELEVENLABS_API_KEY" \
      -F file="@$audio" \
      -F model_id="scribe_v2" \
      -F language_code="ltz" \
      | python3 -c 'import sys,json; print(json.load(sys.stdin).get("text",""))' > "$hyp" || echo "[error]" > "$hyp"
    end=$(python3 -c 'import time; print(int(time.time()*1000))')
    w=$(wer "$ref" "$hyp")
    echo "elevenlabs,$name,$w,$((end-start))" >> "$OUTPUT_CSV"
  fi
  
  # LuxASR (queued v3 API)
  if [ -n "${LUXASR_API_KEY:-}" ] || true; then
    start=$(python3 -c 'import time; print(int(time.time()*1000))')
    hyp="/tmp/hyp_luxasr_${name}.txt"
    ext="${audio##*.}"
    case "$ext" in
      wav) mime="audio/wav" ;;
      mp3) mime="audio/mpeg" ;;
      *) mime="audio/mp4" ;;
    esac
    job=$(curl -sf -X POST "https://luxasr.uni.lu/asr2?language=lb&diarization=Disabled&outfmt=text" \
      -H "Content-Type: $mime" \
      -H "X-Filename: $(basename "$audio")" \
      --data-binary "@$audio" | python3 -c 'import sys,json; print(json.load(sys.stdin)["job_id"])') || job=""
    if [ -n "$job" ]; then
      for i in $(seq 1 60); do
        status=$(curl -sf "https://luxasr.uni.lu/v3/asr/jobs/$job" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("status",""))')
        [ "$status" = "completed" ] && break
        [ "$status" = "failed" ] && break
        sleep 2
      done
      curl -sf "https://luxasr.uni.lu/v3/asr/jobs/$job/result" -o "$hyp" || echo "[error]" > "$hyp"
    else
      echo "[error]" > "$hyp"
    fi
    end=$(python3 -c 'import time; print(int(time.time()*1000))')
    w=$(wer "$ref" "$hyp")
    echo "luxasr,$name,$w,$((end-start))" >> "$OUTPUT_CSV"
  fi
done

echo "Results written to $OUTPUT_CSV"
column -t -s, "$OUTPUT_CSV" 2>/dev/null || cat "$OUTPUT_CSV"
