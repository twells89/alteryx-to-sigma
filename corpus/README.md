# Regression corpus

Synthetic Alteryx `.yxmd` fixtures + golden converter outputs + a runner, so a
converter change can be smoke-tested **with no Sigma tenant, no credentials,
and no network**. Everything here is synthetic demo data (`DEMO_DB.DEMO` retail
star) — no tokens, no customer names.

```
corpus/
  run-corpus.sh           # the runner
  lib/corpus_check.py     # normalize / summarize / check / diff helper
  alteryx/<case-name>/
    MANIFEST.md           # what it is, features exercised, converter call,
                          # and a ```json expectations block
    checks.sh             # executable expectations (runs the in-skill bundle)
    golden/*.json         # converter output, id-NORMALIZED (see below)
```

The `.yxmd` inputs are **not duplicated** here — each MANIFEST references the
skill's own `skills/alteryx-to-sigma/fixtures/*.yxmd` by relative path, so the
fixture the corpus pins is exactly the fixture the skill ships.

## Cases

| Case | What it pins |
|---|---|
| `alteryx/orders-join` | Input + Join + Formula + Select. Cross-element formula refs qualified onto a derived view; composite join keys; relationship on the fact side. `dbtOfframps == 0`. |
| `alteryx/retail-star` | Multi-table star, `IIF` mapping, and a Filter tool surfaced as an RLS-candidate warning (never silently applied). |
| `alteryx/union-offramp` | A Union canvas. Asserts `stats.dbtOfframps > 0` and that **no fake union** is emitted — the tool is censused as a dbt offramp instead. |

## Running

```bash
./corpus/run-corpus.sh --check            # all cases
./corpus/run-corpus.sh --check alteryx    # one tool's cases
```

Each case is two independent gates: `corpus_check.py check` validates the
MANIFEST's `expectations` block against the golden, and `checks.sh` re-runs the
in-skill converter bundle and byte-compares the normalized output to the
golden.

## Goldens are id-normalized

Converter output contains generated element/column ids that are stable per run
but meaningless across runs. `lib/corpus_check.py normalize` rewrites them to
deterministic placeholders before the byte compare, so a golden diff means a
*behavior* change, not an id shuffle.

## Updating a golden

Only when you intended the behavior change:

```bash
node skills/alteryx-to-sigma/converter/cli.mjs \
  skills/alteryx-to-sigma/fixtures/orders-join.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID --out /tmp/fresh.json
python3 corpus/lib/corpus_check.py normalize /tmp/fresh.json \
  corpus/alteryx/orders-join/golden/data-model.json
```

Review the diff before committing — a golden churn with no explanation in the
PR body is a red flag, not a rebase artifact.
