require "digest"

Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new

Rack::Attack.throttled_responder = lambda do |request|
  match_data = request.env["rack.attack.match_data"] || {}
  retry_after = match_data[:period].to_i

  [
    429,
    { "Content-Type" => "application/json", "Retry-After" => retry_after.to_s },
    [{ error: "too_many_requests", detail: "rate limit exceeded" }.to_json]
  ]
end

api_limit = ENV.fetch("TASKRAIL_API_RATE_LIMIT", 300).to_i
admin_limit = ENV.fetch("TASKRAIL_ADMIN_RATE_LIMIT", 30).to_i
unauthenticated_limit = ENV.fetch("TASKRAIL_UNAUTHENTICATED_RATE_LIMIT", 60).to_i
webhook_limit = ENV.fetch("TASKRAIL_WEBHOOK_RATE_LIMIT", 60).to_i
sign_in_limit = ENV.fetch("TASKRAIL_SIGN_IN_RATE_LIMIT", 10).to_i

Rack::Attack.throttle("api/bearer", limit: api_limit, period: 60.seconds) do |request|
  bearer_digest(request) if request.path.start_with?("/api/") && bearer_digest(request)
end

Rack::Attack.throttle("api/unauthenticated-ip", limit: unauthenticated_limit, period: 60.seconds) do |request|
  request.ip if request.path.start_with?("/api/") && bearer_digest(request).blank?
end

Rack::Attack.throttle("admin/bearer", limit: admin_limit, period: 60.seconds) do |request|
  bearer_digest(request) if request.path.start_with?("/admin/") && bearer_digest(request)
end

Rack::Attack.throttle("admin/unauthenticated-ip", limit: unauthenticated_limit, period: 60.seconds) do |request|
  request.ip if request.path.start_with?("/admin/") && bearer_digest(request).blank?
end

Rack::Attack.throttle("webhook/ip", limit: webhook_limit, period: 60.seconds) do |request|
  request.ip if request.path.include?("/webhooks/")
end

Rack::Attack.throttle("devise/sign-in-ip", limit: sign_in_limit, period: 60.seconds) do |request|
  request.ip if request.post? && request.path == "/users/sign_in"
end

def bearer_digest(request)
  raw_token = request.env["HTTP_AUTHORIZATION"].to_s[/\ABearer (.+)\z/, 1]
  Digest::SHA256.hexdigest(raw_token) if raw_token.present?
end
