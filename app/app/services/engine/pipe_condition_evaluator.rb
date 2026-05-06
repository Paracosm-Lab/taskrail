module Engine
  class PipeConditionEvaluator
    def initialize(artifact_data:, conditions:)
      @data = artifact_data
      @conditions = conditions
    end

    def passes?
      @conditions.all? { |condition| evaluate(condition) }
    end

    private

    def evaluate(condition)
      field = condition.fetch("field")
      operator = condition.fetch("operator")
      value = condition["value"]

      resolved = resolve_field(@data, field)

      case operator
      when "includes"
        resolved.any? { |v| Array(value).include?(v) }
      when "equals"
        resolved.first == value
      when "exists"
        resolved.any? { |v| !v.nil? }
      else
        false
      end
    end

    # Returns an array of resolved values.
    # For "findings[].severity" — iterates the findings array and collects severity values.
    # For "grade" — returns [data["grade"]].
    def resolve_field(data, field)
      if field.include?("[].")
        array_key, rest = field.split("[].", 2)
        array = dig_path(data, array_key)
        return [] unless array.is_a?(Array)

        array.map { |item| dig_path(item, rest) }
      else
        [dig_path(data, field)]
      end
    end

    def dig_path(obj, key_path)
      key_path.split(".").reduce(obj) do |current, key|
        current.is_a?(Hash) ? current[key] : nil
      end
    end
  end
end
