module Adapters
  class ResponseParser
    STRUCTURED_KEYS = %w[
      artifacts
      blocked_question
      children
      classify
      feedback
      spawn_work_items
      status
      tags
      verdict
    ].freeze

    def self.extract_structured_fields(response)
      return {} if response.blank?

      fields = {}
      json_objects(response).each do |parsed|
        parsed.each do |key, value|
          fields[key] = value if STRUCTURED_KEYS.include?(key)
        end
      end

      fields
    end

    def self.json_objects(response)
      candidates = json_fence_blocks(response)
      candidates << response

      candidates.each_with_object([]) do |candidate, objects|
        parsed = JSON.parse(candidate)

        if parsed.is_a?(Hash)
          objects << parsed
          nested_result = parsed["result"]
          objects.concat(json_objects(nested_result)) if nested_result.is_a?(String)
        end
      rescue JSON::ParserError
        next
      end
    end

    def self.json_fence_blocks(response)
      blocks = []
      current = nil
      capture = false

      response.each_line do |line|
        if current
          if line.match?(/\A```\s*\z/)
            blocks << current.join if capture
            current = nil
            capture = false
          else
            current << line if capture
          end
          next
        end

        fence = line.match(/\A```(?<language>[A-Za-z0-9_-]+)?\s*\z/)
        next unless fence

        language = fence[:language]
        capture = language.blank? || language == "json"
        current = []
      end

      blocks
    end
    private_class_method :json_objects
    private_class_method :json_fence_blocks
  end
end
