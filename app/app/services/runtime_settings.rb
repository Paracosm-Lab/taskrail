class RuntimeSettings
  CIRCUIT_BREAKERS_KEY = "runtime:circuit_breakers".freeze
  LOG_LEVEL_KEY = "runtime:log_level".freeze
  MAINTENANCE_KEY = "runtime:maintenance".freeze
  TRACE_SAMPLE_RATE_KEY = "runtime:trace_sample_rate".freeze

  class << self
    def log_level
      Rails.cache.fetch(LOG_LEVEL_KEY, expires_in: 24.hours) { ENV.fetch("LOG_LEVEL", "info") }
    end

    def set_log_level!(value)
      Rails.cache.write(LOG_LEVEL_KEY, value, expires_in: 24.hours)
      Rails.logger.level = Logger.const_get(value.upcase)
    end

    def trace_sample_rate
      Rails.cache.fetch(TRACE_SAMPLE_RATE_KEY, expires_in: 24.hours) { 0.0 }
    end

    def set_trace_sample_rate!(value)
      Rails.cache.write(TRACE_SAMPLE_RATE_KEY, value, expires_in: 24.hours)
    end

    def circuit_breakers
      Rails.cache.fetch(CIRCUIT_BREAKERS_KEY, expires_in: 24.hours) { {} }
    end

    def set_circuit_breaker!(name:, open:)
      updated = circuit_breakers.merge(name => { "open" => !!open, "updated_at" => Time.current.iso8601 })
      Rails.cache.write(CIRCUIT_BREAKERS_KEY, updated, expires_in: 24.hours)
      updated
    end

    def maintenance?
      Rails.cache.fetch(MAINTENANCE_KEY, expires_in: 24.hours) { false }
    end

    def set_maintenance!(value)
      Rails.cache.write(MAINTENANCE_KEY, !!value, expires_in: 24.hours)
    end
  end
end
