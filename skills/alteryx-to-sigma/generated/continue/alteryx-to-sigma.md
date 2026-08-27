<!--
Auto-generated from SKILL.md by tools/gen-agent-variants.rb.
Do not edit by hand — edit SKILL.md and re-run: ruby tools/gen-agent-variants.rb --all
-->

> Convert an Alteryx Designer workflow (.yxmd XML) into a Sigma data model. DbFileInput tools become warehouse tables, Join tools become relationships, Formula tools become calculated columns, Summarize tools become metrics. Data-model only — Alteryx has no dashboard surface, so this skill never builds a workbook.

# Alteryx → Sigma (data model)

> **Data-model only.** An Alteryx Designer workflow is an ETL graph, not a
> dashboard. This skill converts `.yxmd` XML into a Sigma data model and
> posts it. It does **not** build a workbook, apply `layout.xml`, or run
> visual PNG QA — those gates are N/A. Defer workbook authoring (if you
> want charts on top of the posted DM) to `sigma-workbooks`.

> Phase numbering is local to this skill; the canonical Assess→Discover→
> Reuse→Convert→Post-DM→Build→Layout→Parity→Security→Enhance arc and this
> skill's mapping live in `docs/phase-schema.md` at the repo root.

The converter lives **in this skill** (`converter/alteryx.ts`, bundled as
`converter/cli.mjs`). Conversion is **local only** — never call the hosted
`sigma-data-model` MCP, never `convert_alteryx_to_sigma`, never send the
`.yxmd` off-box. Rebuild after a `.ts` edit with `npm run bundle` in
`converter/` (plain `node`, no tsx, no MCP checkout).

<!-- mandatory-pre-read -->
Read `refs/yxmd-coverage.md` (tool census) and `refs/dbt-offramp.md`
(ETL that belongs in dbt, not Sigma) before converting anything beyond a
simple Input + Join + Formula canvas.
<!-- /mandatory-pre-read -->

Run from this skill directory.

## Prerequisites

- An Alteryx `.yxmd` (or `.yxmc`) export of the workflow. Designer → Save.
  No Alteryx Server/Gallery credentials are required.
- Sigma credentials, stored once with `ruby scripts/setup.rb` (writes
  `~/.claude/settings.json` + `~/.sigma-migration/env`; every script here
  auto-sources the neutral file). To mint a token by hand:
  `eval "$(scripts/get-token.sh)"`, or `python3 scripts/get_token.py
  --workdir <dir>` on a shell that cannot run the bash idiom.
- The same warehouse the workflow's Input Data tools read. Sigma reads it
  live; `--database` / `--schema` override the path parsed from the ODBC
  File string when the `.yxmd` was built against a different catalog.

```bash
ruby scripts/migrate-alteryx.rb --yxmd <workflow.yxmd> --connection-id <id>
```

## Phase 0 — Assess (C1)

Defer estate inventory to `alteryx-assessment` (file-based scan of a folder
of `.yxmd` files). For a single workflow, skip to Phase 1.

## Phase 1 — Discover (C2)

The `.yxmd` **is** the source of truth. Open it (XML) and confirm:

- `<AlteryxDocument>` root
- Input Data tools (`DbFileInput` / `AlteryxDbFileInput`) with warehouse
  paths in the `<File>` string
- Join / Formula / Summarize / Select / Filter tools you expect to land

Unsupported tools (Browse, Union, Crosstab, Download, macros, In-DB, etc.)
are skipped with warnings — never silently dropped from the warning list.
See `refs/yxmd-coverage.md`.

If MetaInfo is empty, run the workflow once in Designer and re-export so
column names are in the XML; otherwise columns are inferred from Formula /
Summarize refs (noisier).

## Phase 1.5 — Reuse-check (C3)

Before creating a DM, score existing Sigma DMs and reuse on a strong match
(avoid sprawl). Mirrors tableau Phase 1.5:

```bash
node converter/cli.mjs <workflow.yxmd> --connection <id> --out dm.json
ruby scripts/emit-signature.rb --spec dm.json --out signature.json
ruby scripts/find-or-pick-dm.rb --workbook-signature signature.json --out dm-match.json --auto-pick
```

`migrate-alteryx.rb` runs this automatically. `--force-new` skips reuse.

## Phase 2 — Convert (C4)

```bash
node converter/cli.mjs <workflow.yxmd> \
  --connection <SIGMA_CONNECTION_ID> \
  [--database DEMO_DB --schema DEMO --name "Orders"] \
  --out dm.json
```

Mapping (see `refs/yxmd-coverage.md` for the full tool list):

| Alteryx | Sigma |
|---|---|
| Input Data (`DbFileInput`) | `warehouse-table` element (`source.path` from the ODBC File string) |
| Join | `relationships[]` on the **fact** side (assumed N:1; composite keys; L/R unjoin → dbt) |
| Formula | calculated columns (Alteryx functions → Sigma; IF/ENDIF → `If()`) |
| Summarize | metrics (`Sum`/`Avg`/`CountDistinct`/…) |
| Select (renames / deselects) | hide deselected columns; apply `name` overrides |
| Filter | warning — consider as RLS (Phase Security) |
| Cross-element Formula refs | moved onto the derived `"<Table> View"` element as `[SRC/REL/Field]` |

`converter/cli.mjs` is self-contained (`node`, no npm, no network, no MCP).
It also writes a `gaps` array: every tool is `converted` / `ignored` /
`dbt-offramp` / `gap`. If `stats.dbtOfframps > 0`, read
`refs/dbt-offramp.md` and **recommend a dbt (or warehouse SQL) model**
for those tools before claiming the workflow lives in Sigma. Do not fake
Union / Crosstab / grouped Summarize / file inputs / macros as calc columns.

```bash
node converter/cli.mjs <workflow.yxmd> --connection <id> --out dm.json --gaps-out dbt-offramp.json
```

## Phase 3 — Post the data model + read back (C5)  ← HARD GATE

POST the DM, then **read back** the real element/column ids — never keep
client-side ids as the source of truth:

```bash
ruby scripts/post-and-readback.rb --spec dm.json --out dm-map.json
```

`folderId` is required on create. The poster auto-picks a writable folder
(preferring a name matching ALTERYX / MIGRATION / TEST); override with
`--folder <id>` or `SIGMA_FOLDER_ID`.

Hard gate: `/v2/dataModels/{id}/columns` must contain zero `type=error`
columns. A 200 POST with a runtime-broken formula is a fail.

## Phase 4 — Workbook (C6) — N/A

Alteryx workflows have no dashboard/report surface. **Do not** invent a
workbook. If the user wants charts on the posted DM, hand off to
`sigma-workbooks`.

## Phase 5 — Layout (C7) — N/A

No workbook is built, so there is no `put-layout.rb` / `layout.xml` and no
last write of layout. Visual PNG QA is also N/A; see
`refs/layout-visual-qa.md`.

## Phase 6 — Verify parity (C8)  ← HARD GATE, never skip

For this skill the hard parity gate is the C5 column-type guard (formulas
resolve). `migrate-alteryx.rb` writes `parity-final.json` with
`status=PASS` only after that guard succeeds.

Numeric warehouse-vs-Sigma metric comparison is the follow-up when the
same warehouse is reachable (query the posted DM's metrics against the
Input Data tables). There is no Alteryx engine API to query for a
three-way check. Never skip the column-type gate; never fake GREEN.

`assert-phase6-ran.rb` is **not** vendored — Alteryx is data-model-only,
so the workbook completion gate (layout, tiles, visual PNG) has nothing
to point at. The C5 column-type guard plus `parity-final.json` is the
hard gate.

## Security: RLS / CLS (C9)

Detect Filter tools always (`Filter: <expr> — consider adding as RLS` in
converter warnings). Alteryx has no first-class RLS/CLS on a `.yxmd`;
Filter expressions are the closest analogue. Apply to Sigma user-attributes
+ DM filters **opt-in** — never invent a policy from a Filter that was
just an analytic subset. CLS is not present in Designer workflows.

## Too complex for Sigma → dbt (warehouse)

Alteryx canvases that reshape rows or land files are ETL. Sigma will not
be a better Alteryx. When the converter emits `dbt-offramp`:

1. Show the user the tool list + `dbtHint` (also in `dbt-offramp.json`).
2. Recommend a dbt model (or equivalent Snowflake/Databricks SQL) that
   performs that step, materialized as a table.
3. Point Sigma at **that** table (re-run this skill, or author via
   `sigma-data-models`). The Output Data tool on the canvas usually *is*
   the model you want.
4. Never translate those tools into Sigma formulas so the POST "succeeds."

Worked rule table: `refs/dbt-offramp.md`.

## Gaps

Unsupported / unmapped tools are already in `gaps` (kind `gap` or
`dbt-offramp`). Optional tracking issue (dry-run by default — it files
nothing without `--yes`):
`python3 scripts/escalate-gap.py --skill alteryx-to-sigma --category skill`.
Both `skill` and `converter` route to this repo, because the converter
lives here (`converter/*.ts`) — there is no hosted Alteryx MCP tool. Never
fake a feature; flag it. Coverage: `refs/yxmd-coverage.md`.
