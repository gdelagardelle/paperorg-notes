#!/usr/bin/env bash
# Proof of Done — runs in a CLEAN ROOM checkout of the commit you intend to
# ship, outside the worker's directory. $1 = evidence dir (also $DUO_EVIDENCE).
# $DUO_PROOF_PROFILE is "full" or "hotfix" — a hotfix proof may compress checks
# but a full proof is owed after merge-back (references/fix.md).
# Prove the product works, not just that it compiles. See
# references/proof-of-done.md for the full template.
set -euo pipefail
EV="${1:?evidence dir}"

# 1. clean build from nothing   2. tests/types/lint   3. it actually starts
# 4. real browser journeys      5. screenshots -> $EV  6. a11y  7. perf budget
# 8. websites: SEO baseline + Core Web Vitals budgets (references/proof-of-done.md)

echo "proof.sh: no evidence steps configured yet — edit .duo-build/proof.sh"
exit 1
