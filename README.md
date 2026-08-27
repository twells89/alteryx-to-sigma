# alteryx-to-sigma

Claude Code plugin for migrating **Alteryx Designer** workflows (`.yxmd`) to
**Sigma Computing**, in the same format and phase structure as the
[sigma-migration-skills](https://github.com/twells89/sigma-migration-skills)
converters (Tableau, Power BI, Qlik, ThoughtSpot, QuickSight, Cognos,
MicroStrategy, SSRS).

**Two things make this converter different from its siblings.**

1. **Data-model only.** An Alteryx canvas is an ETL graph, not a dashboard.
   There is no report surface to reproduce, so this skill builds a Sigma
   **data model** and stops. It never invents a workbook, never writes a
   layout, and never runs visual QA — those gates are honestly N/A, not
   skipped.
2. **Conversion is local, and the `.yxmd` never leaves the box.** The
   converter is TypeScript that ships *inside* the skill
   (`converter/alteryx.ts`, bundled to a dependency-free
   `converter/cli.mjs`). Plain `node`, no network at convert time, no hosted
   MCP. A customer's workflow XML is parsed on their machine.

## The design contract: flag, never fake — and know when the answer is dbt

Sigma is a **semantic layer** (warehouse tables + relationships + metrics +
governed calc columns). Alteryx is frequently **ETL** (reshape rows, land
files, run Python, write a table). Forcing ETL through Sigma formulas
produces a model that POSTs cleanly and then returns the wrong grain, blank
columns, or `type=error`.

So every tool on the canvas is censused into one of four dispositions, and
nothing is silently dropped:

| Disposition | Meaning |
|---|---|
| `converted` | Warehouse Input Data, two-input Join (composite keys; relationship on the fact/wider side), Formula (mapped functions + IF/ENDIF; cross-table refs qualified onto a derived view), ungrouped Summarize, Select hide/rename |
| `ignored` | Browse / Comment / Sort — no data change, nothing to port |
| `dbt-offramp` | Union, Join Multiple, L/R unjoin, **grouped** Summarize, file/CSV inputs, Crosstab/Transpose, Unique/Sample, macros/Python/In-DB, unmapped functions (`REGEX_Replace`, `DateTimeParse`, `Switch`, …) |
| `gap` | Anything unrecognized — flagged, never assumed safe |

When `stats.dbtOfframps > 0` the agent must **stop claiming the workflow
lives in Sigma**, show the offramp list with its per-tool dbt hint, and
recommend a dbt (or warehouse SQL) model that Sigma then reads as a
materialized table. Full rule table:
[`refs/dbt-offramp.md`](skills/alteryx-to-sigma/refs/dbt-offramp.md).
Per-tool coverage:
[`refs/yxmd-coverage.md`](skills/alteryx-to-sigma/refs/yxmd-coverage.md).

## What's in the box

| Skill | What it does |
|---|---|
| [`skills/alteryx-to-sigma`](skills/alteryx-to-sigma/SKILL.md) | The converter: `.yxmd` → Sigma data-model spec → reuse-check → POST + readback → column-type hard gate. Driven end-to-end by `scripts/migrate-alteryx.rb`. |
| [`skills/alteryx-assessment`](skills/alteryx-assessment/SKILL.md) | Read-only, file-based estate inventory: point it at a folder of `.yxmd` exports and get a `sigma-dm` vs `dbt-first` shortlist scored by the converter's *actual* coverage (it shells the same bundle, so it cannot drift). Writes nothing to Alteryx or Sigma. |

## Install

```bash
# In Claude Code:
/plugin marketplace add twells89/alteryx-to-sigma
/plugin install alteryx-to-sigma
```

Then just ask: *"migrate this Alteryx workflow to Sigma"* / *"assess my
Alteryx estate."*

Or clone and run the scripts directly — nothing here requires the plugin
runtime.

## Quick start (offline — no Sigma tenant, no credentials)

```bash
git clone https://github.com/twells89/alteryx-to-sigma
cd alteryx-to-sigma

# Convert a bundled fixture. The committed cli.mjs is self-contained:
# no npm install, no network.
node skills/alteryx-to-sigma/converter/cli.mjs \
  skills/alteryx-to-sigma/fixtures/orders-join.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID \
  --out /tmp/dm.json --gaps-out /tmp/gaps.json

# Inventory a folder of workflows (read-only):
ruby skills/alteryx-assessment/scripts/inventory.rb \
  --dir skills/alteryx-to-sigma/fixtures --out /tmp/readout.json
```

## End to end (needs a Sigma org)

Store credentials once — `setup.rb` writes both `~/.claude/settings.json`
(Claude Code loads it automatically) and `~/.sigma-migration/env` (every
script here auto-sources it, so any agent or plain shell works):

```bash
cd skills/alteryx-to-sigma
ruby scripts/setup.rb        # or --client-id/--client-secret for automation

ruby scripts/migrate-alteryx.rb \
  --yxmd path/to/workflow.yxmd \
  --connection-id "$SIGMA_CONNECTION_ID" \
  [--database DEMO_DB --schema DEMO] \
  [--folder "$SIGMA_FOLDER_ID"] \
  --workdir /tmp/alteryx-run
```

That sequences convert → signature → reuse-check → POST + readback and stops
at the first hard-gate failure. `--database` / `--schema` override the
catalog path parsed from the ODBC `File` string, for when the `.yxmd` was
built against a different environment. `folderId` is required on create; the
poster auto-picks a writable folder (preferring one named ALTERYX /
MIGRATION / TEST) unless you pass `--folder`.

### The hard gate

`/v2/dataModels/{id}/columns` must come back with **zero `type=error`
columns**. A 200 on the POST with a runtime-broken formula is a failure, not
a pass — a formula that references a column that did not survive the
conversion returns `type=error`, and that is precisely the class of bug a
"the POST succeeded" claim would hide. Only after that guard passes does
`migrate-alteryx.rb` write `parity-final.json` with `status=PASS`.

Numeric warehouse-vs-Sigma metric comparison is the documented follow-up when
the same warehouse is reachable. There is no Alteryx engine API to query, so
a three-way check is not available; the skill says so rather than inventing a
green number.

## Prerequisites

| | |
|---|---|
| `.yxmd` / `.yxmc` export | Alteryx Designer → Save. **No** Alteryx Server/Gallery credentials needed. If MetaInfo is empty, run the workflow once in Designer and re-export so column names are in the XML. |
| Node | 22+ (to run `converter/cli.mjs`; only needed for a rebuild's `npm ci`) |
| Ruby | 3.x (orchestrator + assessment scripts) |
| Python | 3.9+ (corpus checks, gap escalation) |
| Sigma | An org + OAuth client, and read access to the same warehouse the workflow's Input Data tools point at — Sigma reads it live. Only needed from the POST step onward. |

Token minting is shell-neutral: `scripts/get-token.sh` prints the bash
`export` idiom, and `scripts/get_token.py --workdir <dir>` writes a 0600
`auth.json` that the Ruby scripts read — so PowerShell and cmd work too.

## Tests

Everything below is offline and creds-free.

```bash
# Converter unit tests (24)
( cd skills/alteryx-to-sigma/converter && npm ci && npm test )

# Regression corpus: 3 cases, golden byte-compare against the shipped bundle
./corpus/run-corpus.sh --check

# Assessment readout (estate count + lane assignment)
./tools/test-assessment-inventory.sh

# Gates
ruby tools/check-alteryx-bundle.rb    # cli.mjs is fresh vs converter/*.ts
ruby tools/check-agent-variants.rb    # generated/ matches SKILL.md
```

CI runs all of these on every push and PR. The assessment test runs on
**both** Ubuntu and macOS on purpose — the estate-count regression it pins
only reproduces on a case-insensitive filesystem.

## Repo layout

```
.claude-plugin/plugin.json    # Claude Code plugin manifest
skills/
  alteryx-to-sigma/           # SKILL.md, converter/, scripts/, refs/, fixtures/
  alteryx-assessment/         # SKILL.md, scripts/
corpus/                       # creds-free regression cases + goldens
docs/phase-schema.md          # canonical C1–C10 arc + this skill's mapping
tools/                        # freshness/drift gates + the offline test
```

Each skill's `generated/` holds Cursor / Codex / Cline / Continue variants
derived from `SKILL.md` by `tools/gen-agent-variants.rb`, so every coding
agent reads the same instructions. Edit `SKILL.md`, then:

```bash
ruby tools/gen-agent-variants.rb --all && ruby tools/check-agent-variants.rb
```

## Editing the converter

`converter/cli.mjs` is **generated** — production runs the bundle, so a
`.ts` edit that ships without re-bundling silently ships the old behavior.
After touching any `converter/*.ts`:

```bash
( cd skills/alteryx-to-sigma/converter && npm ci && npm run bundle )
ruby tools/check-alteryx-bundle.rb --write   # refresh the freshness hash
```

`tools/check-alteryx-bundle.rb` hashes the bundled TS sources (not the
esbuild output, which varies by version) and fails CI if they drift from
`PROVENANCE.json`.

## Data handling

Nothing in this repo phones home. Conversion is a pure local parse; the only
network calls are the Sigma REST API from the POST/readback step onward, and
the fixtures are synthetic (`DEMO_DB.DEMO`) — no customer names, no tokens.
`.gitignore` keeps real `.yxmd`/`.yxmc`/`.yxdb` exports and run artifacts out
of commits.

## Status

Maturity: **foundation**. Converter unit tests, the 3-case corpus, and a live
POST + column-type gate against a Snowflake-backed Sigma org all pass; the
numeric warehouse parity follow-up is documented but not automated. Coverage
beyond the table above is a gap, not a silent failure — see
`refs/yxmd-coverage.md` and file one with
`python3 skills/alteryx-to-sigma/scripts/escalate-gap.py --skill alteryx-to-sigma --category skill …`
(dry run until you add `--yes`).

## License

MIT — see [LICENSE](LICENSE).
