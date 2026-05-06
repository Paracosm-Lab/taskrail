require "json"

class RequestLoggingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status, headers, body = @app.call(env)
    duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round

    request = ActionDispatch::Request.new(env)
    payload = {
      ts: Time.now.utc.iso8601(3),
      level: "info",
      msg: "request_completed",
      service: "stupidclaw",
      logger: "request",
      request_id: request.request_id,
      method: request.request_method,
      path: request.path,
      status: status,
      duration_ms: duration_ms
    }
    Rails.logger.info(payload.to_json)

    [status, headers, body]
  end
end
