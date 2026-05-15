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

Rack::Attack.throttle("api/token", limit: 300, period: 60.seconds) do |request|
  request.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if request.path.start_with?("/api/")
end

Rack::Attack.throttle("admin/token", limit: 30, period: 60.seconds) do |request|
  request.env["HTTP_AUTHORIZATION"]&.split(" ")&.last if request.path.start_with?("/admin/")
end

Rack::Attack.throttle("webhook/ip", limit: 60, period: 60.seconds) do |request|
  request.ip if request.path.include?("/webhooks/")
end
