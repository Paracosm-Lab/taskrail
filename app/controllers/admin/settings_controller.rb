module Admin
  class SettingsController < ApplicationController
    before_action :require_admin_auth!

    def log_level
      level = params.require(:level).to_s.downcase
      unless %w[debug info warn error fatal unknown].include?(level)
        return render json: { error: "invalid_log_level", detail: "level must be one of debug/info/warn/error/fatal/unknown" }, status: :bad_request
      end

      RuntimeSettings.set_log_level!(level)
      render json: { level: RuntimeSettings.log_level }
    end

    def trace_sample_rate
      value = Float(params.require(:rate))
      if value.negative? || value > 1.0
        return render json: { error: "invalid_trace_sample_rate", detail: "rate must be between 0.0 and 1.0" }, status: :bad_request
      end

      RuntimeSettings.set_trace_sample_rate!(value)
      render json: { rate: RuntimeSettings.trace_sample_rate }
    rescue ArgumentError
      render json: { error: "invalid_trace_sample_rate", detail: "rate must be numeric" }, status: :bad_request
    end

    def circuit_breaker
      render json: { breakers: RuntimeSettings.circuit_breakers }
    end

    def update_circuit_breaker
      name = params.require(:name).to_s
      open = ActiveModel::Type::Boolean.new.cast(params.require(:open))
      breakers = RuntimeSettings.set_circuit_breaker!(name: name, open: open)
      render json: { breakers: breakers }
    end

    def maintenance
      enabled = ActiveModel::Type::Boolean.new.cast(params.require(:enabled))
      RuntimeSettings.set_maintenance!(enabled)
      render json: { maintenance: RuntimeSettings.maintenance? }
    end
  end
end
