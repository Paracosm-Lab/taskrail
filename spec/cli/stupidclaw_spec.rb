require "rails_helper"
require "json"
require "open3"
require "socket"

RSpec.describe "bin/stupidclaw" do
  def with_server(response_body = { ok: true })
    requests = Queue.new
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    thread = Thread.new do
      loop do
        socket = server.accept
        request_line = socket.gets&.strip
        headers = {}
        while (line = socket.gets)&.strip != ""
          key, value = line.split(":", 2)
          headers[key.downcase] = value.strip if key && value
        end
        body = socket.read(headers.fetch("content-length", "0").to_i)
        method, full_path, = request_line.split(" ")
        path, query_string = full_path.split("?", 2)
        requests << { method: method, path: path, query: query_string, body: body }
        response_payload = response_for(response_body, full_path)
        response = JSON.dump(response_payload)
        socket.write "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: #{response.bytesize}\r\nConnection: close\r\n\r\n#{response}"
        socket.close
      rescue IOError
        break
      end
    end

    yield "http://127.0.0.1:#{port}", requests
  ensure
    server&.close
    thread&.kill
    thread&.join
  end

  def response_for(response_body, full_path)
    return response_body unless response_body.key?(full_path)

    response_body.fetch(full_path)
  end

  def run_cli(api_url, *args)
    Open3.capture3({ "STUPIDCLAW_API_URL" => api_url }, Rails.root.join("bin/stupidclaw").to_s, *args)
  end

  it "submits a work item" do
    with_server({ id: "123" }) do |api_url, requests|
      _stdout, _stderr, status = run_cli(api_url, "submit", "--queue", "development", "--spec", "./spec.md", "--title", "Add calendar")

      expect(status).to be_success
      request = requests.pop
      expect(request[:method]).to eq("POST")
      expect(request[:path]).to eq("/api/v1/work_items")
      expect(JSON.parse(request[:body])).to include("queue" => "development", "spec_url" => "./spec.md", "title" => "Add calendar")
    end
  end

  it "maps read and lifecycle commands to API endpoints" do
    with_server do |api_url, requests|
      commands = [
        [["status", "abc"], "GET", "/api/v1/work_items/abc"],
        [["list", "--queue", "development", "--stage", "build"], "GET", "/api/v1/work_items"],
        [["answer", "abc", "Use bearer tokens"], "POST", "/api/v1/work_items/abc/answer"],
        [["retry", "abc"], "POST", "/api/v1/work_items/abc/retry"],
        [["cancel", "abc"], "POST", "/api/v1/work_items/abc/cancel"],
        [["queues"], "GET", "/api/v1/queues"],
        [["stages", "development"], "GET", "/api/v1/queues/development/stages"]
      ]

      commands.each do |args, expected_method, expected_path|
        _stdout, _stderr, status = run_cli(api_url, *args)
        expect(status).to be_success
        request = requests.pop
        expect(request[:method]).to eq(expected_method)
        expect(request[:path]).to eq(expected_path)
      end
    end
  end

  it "renders a one-shot dashboard" do
    responses = {
      "/api/v1/queues/development/stages" => {
        queue: { name: "Development", slug: "development" },
        stages: [{ name: "build", adapter_type: "codex", completion_criteria: ["branch_created"] }]
      },
      "/api/v1/work_items?queue=development" => {
        work_items: [{ id: 12, status: "pending", stage_name: "build", title: "Add calendar" }]
      },
      "/api/v1/costs" => { total_cost_cents: 7, total_tokens_in: 10, total_tokens_out: 20 }
    }

    with_server(responses) do |api_url, requests|
      stdout, _stderr, status = run_cli(api_url, "dashboard", "--queue", "development")

      expect(status).to be_success
      expect(stdout).to include("StupidClaw Dashboard")
      expect(stdout).to include("development")
      expect(stdout).to include("Add calendar")
      expect(3.times.map { requests.pop }.map { |request| [request[:method], request[:path], request[:query]] }).to contain_exactly(
        ["GET", "/api/v1/queues/development/stages", nil],
        ["GET", "/api/v1/work_items", "queue=development"],
        ["GET", "/api/v1/costs", nil]
      )
    end
  end

  it "renders dashboard filters" do
    responses = {
      "/api/v1/queues/development/stages" => { queue: { name: "Development", slug: "development" }, stages: [] },
      "/api/v1/work_items?queue=development" => {
        work_items: [
          { id: 12, status: "pending", stage_name: "build", title: "Add calendar" },
          { id: 13, status: "blocked", stage_name: "review", title: "Review auth changes" }
        ]
      },
      "/api/v1/costs" => {}
    }

    with_server(responses) do |api_url, _requests|
      stdout, _stderr, status = run_cli(api_url, "dashboard", "--queue", "development", "--status", "blocked", "--limit", "1")

      expect(status).to be_success
      expect(stdout).to include("Review auth changes")
      expect(stdout).not_to include("Add calendar")
    end
  end

  it "requires a queue for dashboard" do
    with_server do |api_url, _requests|
      _stdout, stderr, status = run_cli(api_url, "dashboard")

      expect(status).not_to be_success
      expect(stderr).to include("missing queue")
    end
  end
end
