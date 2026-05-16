class ApplicationController < ActionController::API
  include Devise::Controllers::Helpers

  rescue_from ActionDispatch::Http::Parameters::ParseError, with: :bad_request

  before_action :enforce_maintenance_mode!
  before_action :enforce_body_size_limit!
  before_action :require_api_auth!

  private

  DEFAULT_LIMIT = 50
  MAX_LIMIT = 200
  MAX_BODY_BYTES = 1.megabyte

  def enforce_body_size_limit!
    return if request.content_length.to_i <= MAX_BODY_BYTES

    render json: { error: "Request body too large (max 1 MB)" }, status: :payload_too_large
  end

  def bad_request(error)
    render json: { error: "bad_request", detail: error.message }, status: :bad_request
  end

  def pagination
    limit = params[:limit].to_i
    limit = DEFAULT_LIMIT if limit <= 0
    limit = [limit, MAX_LIMIT].min

    offset = params[:offset].to_i
    offset = 0 if offset.negative?

    { limit: limit, offset: offset }
  end

  def paginate(scope)
    page = pagination
    total = scope.count
    records = scope.limit(page.fetch(:limit)).offset(page.fetch(:offset))

    [records, { total: total, limit: page.fetch(:limit), offset: page.fetch(:offset) }]
  end

  def require_api_auth!
    return if public_endpoint?
    return if admin_endpoint?
    return if valid_personal_access_token?(required_scope: api_scope)
    return if valid_service_token?
    return unless auth_enforced?

    render json: { error: "unauthorized", detail: "missing or invalid bearer token" }, status: :unauthorized
  end

  def require_admin_auth!
    return if authenticated_user&.admin?
    return if valid_personal_access_token?(required_scope: "admin", require_admin_user: true)

    admin_token = ENV["TASKRAIL_ADMIN_TOKEN"].to_s
    return render(json: { error: "admin_not_configured" }, status: :service_unavailable) if admin_token.empty? && !auth_enforced?

    return if bearer_token == admin_token

    render json: { error: "forbidden", detail: "admin token required" }, status: :forbidden
  end

  def authenticated_user
    current_user || request.env["warden"]&.user(:user)
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

  def valid_personal_access_token?(required_scope:, require_admin_user: false)
    token = PersonalAccessToken.authenticate(bearer_token)
    return false unless token&.includes_scope?(required_scope)
    return false if require_admin_user && !token.user.admin?

    token.mark_used!
    @current_personal_access_token = token
    @current_api_user = token.user
    true
  end

  def auth_enforced?
    Rails.env.production? || ENV["TASKRAIL_SERVICE_TOKEN"].present? || PersonalAccessToken.exists?
  end

  def api_scope
    request.get? || request.head? ? "read" : "write"
  end

  def public_endpoint?
    request.path == "/up" || request.path == "/health" || request.path == "/api/v1/webhooks/github/pull_request"
  end

  def admin_endpoint?
    request.path.start_with?("/admin/")
  end
end
