# alteryx / union-offramp

Two warehouse Input Data tools stacked by a Union. Union is ETL Sigma cannot
represent as a relationship or calc — the converter must emit `dbt-offramp`
and must not invent a union element.

Referenced from the plugin's `fixtures/` dir, not duplicated.

## Converter

```
node skills/alteryx-to-sigma/converter/cli.mjs \
  skills/alteryx-to-sigma/fixtures/union-offramp.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID \
  --out dm.json --gaps-out gaps.json
```

Then normalize:

```
python3 corpus/lib/corpus_check.py normalize dm.json golden/data-model.json
```

## Features exercised

- Two warehouse Inputs still convert to warehouse-table elements
- Union is `dbt-offramp` (not a Sigma union/calc)
- Tool census: nothing silently dropped
- Local-only converter (`cli.mjs`)

## Known parity reference

This case is the offramp lock. Do not "fix" it by emitting a fake Sigma union.

## Expectations

```json
{
  "artifacts": [
    {"path": "../../../skills/alteryx-to-sigma/fixtures/union-offramp.yxmd", "format": "xml"},
    {"path": "checks.sh", "format": "text"}
  ],
  "goldens": {
    "data-model.json": {
      "pages": 1,
      "elements": 2,
      "columns": 4,
      "metrics": 0,
      "relationships": 0,
      "warnings": 3,
      "element_names": ["EAST_ORDERS", "WEST_ORDERS"]
    }
  }
}
```
