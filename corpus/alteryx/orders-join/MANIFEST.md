# alteryx / orders-join

Neutralized Alteryx Designer workflow: warehouse Input Data on
`DEMO_DB.DEMO.ORDER_FACT` ⋈ `DEMO_DB.DEMO.CUSTOMER_DIM` plus a Formula that
references a related-table column (`CUSTOMER_SEGMENT`) — the converter lifts
that calc onto the derived `"Order Fact View"` element.

Referenced from the plugin's `fixtures/` dir, not duplicated.

## Converter

The **in-repo converter** (not a hosted MCP). Production runs the bundled
`converter/cli.mjs` (plain `node`):

```
node skills/alteryx-to-sigma/converter/cli.mjs \
  skills/alteryx-to-sigma/fixtures/orders-join.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID \
  --out dm.json --gaps-out gaps.json
```

Then normalize:

```
python3 corpus/lib/corpus_check.py normalize dm.json golden/data-model.json
```

Rebuild after a `.ts` edit: `cd .../converter && npm install && npm run bundle`.

## Features exercised

- DbFileInput ODBC File string → warehouse-table `source.path`
- Join → `relationships[]` (keys traced back to inputs)
- Formula `IIF` → Sigma `If()`, moved onto derived `"Order Fact View"` with
  both related (`[ORDER_FACT/CUSTOMER_DIM/…]`) and same-table
  (`[ORDER_FACT/Gross Revenue]`) refs fully qualified
- Join → `relationships[]` (assumed N:1 on the fact; composite keys supported
  on other canvases)
- Tool census: 4/4 converted, 0 dbt-offramps, 0 silent drops
- Local-only: `migrate-alteryx.rb --print-converter` resolves to `converter/cli.mjs`

## Known parity reference

Foundation fixture — not live-validated. Column-type guard is the hard gate
once posted. ETL that does not fit Sigma is a dbt offramp on other canvases
(`refs/dbt-offramp.md`); this case is the convertible Input+Join+Formula slice.

## Expectations

```json
{
  "artifacts": [
    {"path": "../../../skills/alteryx-to-sigma/fixtures/orders-join.yxmd", "format": "xml"},
    {"path": "checks.sh", "format": "text"}
  ],
  "goldens": {
    "data-model.json": {
      "pages": 1,
      "elements": 3,
      "columns": 14,
      "metrics": 0,
      "relationships": 1,
      "warnings": 5,
      "element_names": ["CUSTOMER_DIM", "ORDER_FACT", "Order Fact View"]
    }
  }
}
```
