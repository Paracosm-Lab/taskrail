require "json"

run lambda { |env|
  case env["PATH_INFO"]
  when "/health"
    [200, { "content-type" => "application/json" }, ['{"ok":true}']]
  when "/boom"
    path = ENV.fetch("FAKE_SENTRY_EVENTS_PATH", "/tmp/fake_sentry/events.jsonl")
    File.open(path, "a") do |file|
      file.puts({ id: Time.now.to_i.to_s, service: "chaos-api", message: "boom" }.to_json)
    end
    [500, { "content-type" => "application/json" }, ['{"error":"boom"}']]
  else
    [404, { "content-type" => "application/json" }, ['{"error":"not_found"}']]
  end
}
