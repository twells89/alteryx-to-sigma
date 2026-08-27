# alteryx / retail-star

Neutralized stand-in for a retail analytics Alteryx canvas (the original
Desktop `.yxmd` is not in git). Six warehouse Inputs (ORDER_FACT + five
dims), two Joins (CUSTOMER_KEY, PRODUCT_KEY), Formula `GROSS_MARGIN_PCT` +
`CHANNEL_GROUP` (`IIF` → `If()`), Filter `IS_CANCELLED = 0`.

Referenced from the plugin's `fixtures/` dir, not duplicated.

## Converter

```
node skills/alteryx-to-sigma/converter/cli.mjs \
  skills/alteryx-to-sigma/fixtures/retail-star.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID \
  --out dm.json --gaps-out gaps.json
```

Then normalize:

```
python3 corpus/lib/corpus_check.py normalize dm.json golden/data-model.json
```

## Features exercised

- Six warehouse Input Data tools → warehouse-table elements
- Two Joins → `relationships[]` on the fact (assumed N:1)
- Formula `IIF` → Sigma `If()` (`CHANNEL_GROUP`); ratio calc (`GROSS_MARGIN_PCT`)
- Filter surfaced as a warning (optional RLS)
- Derived `"Order Fact View"` because the fact has relationships
- Tool census: 10/10 converted, 0 dbt-offramps

## Known parity reference

Synthetic DEMO_DB.DEMO star — not the original Desktop file. Live POST of
`orders-join` is the column-type gate; this case locks the multi-table shape
the browser harness used to probe.

## Expectations

```json
{
  "artifacts": [
    {"path": "../../../skills/alteryx-to-sigma/fixtures/retail-star.yxmd", "format": "xml"},
    {"path": "checks.sh", "format": "text"}
  ],
  "goldens": {
    "data-model.json": {
      "pages": 1,
      "elements": 7,
      "columns": 36,
      "metrics": 0,
      "relationships": 2,
      "warnings": 11,
      "element_names": ["CUSTOMER_DIM", "PRODUCT_DIM", "STORE_DIM", "DATE_DIM", "CHANNEL_DIM", "ORDER_FACT", "Order Fact View"]
    }
  }
}
```
