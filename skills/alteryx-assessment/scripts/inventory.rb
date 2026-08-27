#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Read-only inventory of a folder of Alteryx .yxmd files. Uses the local
# alteryx-to-sigma converter bundle (no MCP).
#
#   ruby scripts/inventory.rb --dir <folder> --out readout.json
#
require 'json'
require 'optparse'
require 'open3'
require 'fileutils'

opts = {}
OptionParser.new do |p|
  p.on('--dir P') { |v| opts[:dir] = v }
  p.on('--out P') { |v| opts[:out] = v }
end.parse!
abort 'missing --dir' if opts[:dir].to_s.empty?
abort 'missing --out' if opts[:out].to_s.empty?

dir = File.expand_path(opts[:dir])
abort "not a directory: #{dir}" unless File.directory?(dir)

cli = File.expand_path('../../alteryx-to-sigma/converter/cli.mjs', __dir__)
abort "converter bundle missing: #{cli} — cd ../alteryx-to-sigma/converter && npm install && npm run bundle" unless File.exist?(cli)

# Case-fold the MATCH rather than brace-listing both cases: on a
# case-insensitive filesystem (macOS APFS/HFS+) a `{yxmd,YXMD}` brace glob
# matches every file TWICE, which silently doubles the estate count and the
# converter subprocess work. `.uniq` is belt-and-braces for symlinked dirs.
files = Dir.glob(File.join(dir, '*.{yxmd,yxmc}'), File::FNM_CASEFOLD).uniq.sort
abort "no .yxmd/.yxmc files in #{dir}" if files.empty?

workflows = files.map do |path|
  out, err, status = Open3.capture3('node', cli, path, '--connection', 'PLACEHOLDER')
  parsed = JSON.parse(out) rescue {}
  stats = parsed['stats'] || {}
  gaps = parsed['gaps'] || []
  dbt = gaps.select { |g| g['kind'] == 'dbt-offramp' }
  lane = if (stats['dbtOfframps'] || 0).to_i.positive? || (stats['gaps'] || 0).to_i.positive?
           'dbt-first'
         else
           'sigma-dm'
         end
  {
    'file' => File.basename(path),
    'ok' => status.success?,
    'lane' => lane,
    'stats' => stats,
    'dbt_families' => dbt.map { |g| g['family'] }.uniq,
    'stderr' => err.to_s.split("\n").first(8),
  }
end

sigma, dbt_first = workflows.partition { |w| w['lane'] == 'sigma-dm' }
readout = {
  'folder' => dir,
  'count' => workflows.size,
  'sigma_dm_shortlist' => sigma.map { |w| w['file'] },
  'dbt_first' => dbt_first.map { |w| { 'file' => w['file'], 'families' => w['dbt_families'] } },
  'workflows' => workflows,
}
File.write(opts[:out], JSON.pretty_generate(readout) + "\n")
warn "assessed #{workflows.size} workflow(s): #{sigma.size} sigma-dm, #{dbt_first.size} dbt-first → #{opts[:out]}"
