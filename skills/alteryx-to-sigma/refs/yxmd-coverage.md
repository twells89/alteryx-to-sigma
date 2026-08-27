# Alteryx tool coverage

Every tool in a `.yxmd` is censused. Nothing is silently dropped. Sigma is
the **semantic layer** (tables, relationships, calc columns, metrics).
Alteryx is often **ETL** (reshape rows, land files, run macros). ETL that
Sigma cannot represent honestly is a **dbt offramp** — see
`dbt-offramp.md`.

| Family | Alteryx plugin (typical) | Disposition |
|---|---|---|
| input | `DbFileInput` | **converted** → warehouse-table element. File/CSV/YXDB sources additionally offramp (land in the warehouse first). |
| join | `Join` (two inputs, **Join/J output**) | **converted** → `relationships[]` (assumed N:1 on the wider/fact side; composite keys supported) |
| join-unjoin | `Join` Left/Right unjoin output | **dbt-offramp** (anti-join grain Sigma cannot express) |
| formula | `Formula` | **converted** → calc column on the upstream input. Unmapped functions (regex, DateTimeParse, Switch, …) offramp to dbt. |
| summarize | `Summarize` without GroupBy | **converted** → metrics (`Sum`/`Avg`/`CountDistinct`/…) |
| summarize-groupby | `Summarize` **with** GroupBy | **dbt-offramp** — new grain, not a metric on the ungrouped table |
| select | `AlteryxSelect` | **converted** (deselected columns hidden; renames applied as `name`) |
| filter | `Filter` | **converted** as a warning / optional RLS — never invented as a policy |
| ui | Browse, Comment, Tool Container | **ignored** (no data change) |
| sort | `Sort` | **ignored** (Sigma orders at query time) |
| union | `Union` | **dbt-offramp** (`UNION ALL`) |
| join-multiple | `JoinMultiple` | **dbt-offramp** (3+ table join) |
| append | `AppendFields` | **dbt-offramp** (cartesian / bind) |
| crosstab / transpose | `CrossTab`, `Transpose` | **dbt-offramp** (`dbt_utils.pivot` / `unpivot`) |
| unique / sample | `Unique`, `Sample` | **dbt-offramp** (DISTINCT / TABLESAMPLE) |
| generate-rows / text-to-columns / running-total / record-id | Generate Rows, Text To Columns, Running Total, Record ID | **dbt-offramp** (grain / window / surrogate key) |
| cleanup | Find Replace, Fuzzy Match, Imputation, Tile | **dbt-offramp** (prep model) |
| multi-formula | Multi-Field Formula, Multi-Row Formula | **dbt-offramp** (windowed ETL) |
| output | `DbFileOutput` | **dbt-offramp** — that output **is** the dbt model Sigma should read |
| in-db | In-DB tool family | **dbt-offramp** — promote the warehouse SQL as a dbt model |
| script-macro | Macro, Python, R, Download, Dynamic Input, Command | **dbt-offramp** (external job that lands a table) |
| unknown | anything else | **gap** — flagged, never assumed safe |

## Formula function map (converted)

`ToString`→`Text`, `ToNumber`→`Number`, `Trim`, `Uppercase`→`Upper`,
`Lowercase`→`Lower`, `Left`/`Right`/`Substring`, `Length`→`Len`,
`Contains`, `FindString`→`Find`, `PadLeft`→`PadStart`, `PadRight`→`PadEnd`,
`ReplaceFirst`/`ReplaceChar`→`Replace`, `Abs`/`Ceil`→`Ceiling`/`Floor`/
`Round`/`Sqrt`/`Pow`→`Power`/`Log`/`Log10`, `DateTimeYear`→`Year` (and
Month/Day/Hour/Minute/Second), `DateTimeTrim`→`DateTrunc`,
`DateTimeDiff`→`DateDiff`, `DateTimeAdd`→`DateAdd`, `DateTimeNow`→`Now`,
`DateTimeToday`→`Today`, `IsNull`/`IsEmpty`→`IsNull`, `IIF`→`If`,
`Min`/`Max`. IF/ENDIF and SQL CASE → nested `If()`.

Unmapped (offramp, not passed through): `REGEX_Replace`, `GetWord`,
`DateTimeParse`, `DateTimeFormat`, `ToDate`, `Switch`, `CharFromInt`,
`Md5_ASCII`, `TrimLeft`/`TrimRight`, `UrlEncode`, `JSON_Parse`, others in
`UNMAPPED_ALTERYX_FUNCS`.

## Converter is local

`converter/alteryx.ts` bundled as `converter/cli.mjs`. No MCP, no hosted
`convert_alteryx_to_sigma`, no network at convert time.
