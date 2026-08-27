#!/usr/bin/env bash
# Offline, creds-free. Multi-table retail star + IIF + Filter.
set -euo pipefail

CASE_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$CASE_DIR/../../.." && pwd)"
SKILL="$ROOT/skills/alteryx-to-sigma"
CLI="$SKILL/converter/cli.mjs"
YXMD="$SKILL/fixtures/retail-star.yxmd"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

[ -f "$CLI" ] || { echo "FAIL: converter bundle missing: $CLI"; exit 1; }
[ -f "$YXMD" ] || { echo "FAIL: fixture missing: $YXMD"; exit 1; }

node "$CLI" "$YXMD" --connection PLACEHOLDER-CONNECTION-ID \
  --out "$TMP/dm.json" --gaps-out "$TMP/gaps.json"

python3 - "$TMP/dm.json" "$TMP/gaps.json" <<'PY'
import json, sys, re
dm = json.load(open(sys.argv[1]))
gaps = json.load(open(sys.argv[2]))
stats = dm.get("stats") or {}
assert stats.get("elements") >= 4, stats
assert stats.get("dbtOfframps", 0) == 0, stats
assert stats.get("converted") == 10, stats
els = dm["dataModel"]["pages"][0]["elements"]
assert len(els) >= 4, len(els)
named = [c for e in els for c in (e.get("columns") or []) if c.get("name")]
names = {c["name"] for c in named}
assert "Gross Margin Pct" in names, names
assert "Channel Group" in names, names
formulas = " ".join(c.get("formula") or "" for c in named)
assert re.search(r"\bIf\s*\(", formulas), formulas
assert not re.search(r"\bIIF\s*\(", formulas, re.I), formulas
warns = "\n".join(dm.get("warnings") or [])
assert "Filter" in warns and "IS_CANCELLED" in warns, warns
assert not any(g.get("kind") == "dbt-offramp" for g in (gaps.get("dbtOfframps") or []))
PY

python3 "$ROOT/corpus/lib/corpus_check.py" normalize "$TMP/dm.json" "$TMP/data-model.json"
cmp "$TMP/data-model.json" "$CASE_DIR/golden/data-model.json"
echo "alteryx/retail-star: 6 inputs + joins + IIF + Filter (local converter)"
