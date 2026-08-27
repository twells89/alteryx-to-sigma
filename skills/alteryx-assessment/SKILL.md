---
name: alteryx-assessment
description: Inventory a folder of Alteryx Designer workflows (.yxmd) and produce a migration-readiness readout — tool mix, dbt-offramp density, and a value/cost-ranked shortlist. File-based and read-only; no Alteryx Server/Gallery write, no Sigma write.
---

# Alteryx migration assessment (read-only)

> File-based. Alteryx Server/Gallery APIs are out of scope for v1 — hand
> the agent a directory of `.yxmd` / `.yxmc` exports. Never writes to
> Alteryx or Sigma. Hands off to `alteryx-to-sigma` for a single workflow.

```bash
ruby scripts/inventory.rb --dir <folder-of-yxmd> --out readout.json
```

## Phase 0 — Connect

No auth. Point `--dir` at the export folder (Designer Save, or a git
checkout of workflows).

## Phase 1 — Inventory

`inventory.rb` parses each `.yxmd`, runs the **local** converter census
(`node ../alteryx-to-sigma/converter/cli.mjs --gaps-out -` is not required —
the script shells the same bundled CLI) and records per-workflow:

- tool count by family (`converted` / `ignored` / `dbt-offramp` / `gap`)
- whether Input Data tools are warehouse vs file
- presence of macros / Python / In-DB (always dbt-heavy)

Dedup near-identical canvases with `scripts/dup-dashboards.py` on the
workflow names if needed.

## Phase 2 — Score + shortlist

Complexity score (higher = more dbt work, convert later):

- `dbtOfframps` and `gaps` count
- file-input count (must land in the warehouse first)
- converted-only workflows (Input + Join + Formula) go to the **front** of
  the shortlist — they are cheap Sigma DM conversions
- Union / Crosstab / grouped Summarize / macro canvases go to a **dbt
  first** lane (`refs/dbt-offramp.md` in `alteryx-to-sigma`)

Hand the shortlist to `alteryx-to-sigma`. Do not POST anything from this
skill.
