#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Alteryx → Sigma data-model orchestrator (C2–C8). Data-model only — Alteryx
# Designer workflows have no dashboard surface, so this never builds a workbook.
#
#   ruby scripts/migrate-alteryx.rb --yxmd <workflow.yxmd> \
#     --connection-id <id> [--name NAME] [--workdir DIR] [--force-new]
#
#   ruby scripts/migrate-alteryx.rb --print-converter   # path of bundled CLI
#
# Sequences: convert → signature → reuse-check → POST+readback. Stops at the
# first hard-gate failure.
require 'optparse'
require 'json'
require 'fileutils'
require 'open3'

class MigrationFailed < StandardError; end

CONV_DIR = File.expand_path('../converter', __dir__)
CLI = File.join(CONV_DIR, 'cli.mjs')

def fail_phase!(phase, msg)
  raise MigrationFailed, "#{phase}: #{msg}"
end

def run!(*cmd, env: {})
  out, err, status = Open3.capture3(env, *cmd)
  warn out unless out.empty?
  warn err unless err.empty?
  [status.success?, status.exitstatus]
end

if ARGV.include?('--print-converter')
  puts CLI
  exit 0
end

opts = {}
OptionParser.new do |o|
  o.on('--yxmd PATH')          { |v| opts[:yxmd] = v }
  o.on('--connection-id ID')   { |v| opts[:connection_id] = v }
  o.on('--database NAME')      { |v| opts[:database] = v }
  o.on('--schema NAME')        { |v| opts[:schema] = v }
  o.on('--name NAME')          { |v| opts[:name] = v }
  o.on('--workdir DIR')        { |v| opts[:workdir] = v }
  o.on('--force-new')          { opts[:force_new] = true }
  o.on('--update-id ID')       { |v| opts[:update_id] = v }
  o.on('--folder ID')          { |v| opts[:folder] = v }
end.parse!(ARGV)

abort 'missing --yxmd' if opts[:yxmd].to_s.empty?
abort 'missing --connection-id' if opts[:connection_id].to_s.empty?
abort "converter bundle missing: #{CLI} — cd converter && npm install && npm run bundle" unless File.exist?(CLI)

workdir = File.expand_path(opts[:workdir] || Dir.pwd)
FileUtils.mkdir_p(workdir)
yxmd = File.expand_path(opts[:yxmd])
abort "yxmd not found: #{yxmd}" unless File.file?(yxmd)

begin
  dm_json = File.join(workdir, 'dm.json')
  gaps_json = File.join(workdir, 'dbt-offramp.json')
  conv = ['node', CLI, yxmd, '--connection', opts[:connection_id], '--out', dm_json, '--gaps-out', gaps_json]
  conv += ['--database', opts[:database]] if opts[:database]
  conv += ['--schema', opts[:schema]] if opts[:schema]
  conv += ['--name', opts[:name]] if opts[:name]
  ok, code = run!(*conv)
  fail_phase!('convert', "cli.mjs exited #{code}") unless ok

  if File.exist?(gaps_json)
    payload = JSON.parse(File.read(gaps_json)) rescue {}
    dbt = payload['dbtOfframps'] || []
    if dbt.any?
      warn "\nDBT OFFRAMP — #{dbt.size} Alteryx tool(s) are ETL Sigma should not fake."
      warn 'Recommend a dbt (or warehouse SQL) model for each, then point Sigma at'
      warn "the materialized table. See refs/dbt-offramp.md and #{gaps_json}"
      dbt.each do |g|
        warn "  → Tool #{g['toolId']} [#{g['family']}] #{g['reason']}"
      end
    end
  end

  sig = File.join(workdir, 'signature.json')
  ok, code = run!('ruby', File.expand_path('emit-signature.rb', __dir__),
                  '--spec', dm_json, '--out', sig)
  fail_phase!('signature', "emit-signature.rb exited #{code}") unless ok

  match = File.join(workdir, 'dm-match.json')
  pick = ['ruby', File.expand_path('find-or-pick-dm.rb', __dir__),
          '--workbook-signature', sig, '--out', match, '--auto-pick']
  pick << '--force-new' if opts[:force_new]
  # Reuse-check is advisory: a "no match" exit still writes dm-match.json.
  run!(*pick)

  update_id = opts[:update_id]
  if !update_id && File.exist?(match)
    rec = JSON.parse(File.read(match)) rescue {}
    update_id = rec['dataModelId'] || rec.dig('recommendation', 'dataModelId') if rec['auto_picked']
  end

  map = File.join(workdir, 'dm-map.json')
  post = ['ruby', File.expand_path('post-and-readback.rb', __dir__),
          '--spec', dm_json, '--out', map, '--workdir', workdir]
  post += ['--update-id', update_id] if update_id
  post += ['--folder', opts[:folder]] if opts[:folder]
  ok, code = run!(*post)
  fail_phase!('post-dm', "post-and-readback.rb exited #{code}") unless ok

  # C8: the column-type guard inside post-and-readback is the hard parity
  # gate for this DM-only skill (no workbook / no visual PNG). Record it.
  parity = {
    'status' => 'PASS',
    'kind' => 'data-model',
    'gate' => 'column-type',
    'notes' => 'Alteryx is data-model only. Numeric warehouse-vs-Sigma metric ' \
               'parity is a follow-up when the same warehouse is reachable; ' \
               'the posted DM has zero type=error columns.'
  }
  File.write(File.join(workdir, 'parity-final.json'), JSON.pretty_generate(parity) + "\n")
  warn 'parity-final.json: PASS (column-type guard)'
rescue MigrationFailed => e
  warn "STOP: #{e.message}"
  exit 1
end
