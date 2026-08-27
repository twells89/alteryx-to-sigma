#!/usr/bin/env ruby
# frozen_string_literal: true
#
# Build the find-or-pick-dm.rb signature from a converted Alteryx data-model JSON.
#
#   ruby scripts/emit-signature.rb --spec dm.json --out signature.json
#
require 'json'
require 'optparse'

opts = {}
OptionParser.new do |p|
  p.on('--spec P') { |v| opts[:spec] = v }
  p.on('--out P')  { |v| opts[:out]  = v }
end.parse!
%i[spec out].each { |k| abort("missing --#{k}") unless opts[k] }

raw = JSON.parse(File.read(opts[:spec]))
model = raw['dataModel'] || raw['model'] || raw
elements = (model.dig('pages') || []).flat_map { |p| p['elements'] || [] }

tables = []
columns = []
measures = []
elements.each do |el|
  path = el.dig('source', 'path')
  tables << path.join('.') if path.is_a?(Array) && !path.empty?
  (el['columns'] || []).each do |c|
    name = c['name']
    next unless name
    columns << name
  end
  (el['metrics'] || []).each do |m|
    measures << { 'col' => m['name'], 'derivation' => m['formula'] }
  end
end

sig = {
  'alteryx_workflow' => model['name'] || 'Alteryx Workflow',
  'warehouse_tables' => tables.uniq,
  'referenced_columns' => columns.uniq,
  'measures' => measures
}
File.write(opts[:out], JSON.pretty_generate(sig) + "\n")
warn "signature: #{tables.uniq.size} table(s), #{columns.uniq.size} column name(s)"
