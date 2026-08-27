#!/usr/bin/env bash
# Offline, creds-free. Conversion is local — never a hosted MCP.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CASE_DIR/../../.." && pwd)"
SKILL="$ROOT/skills/alteryx-to-sigma"
CLI="$SKILL/converter/cli.mjs"
YXMD="$SKILL/fixtures/orders-join.yxmd"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$CLI" ] || { echo "FAIL: converter bundle missing: $CLI"; exit 1; }
[ -f "$YXMD" ] || { echo "FAIL: fixture missing: $YXMD"; exit 1; }

# Orchestrator must resolve to the in-skill bundle, never a hosted converter.
printed="$("$SKILL/scripts/migrate-alteryx.rb" --print-converter)"
case "$printed" in
  */converter/cli.mjs) ;;
  *) echo "FAIL: --print-converter expected .../converter/cli.mjs, got: $printed"; exit 1 ;;
esac

if grep -E "sigma-data-model-mcp|convert_alteryx_to_sigma|~/sigma-data-model" \
     "$SKILL/scripts/migrate-alteryx.rb" "$SKILL/converter/cli.ts" >/dev/null; then
  echo "FAIL: orchestrator/CLI still references a hosted converter"
  exit 1
fi

node "$CLI" "$YXMD" --connection PLACEHOLDER-CONNECTION-ID \
  --out "$TMP/dm.json" --gaps-out "$TMP/gaps.json"

python3 - "$TMP/dm.json" "$TMP/gaps.json" <<'PY'
import json, sys
dm = json.load(open(sys.argv[1]))
gaps = json.load(open(sys.argv[2]))
stats = dm.get("stats") or {}
assert stats.get("dbtOfframps", 0) == 0, stats
assert stats.get("gaps", 0) == 0, stats
assert stats.get("converted") == 4, stats
assert stats.get("tools") == 4, stats
assert not any(g.get("kind") == "dbt-offramp" for g in gaps.get("dbtOfframps") or [])
assert "dataModel" in dm
PY

python3 "$ROOT/corpus/lib/corpus_check.py" normalize "$TMP/dm.json" "$TMP/data-model.json"
cmp "$TMP/data-model.json" "$CASE_DIR/golden/data-model.json"
echo "alteryx/orders-join: local converter + golden match (no hosted converter)"
