# Alteryx → Sigma — Quickstart

Data-model only. Local converter. No MCP — the `.yxmd` never leaves the box.

## Convert (offline — no Sigma tenant, no token, no npm install)

```bash
cd skills/alteryx-to-sigma

node converter/cli.mjs fixtures/orders-join.yxmd \
  --connection PLACEHOLDER-CONNECTION-ID \
  --out /tmp/alteryx-dm.json --gaps-out /tmp/alteryx-gaps.json
```

If `stats.dbtOfframps > 0`, read `/tmp/alteryx-gaps.json` and
`refs/dbt-offramp.md` **before** posting. That ETL belongs in dbt; Sigma
reads the materialized table.

## Auth (once)

```bash
ruby scripts/setup.rb            # prompts, or pass --client-id/--client-secret
```

Writes `SIGMA_BASE_URL` / `SIGMA_CLIENT_ID` / `SIGMA_CLIENT_SECRET` to
`~/.claude/settings.json` and `~/.sigma-migration/env`. Every script here
auto-sources the neutral file, so usually there is nothing else to do. To
mint a token by hand:

```bash
eval "$(scripts/get-token.sh)"                  # bash/zsh
python3 scripts/get_token.py --workdir /tmp/alteryx-run   # any shell (PowerShell/cmd)
```

## End to end (convert + reuse-check + POST + column-type gate)

```bash
ruby scripts/migrate-alteryx.rb \
  --yxmd fixtures/orders-join.yxmd \
  --connection-id "$SIGMA_CONNECTION_ID" \
  [--database DEMO_DB --schema DEMO] \
  [--folder "$SIGMA_FOLDER_ID"] \
  --workdir /tmp/alteryx-run
```

`--database` / `--schema` override the catalog path parsed from the ODBC
`File` string, for when the `.yxmd` was built against a different
environment. The run is a PASS only when the posted model has **zero
`type=error` columns** — that is what `parity-final.json` records.

## Rebuild the converter after a `.ts` edit

`converter/cli.mjs` is generated, and production runs the bundle:

```bash
( cd converter && npm ci && npm run bundle )
ruby ../../tools/check-alteryx-bundle.rb --write
```
