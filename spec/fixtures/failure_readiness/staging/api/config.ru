require "json"

run lambda { |env|
  case env["PATH_INFO"]
  when "/health"
    [200, { "content-type" => "application/json" }, [JSON.generate(ok: true, service: "failure-api")]]
  when "/sessions"
    [200, { "content-type" => "application/json" }, [JSON.generate(ok: true, action: "session-created")]]
  else
    [404, { "content-type" => "application/json" }, [JSON.generate(error: "not_found")]]
  end
}
