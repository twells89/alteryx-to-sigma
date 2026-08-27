#!/usr/bin/env bash
# Offline, creds-free. Union must be a dbt offramp, never a fake Sigma union.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CASE_DIR/../../.." && pwd)"
SKILL="$ROOT/skills/alteryx-to-sigma"
CLI="$SKILL/converter/cli.mjs"
YXMD="$SKILL/fixtures/union-offramp.yxmd"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$CLI" ] || { echo "FAIL: converter bundle missing: $CLI"; exit 1; }
[ -f "$YXMD" ] || { echo "FAIL: fixture missing: $YXMD"; exit 1; }

node "$CLI" "$YXMD" --connection PLACEHOLDER-CONNECTION-ID \
  --out "$TMP/dm.json" --gaps-out "$TMP/gaps.json"

python3 - "$TMP/dm.json" "$TMP/gaps.json" <<'PY'
import json, sys
dm = json.load(open(sys.argv[1]))
gaps = json.load(open(sys.argv[2]))
stats = dm.get("stats") or {}
assert stats.get("dbtOfframps", 0) >= 1, stats
assert stats.get("elements") == 2, stats
union = [g for g in (gaps.get("gaps") or []) if g.get("family") == "union"]
assert union and union[0].get("kind") == "dbt-offramp", gaps
kinds = [e.get("source", {}).get("kind") for e in dm["dataModel"]["pages"][0]["elements"]]
assert all(k == "warehouse-table" for k in kinds), kinds
PY

python3 "$ROOT/corpus/lib/corpus_check.py" normalize "$TMP/dm.json" "$TMP/data-model.json"
cmp "$TMP/data-model.json" "$CASE_DIR/golden/data-model.json"
echo "alteryx/union-offramp: Union is dbt-offramp (no fake Sigma union)"
