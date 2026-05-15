module TraceRedactor
  SENSITIVE_KEY_PATTERN = /prompt|assignment|x-api-key|api[_-]?key|apikey|aws_secret_access_key|aws_session_token|secret|password|passwd|token|authorization|credential|private[_-]?key|signing[_-]?key|session/i
  BEARER_PATTERN = /\b(Bearer)\s+["']?[^"'\s,;&]+["']?/i
  KEY_VALUE_PATTERN = /\b(x-api-key|api[_-]?key|apikey|aws_secret_access_key|aws_session_token|secret|password|passwd|token|credential|private[_-]?key|signing[_-]?key|session)\b(\s*[:=]\s*)("[^"]+"|'[^']+'|[^\s,;&]+)/i

  module_function

  def sensitive_key?(key)
    key.to_s.match?(SENSITIVE_KEY_PATTERN)
  end

  def safe_summary(value, redact_always: false)
    return value unless value.is_a?(String)
    return "[REDACTED]" if redact_always && value.present?

    redacted = value.gsub(BEARER_PATTERN, "\\1 [REDACTED]")
    redacted = redacted.gsub(KEY_VALUE_PATTERN) { "#{$1}#{$2}[REDACTED]" }
    return redacted unless redacted == value

    value.match?(SENSITIVE_KEY_PATTERN) ? "[REDACTED]" : value
  end

  def safe_metadata(value)
    case value
    when Hash
      value.each_with_object({}) do |(key, child), sanitized|
        sanitized[key] = sensitive_key?(key) ? "[REDACTED]" : safe_metadata(child)
      end
    when Array
      value.map { |child| safe_metadata(child) }
    when String
      safe_summary(value)
    else
      value
    end
  end
end
