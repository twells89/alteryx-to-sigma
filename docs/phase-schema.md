# Canonical migration phase schema

Every converter skill in the
[sigma-migration-skills](https://github.com/twells89/sigma-migration-skills)
family walks the same arc, but each tool's SKILL.md numbers and names its
phases differently (numbering grew organically per tool and is load-bearing —
scripts, gates, and notes reference the local numbers). **Do NOT renumber any
skill's phases.** This document is the cross-skill Rosetta stone: when you need
"the parity gate" or "the reuse check" in an unfamiliar skill, look up its
local name here.

This repo vendors the canonical arc plus the `alteryx-to-sigma` mapping. The
full per-skill table for every sibling converter lives in the upstream repo at
`docs/phase-schema.md`.

## The canonical arc

| # | Canonical step | What it is |
|---|---|---|
| C1 | **Assess** | Inventory/scope the source estate; feature-gap scan; pick targets |
| C2 | **Discover** | Pull the actual source artifacts (model + report/dashboard defs, warehouse columns) |
| C3 | **Reuse-check** | Before creating a DM, look for an existing Sigma DM with the same signature (avoid sprawl) |
| C4 | **Convert** | Source model → Sigma data-model JSON (in-repo converter) |
| C5 | **Post-DM gate** | POST the DM, read back real element/column ids — hard gate before any workbook work |
| C6 | **Build workbook** | Report/dashboard → Sigma workbook spec wired to the DM ids, with every element completely placed in the layout on the create write |
| C7 | **Layout safety** | Preserve the complete layout on every write; make the final write layout-safe and last (stacked ≠ done; any write that omits layout wipes it) |
| C8 | **Parity hard gate** | Source values vs Sigma values (vs warehouse where possible) — mandatory, never skip |
| C9 | **Security / RLS** | Port detected RLS/CLS to Sigma user-attributes + DM filters (detect always; apply opt-in) |
| C10 | **Enhance** | Post-publish polish, UI-only features, optional extras |

## alteryx-to-sigma

Alteryx Designer uses "Phase" numbering. It is **data-model only** (no
workbook / no layout) — an Alteryx canvas is ETL, not a dashboard. ETL that
Sigma should not fake is a dbt/warehouse offramp
(`skills/alteryx-to-sigma/refs/dbt-offramp.md`).

| Canonical | alteryx-to-sigma |
|---|---|
| C1 Assess | `alteryx-assessment` skill (file-based `.yxmd` folder inventory) |
| C2 Discover | Phase 1 — parse the `.yxmd` (the file is the source of truth) |
| C3 Reuse-check | Phase 1.5 — `find-or-pick-dm.rb` (vendored unmodified) |
| C4 Convert | Phase 2 — `converter/cli.mjs` (local; no MCP). Input/Join/Formula/ungrouped Summarize → DM; everything else censused as ignored / dbt-offramp / gap |
| C5 Post-DM gate | Phase 3 — `post-and-readback.rb` (hard gate: zero `type=error` columns) |
| C6 Build workbook | Phase 4 — **N/A** (no dashboard surface; do not invent a workbook) |
| C7 Layout | Phase 5 — **N/A** (no `put-layout.rb` / `layout.xml`; no last write of layout) |
| C8 Parity hard gate | Phase 6 — column-type guard after POST (`parity-final.json`); numeric warehouse follow-up when reachable |
| C9 Security/RLS | Filter tools detected as warnings; apply opt-in |
| C10 Enhance | — (data-model only; nothing to polish in a workbook) |
