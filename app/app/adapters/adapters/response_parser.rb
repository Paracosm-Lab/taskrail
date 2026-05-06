module Adapters
  class ResponseParser
    STRUCTURED_KEYS = %w[spawn_work_items tags].freeze

    def self.extract_structured_fields(response)
      return {} if response.blank?

      fields = {}
      json_blocks = response.scan(/```(?:json)?\s*\n(.*?)\n```/m).flatten

      json_blocks.each do |block|
        parsed = JSON.parse(block)
        next unless parsed.is_a?(Hash)

        parsed.each do |key, value|
          fields[key] = value if STRUCTURED_KEYS.include?(key)
        end
      rescue JSON::ParserError
        next
      end

      fields
    end
  end
end
