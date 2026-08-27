# When Alteryx logic belongs in dbt, not Sigma

Sigma is a **semantic layer** (warehouse tables + relationships + metrics +
governed calc columns). Alteryx Designer is often an **ETL canvas** (reshape
rows, land files, run Python, write a new table). Forcing ETL through Sigma
formulas produces a model that POSTs and then returns wrong grain, blank
columns, or `type=error`.

The converter **never fakes** that class of tool. It emits a `dbt-offramp`
gap (also printed on stderr and written to `dbt-offramp.json` by
`migrate-alteryx.rb`) with a concrete dbt/SQL hint.

## Rule of thumb

| If the Alteryx tool… | Do this |
|---|---|
| Reads a live warehouse table, joins two tables on keys, adds a row-level calc, or defines an ungrouped aggregate | Convert to the Sigma data model (this skill). |
| Changes grain (Union, Unique, GroupBy Summarize, Generate Rows, Crosstab, Transpose, Sample) | **dbt model** (or equivalent warehouse SQL). Point Sigma at the materialized table. |
| Lands a file (CSV / Excel / YXDB) | `dbt seed` or COPY/LOAD, then Sigma on the landed table. |
| Writes an Output Data table | That output **is** the dbt model. Recreate it in dbt; do not replay the canvas in Sigma. |
| Is In-DB SQL already | Promote that SQL to dbt; Sigma reads the model. |
| Is a macro / Python / R / Download / Fuzzy Match | External job that lands a table, then Sigma. |

## What the agent must do

1. Run the local converter (`node converter/cli.mjs` / `migrate-alteryx.rb`).
2. If `stats.dbtOfframps > 0`, **stop claiming the workflow is fully in Sigma**.
   Read `gaps` / `dbt-offramp.json`. Present the dbt (or Snowflake/Databricks
   SQL) recommendation **before** POSTing a half-model — the user chooses
   whether to land the ETL first or post the convertible slice.
3. Never translate a dbt-offramp tool into a Sigma calc column "so something
   shows up." Flag it (`python3 scripts/escalate-gap.py --category skill`
   if they want a tracking issue in this repo; it is a dry run until `--yes`).
   `--category converter` also routes here, because the converter lives in
   this skill — there is no hosted Alteryx converter to mirror to.
4. After the dbt model exists, re-run this skill against a `.yxmd` whose Input
   Data tools point at the new table (or just author the Sigma DM from those
   tables via `sigma-data-models`).

## Example

An Alteryx canvas that unions regional extracts, fuzzy-matches customers,
then Summarizes by region:

- Union + Fuzzy Match + grouped Summarize → **three dbt models** (union,
  cleaned customers, `agg_by_region`).
- Sigma data model → one warehouse-table element on `agg_by_region` plus
  metrics. That is the honest migration, not 40 calc columns on the raw
  extracts.
