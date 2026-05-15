#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "yaml"

errors = []
raw = ENV.fetch("DRAFT_DOCS_JSON", "{}")
parsed = JSON.parse(raw)
draft_docs = if parsed["draft_docs"].is_a?(Hash)
               parsed["draft_docs"]
             elsif parsed["artifact_kind"] == "draft_docs" && parsed["artifact"].is_a?(Hash)
               parsed["artifact"]
             else
               {}
             end

Array(draft_docs["files"]).each do |file|
  next unless file["path"].to_s.match?(/openapi|swagger/)
  next unless file["content"]

  begin
    YAML.safe_load(file["content"], permitted_classes: [Date, Time], aliases: true)
  rescue Psych::Exception => e
    errors << "#{file["path"]}: #{e.message}"
  end
end

puts JSON.generate("validation_results" => { "valid" => errors.empty?, "errors" => errors })
