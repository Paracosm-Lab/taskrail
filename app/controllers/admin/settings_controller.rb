module Admin
  class SettingsController < ActionController::Base
    include Devise::Controllers::Helpers

    skip_forgery_protection
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

    private

    def require_admin_auth!
      return if current_user&.admin?
      return if valid_personal_access_token?
      return if legacy_admin_token_valid?

      if ENV["TASKRAIL_ADMIN_TOKEN"].blank? && !Rails.env.production?
        render json: { error: "admin_not_configured" }, status: :service_unavailable
      else
        render json: { error: "forbidden", detail: "admin token required" }, status: :forbidden
      end
    end

    def valid_personal_access_token?
      token = PersonalAccessToken.authenticate(bearer_token)
      return false unless token&.includes_scope?("admin")
      return false unless token.user.admin?

      token.mark_used!
      true
    end

    def legacy_admin_token_valid?
      admin_token = ENV["TASKRAIL_ADMIN_TOKEN"].to_s
      admin_token.present? && ActiveSupport::SecurityUtils.secure_compare(bearer_token, admin_token)
    rescue ArgumentError
      false
    end

    def bearer_token
      @bearer_token ||= request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
    end
  end
end
