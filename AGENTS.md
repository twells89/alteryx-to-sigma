# AGENTS.md — alteryx-to-sigma

Migrate **Alteryx Designer** workflows (`.yxmd`) to **Sigma Computing**. Part of
the [sigma-migration-skills](https://github.com/twells89/sigma-migration-skills)
converter family; this repo is the standalone home for the Alteryx pair.

Packaged as a Claude Code plugin, but the skills are agent-neutral: each is a
`SKILL.md` (instructions) plus `scripts/` (Ruby/Python/shell) and `refs/`. Any
coding agent can run them by reading the `SKILL.md` and executing its scripts.
Cursor / Codex / Cline / Continue variants of each `SKILL.md` are generated into
`skills/<name>/generated/` — same content, per-agent packaging.

## Two invariants that override convenience

1. **Conversion is local.** Never call a hosted converter, never
   `convert_alteryx_to_sigma`, never send the `.yxmd` off-box. The converter is
   `skills/alteryx-to-sigma/converter/cli.mjs` — plain `node`, no network.
2. **Data-model only.** Alteryx has no dashboard surface. Do **not** invent a
   workbook, a layout, or visual QA to make the output look complete. If the
   user wants charts on the posted data model, hand off to `sigma-workbooks`.

## Which skill

| Intent | Skill | Path (read its `SKILL.md` in full first) |
|---|---|---|
| Convert one `.yxmd` → Sigma data model | `alteryx-to-sigma` | `skills/alteryx-to-sigma/` |
| Inventory a folder of `.yxmd`, get a shortlist | `alteryx-assessment` | `skills/alteryx-assessment/` |

Run scripts **from the skill directory** — script paths are relative
(`scripts/migrate-alteryx.rb`, `converter/cli.mjs`). `cd` in, then invoke.

## The rule that decides most conversions

Sigma is a semantic layer; Alteryx is often ETL. Every tool on the canvas is
censused as `converted` / `ignored` / `dbt-offramp` / `gap`. If
`stats.dbtOfframps > 0`, **stop claiming the workflow lives in Sigma** — read
`skills/alteryx-to-sigma/refs/dbt-offramp.md`, show the user the offramp list,
and recommend a dbt (or warehouse SQL) model that Sigma reads as a materialized
table. Never translate an offramped tool into a Sigma calc column so the POST
"succeeds."

## Hard gate

`/v2/dataModels/{id}/columns` must return **zero `type=error` columns**. A 200
POST with a runtime-broken formula is a failure. `migrate-alteryx.rb` writes
`parity-final.json` with `status=PASS` only after that guard passes. Never fake
GREEN; if the gate did not run, say so.

Canonical phase arc and this skill's mapping: [`docs/phase-schema.md`](docs/phase-schema.md).

## Before you commit

All offline and creds-free:

```bash
( cd skills/alteryx-to-sigma/converter && npm ci && npm test )
./corpus/run-corpus.sh --check
./tools/test-assessment-inventory.sh
ruby tools/check-alteryx-bundle.rb    # cli.mjs fresh vs converter/*.ts
ruby tools/check-agent-variants.rb    # generated/ matches SKILL.md
```

Edited a `converter/*.ts`? Re-bundle, or you ship the old behavior:

```bash
( cd skills/alteryx-to-sigma/converter && npm ci && npm run bundle )
ruby tools/check-alteryx-bundle.rb --write
```

Edited a `SKILL.md`? Regenerate the agent variants:

```bash
ruby tools/gen-agent-variants.rb --all
```

## Never commit

Real customer `.yxmd`/`.yxmc`/`.yxdb` exports, Sigma tokens, org slugs,
warehouse hostnames, or real table/dashboard names. Fixtures are synthetic
(`DEMO_DB.DEMO`) and must stay that way — reproduce a bug by its *shape*, never
by a customer's real names. `.gitignore` covers the common cases; it is not a
substitute for checking.
