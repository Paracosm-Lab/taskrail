class ApplicationController < ActionController::API
  before_action :enforce_maintenance_mode!
  before_action :require_api_auth!

  private

  def require_api_auth!
    return if public_endpoint?
    return if admin_endpoint?
    return unless auth_enforced?
    return if valid_service_token?

    render json: { error: "unauthorized", detail: "missing or invalid bearer token" }, status: :unauthorized
  end

  def require_admin_auth!
    admin_token = ENV["TASKRAIL_ADMIN_TOKEN"].to_s
    return render(json: { error: "admin_not_configured" }, status: :service_unavailable) if admin_token.empty?

    return if bearer_token == admin_token

    render json: { error: "forbidden", detail: "admin token required" }, status: :forbidden
  end

  def enforce_maintenance_mode!
    return unless RuntimeSettings.maintenance?
    return if public_endpoint? || admin_endpoint?

    render json: { error: "service_unavailable", detail: "maintenance mode enabled" }, status: :service_unavailable
  end

  def bearer_token
    @bearer_token ||= request.authorization.to_s[/\ABearer (.+)\z/, 1].to_s
  end

  def valid_service_token?
    token = ENV["TASKRAIL_SERVICE_TOKEN"].to_s
    return false if token.empty?

    ActiveSupport::SecurityUtils.secure_compare(bearer_token, token)
  rescue ArgumentError
    false
  end

  def auth_enforced?
    ENV["TASKRAIL_SERVICE_TOKEN"].present?
  end

  def public_endpoint?
    request.path == "/up" || request.path == "/health" || request.path == "/api/v1/webhooks/github/pull_request"
  end

  def admin_endpoint?
    request.path.start_with?("/admin/")
  end
end
