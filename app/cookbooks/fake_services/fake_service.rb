# frozen_string_literal: true

require "json"
require "stringio"

module Cookbooks
  class FakeService
    JSON_HEADERS = { "content-type" => "application/json" }.freeze

    def initialize(service_name)
      @service_name = service_name
      @events = []
      @logs = []
      @alerts = []
      @requests = 0
      @state = "ok"
    end

    def call(env)
      @requests += 1

      method = env.fetch("REQUEST_METHOD")
      path = env.fetch("PATH_INFO", "/")

      case [method, path]
      in ["GET", "/health"]
        status = @state == "down" ? 503 : 200
        json(status, service: @service_name, status: @state)
      in ["GET", "/metrics"]
        json(200, service: @service_name, requests: @requests, events: @events.size, logs: @logs.size, alerts: @alerts.size)
      in ["GET", "/events"]
        json(200, service: @service_name, events: @events)
      in ["POST", "/events"]
        item = append_payload(@events, env)
        json(202, accepted: true, id: item.fetch("id"), service: @service_name)
      in ["GET", "/logs"]
        json(200, service: @service_name, logs: @logs)
      in ["POST", "/logs"]
        item = append_payload(@logs, env)
        json(202, accepted: true, id: item.fetch("id"), service: @service_name)
      in ["POST", "/reset"]
        @events.clear
        @logs.clear
        @alerts.clear
        @state = "ok"
        json(200, accepted: true, service: @service_name)
      else
        handle_dynamic_route(method, path)
      end
    rescue JSON::ParserError => e
      json(400, service: @service_name, error: "invalid_json", message: e.message)
    end

    private

    def handle_dynamic_route(method, path)
      if method == "POST" && path.start_with?("/chaos/")
        return json(404, service: @service_name, error: "chaos_not_supported") unless @service_name == "fake-staging-app"

        mode = path.delete_prefix("/chaos/")
        return json(422, service: @service_name, error: "unsupported_chaos_mode", mode: mode) unless %w[degraded down ok].include?(mode)

        @state = mode
        @alerts << { "id" => next_id(@alerts), "mode" => mode }
        return json(200, service: @service_name, mode: mode, status: @state)
      end

      json(404, service: @service_name, error: "not_found")
    end

    def append_payload(collection, env)
      payload = parse_payload(env)
      item = payload.merge("id" => payload.fetch("id", next_id(collection)))
      collection << item
      item
    end

    def parse_payload(env)
      input = env["rack.input"]
      raw = input&.read.to_s
      raw = "{}" if raw.empty?
      JSON.parse(raw)
    end

    def next_id(collection)
      "#{@service_name}-#{collection.size + 1}"
    end

    def json(status, payload)
      [status, JSON_HEADERS, [JSON.generate(payload)]]
    end
  end
end

if $PROGRAM_NAME == __FILE__
  require "webrick"

  service_name = ENV.fetch("FAKE_SERVICE_NAME", "fake-service")
  port = Integer(ENV.fetch("FAKE_SERVICE_PORT", "4010"))
  app = Cookbooks::FakeService.new(service_name)

  server = WEBrick::HTTPServer.new(Port: port, BindAddress: "0.0.0.0")
  trap("INT") { server.shutdown }
  trap("TERM") { server.shutdown }

  server.mount_proc("/") do |request, response|
    status, headers, body = app.call(
      "REQUEST_METHOD" => request.request_method,
      "PATH_INFO" => request.path,
      "rack.input" => StringIO.new(request.body.to_s)
    )

    response.status = status
    headers.each { |key, value| response[key] = value }
    response.body = body.join
  end

  server.start
end
