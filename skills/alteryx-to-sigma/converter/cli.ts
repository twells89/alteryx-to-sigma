#!/usr/bin/env node
/**
 * Alteryx .yxmd → Sigma data-model converter CLI. LOCAL ONLY.
 *
 *   node converter/cli.mjs <workflow.yxmd> \
 *     [--connection <id>] [--database DB] [--schema S] [--name NAME] \
 *     [--out PATH] [--gaps-out PATH]
 *
 * Prints `{ dataModel, warnings, stats, gaps }` JSON to stdout (or --out).
 * There is no hosted-converter fallback and no network at convert time.
 * After editing converter/*.ts, rebuild with `npm install && npm run
 * bundle` in this directory, then refresh the freshness hash with
 * `ruby tools/check-alteryx-bundle.rb --write` from the repo root.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import { convertAlteryxToSigma } from './alteryx.js';

const args = process.argv.slice(2);
const file = args.find((a) => !a.startsWith('--'));
const opt = (k: string, d = '') => {
  const i = args.indexOf('--' + k);
  return i >= 0 ? (args[i + 1] ?? d) : d;
};
if (!file) {
  process.stderr.write(
    'usage: cli.mjs <workflow.yxmd> [--connection ID --database DB --schema S --name NAME --out PATH --gaps-out PATH]\n',
  );
  process.exit(1);
}

const xml = readFileSync(file, 'utf8');
const res = convertAlteryxToSigma(xml, {
  connectionId: opt('connection', '<CONNECTION_ID>'),
  database: opt('database'),
  schema: opt('schema'),
  modelName: opt('name') || undefined,
});

const payload = { dataModel: res.model, warnings: res.warnings, stats: res.stats, gaps: res.gaps || [] };
const text = JSON.stringify(payload, null, 2) + '\n';
const out = opt('out');
if (out) writeFileSync(out, text);
else process.stdout.write(text);

const dbt = (res.gaps || []).filter((g) => g.kind === 'dbt-offramp');
const gapsOut = opt('gaps-out');
if (gapsOut) writeFileSync(gapsOut, JSON.stringify({ dbtOfframps: dbt, gaps: res.gaps || [] }, null, 2) + '\n');

process.stderr.write(`[alteryx→data-model] stats: ${JSON.stringify(res.stats)}\n`);
if (dbt.length) {
  process.stderr.write(
    `\nDBT OFFRAMP — ${dbt.length} tool(s) are ETL Sigma should not fake.\n` +
    `Port them to dbt (or equivalent warehouse SQL) and point Sigma at the\n` +
    `materialized table. See refs/dbt-offramp.md.\n`,
  );
  for (const g of dbt) {
    process.stderr.write(`  → Tool ${g.toolId} [${g.family}] ${g.reason}\n`);
    if (g.dbtHint) process.stderr.write(`      dbt: ${g.dbtHint}\n`);
  }
}
if (res.warnings.length) {
  process.stderr.write(`warnings (${res.warnings.length}):\n`);
  for (const w of res.warnings) process.stderr.write('  ! ' + w + '\n');
}
