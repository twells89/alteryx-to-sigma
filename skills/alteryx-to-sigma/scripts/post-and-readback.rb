#!/usr/bin/env ruby
# frozen_string_literal: true
#
# POST a Sigma data-model spec (from converter/cli.mjs), read it back, and
# fail on columns that compiled to type "error". Alteryx is data-model only —
# there is no workbook branch.
#
#   eval "$(scripts/get-token.sh)"
#   ruby scripts/post-and-readback.rb --spec dm.json --out dm-map.json
#
require 'json'
require 'optparse'
require 'fileutils'

opts = {}
OptionParser.new do |p|
  p.on('--spec P') { |v| opts[:spec] = v }
  p.on('--out P')  { |v| opts[:out]  = v }
  p.on('--type T', 'Ignored; this skill only posts data models.') { |v| opts[:type] = v }
  p.on('--workdir P') { |v| opts[:workdir] = v }
  p.on('--update-id ID', 'PUT this existing data model instead of POSTing new.') { |v| opts[:update_id] = v }
  p.on('--folder ID', 'Writable folder/workspace UUID (else SIGMA_FOLDER_ID, else auto-pick).') { |v| opts[:folder] = v }
  p.on('--skip-layout-lint', 'No-op (no workbook / no layout).') { |_| }
end.parse!
%i[spec out].each { |k| abort("missing --#{k}") unless opts[k] }
if opts[:type] && opts[:type] != 'datamodel'
  abort('alteryx-to-sigma is data-model only — --type workbook is not supported')
end
opts[:workdir] ||= File.dirname(File.expand_path(opts[:spec]))
FileUtils.mkdir_p(opts[:workdir])

$LOAD_PATH.unshift File.expand_path('lib', __dir__)
require 'sigma_rest'

raw = JSON.parse(File.read(opts[:spec]))
spec = raw['dataModel'] || raw['model'] || raw

POST_PATH = '/v2/dataModels/spec'
GET_PATH  = '/v2/dataModels/%s/spec'

# POST /v2/dataModels/spec requires a UUID folderId (live-probed 2026-08-27:
# omitting it 400s with "Expecting UUID at 0.folderId"). PUT updates do not.
def resolve_folder_id(explicit)
  return explicit unless explicit.to_s.strip.empty?
  env = ENV['SIGMA_FOLDER_ID'].to_s.strip
  return env unless env.empty?
  files = Sigma.request(:get, '/v2/files?typeFilters=folder&limit=200') rescue {}
  entries = files['entries'] || files['data'] || []
  pref = entries.find { |f| (f['name'] || '').upcase =~ /ALTERYX|MIGRATION|TEST/ }
  hit = pref || entries.first
  hit && hit['id']
end

if opts[:update_id]
  warn "UPDATE mode: PUT datamodel #{opts[:update_id]}"
  resp = Sigma.request(:put, format(GET_PATH, opts[:update_id]), body: spec.to_json)
  oid = resp['dataModelId'] || opts[:update_id]
  warn "PUT ok: dataModelId=#{oid}"
else
  spec['folderId'] ||= resolve_folder_id(opts[:folder])
  abort('POST needs a folderId — pass --folder or set SIGMA_FOLDER_ID') if spec['folderId'].to_s.empty?
  warn "folderId: #{spec['folderId']}"
  resp = Sigma.request(:post, POST_PATH, body: spec.to_json)
  oid = resp['dataModelId'] or abort("POST failed: #{resp.inspect}")
  warn "POST ok: dataModelId=#{oid}"
end

readback = Sigma.request(:get, format(GET_PATH, oid))
pages = (readback['pages'] || []).map do |page|
  {
    'id' => page['id'], 'name' => page['name'],
    'elements' => (page['elements'] || []).map do |element|
      { 'id' => element['id'], 'kind' => element['kind'], 'name' => element['name'] }
    end
  }
end
out = { 'dataModelId' => oid, 'pages' => pages }
File.write(opts[:out], JSON.pretty_generate(out))
puts JSON.pretty_generate(out)

cols = Sigma.request(:get, "/v2/dataModels/#{oid}/columns") rescue nil
if cols
  error_columns = (cols['entries'] || []).select { |c| c.dig('type', 'type') == 'error' }
  File.write(File.join(opts[:workdir], 'dm-columns.json'), JSON.pretty_generate(cols))
  if error_columns.any?
    warn "\nFAIL — #{error_columns.size} column(s) compiled to type \"error\":"
    error_columns.each { |c| warn "  [element=#{c['elementId']}] #{c['label']} (#{c['columnId']}): #{c['formula']}" }
    exit 2
  end
  warn "column-type guard: #{(cols['entries'] || []).size} columns clean (no `error` types)"
else
  warn 'WARN: could not fetch /columns for the type guard — skipping'
end
