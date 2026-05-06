require "rails_helper"
require "stringio"
require Rails.root.join("cookbooks/fake_services/fake_service")

RSpec.describe Cookbooks::FakeService do
  subject(:service) { described_class.new("fake-sentry") }

  it "reports healthy status" do
    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/health")

    expect(status).to eq(200)
    expect(JSON.parse(body.join)).to include("service" => "fake-sentry", "status" => "ok")
  end

  it "stores and resets events deterministically" do
    event_body = StringIO.new({ message: "boom" }.to_json)
    post_env = { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/events", "rack.input" => event_body }
    service.call(post_env)

    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/events")
    expect(status).to eq(200)
    expect(JSON.parse(body.join).fetch("events")).to include(hash_including("message" => "boom"))

    service.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/reset", "rack.input" => StringIO.new("{}"))
    _status, _headers, reset_body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/events")
    expect(JSON.parse(reset_body.join).fetch("events")).to eq([])
  end

  it "stores and resets logs deterministically" do
    log_body = StringIO.new({ level: "warn", message: "slow query" }.to_json)
    service.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/logs", "rack.input" => log_body)

    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/logs")
    expect(status).to eq(200)
    expect(JSON.parse(body.join).fetch("logs")).to include(hash_including("level" => "warn", "message" => "slow query"))

    service.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/reset", "rack.input" => StringIO.new("{}"))
    _status, _headers, reset_body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/logs")
    expect(JSON.parse(reset_body.join).fetch("logs")).to eq([])
  end

  it "reports request counters and collected item counts as metrics" do
    service.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/events", "rack.input" => StringIO.new({ id: "event-1" }.to_json))

    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/metrics")

    expect(status).to eq(200)
    expect(JSON.parse(body.join)).to include("service" => "fake-sentry", "events" => 1, "logs" => 0)
    expect(JSON.parse(body.join).fetch("requests")).to be >= 2
  end

  it "can toggle chaos state for the fake staging app" do
    staging = described_class.new("fake-staging-app")
    staging.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/chaos/down", "rack.input" => StringIO.new("{}"))

    status, _headers, body = staging.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/health")
    expect(status).to eq(503)
    expect(JSON.parse(body.join)).to include("service" => "fake-staging-app", "status" => "down")
  end
end
