#!/usr/bin/env bash
# Offline, creds-free regression test for skills/alteryx-assessment.
#
# Pins the estate COUNT against the three bundled fixtures. The count is the
# number the shortlist and the customer-facing readout are built from, so a
# silent doubling is a wrong readout, not a cosmetic bug.
#
# Regression guarded: inventory.rb used to glob `*.{yxmd,yxmc,YXMD,YXMC}`.
# On a case-insensitive filesystem (macOS APFS/HFS+) that matches every file
# TWICE -- 3 fixtures were reported as 6 workflows, each converted twice.
# Linux CI would NOT have caught it, which is exactly why it is pinned here.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/skills/alteryx-to-sigma/fixtures"
OUT="$(mktemp -d)/readout.json"
trap 'rm -rf "$(dirname "$OUT")"' EXIT

ruby "$ROOT/skills/alteryx-assessment/scripts/inventory.rb" --dir "$FIXTURES" --out "$OUT" >/dev/null 2>&1

python3 - "$OUT" <<'PY'
import json, sys, collections
d = json.load(open(sys.argv[1]))

n_on_disk = 3  # orders-join, retail-star, union-offramp
assert d["count"] == n_on_disk, f'count {d["count"]} != {n_on_disk} on-disk fixtures (double-match?)'
assert len(d["workflows"]) == n_on_disk, f'{len(d["workflows"])} workflow records for {n_on_disk} files'

files = [w["file"] for w in d["workflows"]]
dupes = [f for f, c in collections.Counter(files).items() if c > 1]
assert not dupes, f"workflow assessed more than once: {dupes}"

# Lane assignment is the whole point of the readout: a clean Input+Join+Formula
# canvas is a cheap Sigma DM; a Union canvas must go to the dbt-first lane.
assert sorted(d["sigma_dm_shortlist"]) == ["orders-join.yxmd", "retail-star.yxmd"], d["sigma_dm_shortlist"]
assert [w["file"] for w in d["dbt_first"]] == ["union-offramp.yxmd"], d["dbt_first"]
assert d["dbt_first"][0]["families"] == ["union"], d["dbt_first"][0]

print(f'alteryx-assessment: {d["count"]} workflow(s), '
      f'{len(d["sigma_dm_shortlist"])} sigma-dm, {len(d["dbt_first"])} dbt-first — no double-count')
PY
