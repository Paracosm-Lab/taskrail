require "rails_helper"
require "json"
require "open3"
require "socket"
load Rails.root.join("bin/stupidclaw")

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

  def run_cli(api_url, *args, env: {})
    Open3.capture3({ "STUPIDCLAW_API_URL" => api_url }.merge(env), Rails.root.join("bin/stupidclaw").to_s, *args)
  end

  it "execs the Ink TUI when no subcommand is given" do
    api_url = "http://api.example.test"
    cli = StupidClawCli.new([], { "STUPIDCLAW_API_URL" => api_url }, StringIO.new, StringIO.new)

    expect(cli).to receive(:exec_process).with(
      "node",
      Rails.root.join("tui/dist/index.js").to_s,
      "--api", api_url
    )

    expect(cli.run).to eq(0)
  end

  it "passes TUI options through when args are given without a CLI subcommand" do
    api_url = "http://api.example.test"
    cli = StupidClawCli.new(["--queue", "ops", "--refresh", "10"], { "STUPIDCLAW_API_URL" => api_url }, StringIO.new, StringIO.new)

    expect(cli).to receive(:exec_process).with(
      "node",
      Rails.root.join("tui/dist/index.js").to_s,
      "--api", api_url,
      "--queue", "ops",
      "--refresh", "10"
    )

    expect(cli.run).to eq(0)
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

  it "submits a feature development cookbook work item" do
    with_server({ id: "SC-104" }) do |api_url, requests|
      stdout, _stderr, status = run_cli(
        api_url,
        "submit",
        "--queue", "development-codex",
        "--spec", "test/fixtures/apps/feature_development/README.md",
        "--title", "Add iCalendar VEVENT export"
      )

      expect(status).to be_success
      expect(stdout).to include("SC-104")
      request = requests.pop
      expect(request[:method]).to eq("POST")
      expect(request[:path]).to eq("/api/v1/work_items")
      expect(JSON.parse(request[:body])).to include(
        "queue" => "development-codex",
        "spec_url" => "test/fixtures/apps/feature_development/README.md",
        "title" => "Add iCalendar VEVENT export"
      )
    end
  end

  it "maps read and lifecycle commands to API endpoints" do
    with_server do |api_url, requests|
      commands = [
        [["status", "abc"], "GET", "/api/v1/work_items/abc", nil],
        [["status", "abc", "--traces"], "GET", "/api/v1/work_items/abc", "traces=true"],
        [["list", "--queue", "development", "--stage", "build"], "GET", "/api/v1/work_items", "queue=development&stage=build"],
        [["list", "--queue", "development", "--stage", "build", "--status", "blocked", "--tag", "risk=high", "--tag", "domain=rails"], "GET", "/api/v1/work_items", "queue=development&stage=build&status=blocked&tags%5Brisk%5D=high&tags%5Bdomain%5D=rails"],
        [["answer", "abc", "Use bearer tokens"], "POST", "/api/v1/work_items/abc/answer", nil],
        [["retry", "abc"], "POST", "/api/v1/work_items/abc/retry", nil],
        [["cancel", "abc"], "POST", "/api/v1/work_items/abc/cancel", nil],
        [["queues"], "GET", "/api/v1/queues", nil],
        [["stages", "development"], "GET", "/api/v1/queues/development/stages", nil],
        [["costs"], "GET", "/api/v1/costs", nil],
        [["costs", "--today"], "GET", "/api/v1/costs", "period=today"],
        [["costs", "--work-item", "abc/123"], "GET", "/api/v1/costs/work_items/abc%2F123", nil],
        [["digest"], "GET", "/api/v1/digest", "since=24h"],
        [["digest", "--since", "2h", "--json"], "GET", "/api/v1/digest", "since=2h"]
      ]

      commands.each do |args, expected_method, expected_path, expected_query|
        _stdout, _stderr, status = run_cli(api_url, *args)
        expect(status).to be_success
        request = requests.pop
        expect(request[:method]).to eq(expected_method)
        expect(request[:path]).to eq(expected_path)
        expect(request[:query]).to eq(expected_query)
      end
    end
  end

  it "renders a digest summary by default and raw JSON when requested" do
    digest = {
      since: "2026-05-05T12:00:00Z",
      generated_at: "2026-05-05T14:00:00Z",
      window: "2h",
      summary: {
        clusters_created: 3,
        runbooks_drafted: 1,
        runbooks_published: 0,
        items_completed: 7,
        items_spawned: 2,
        items_blocked: 1
      },
      costs: { cents: 47, tokens_in: 12_400, tokens_out: 8_100 },
      blocked_items: [{ id: "45", title: "rate-limit-exceeded", stage_name: "human_review", question: "Key on IP or user_id?" }],
      recent_transitions: [{ work_item_id: "42", title: "db-pool-timeout", from_stage: "ingest_signals", to_stage: "cluster_failures", trigger: "advance", at: "2026-05-05T13:58:00Z" }]
    }

    with_server(digest) do |api_url, _requests|
      stdout, _stderr, status = run_cli(api_url, "digest", "--since", "2h")

      expect(status).to be_success
      expect(stdout).to include("DIGEST (last 2h)")
      expect(stdout).to include("Clusters created:    3")
      expect(stdout).to include("#45  rate-limit-exceeded")
      expect(stdout).to include("$0.47")
      expect(stdout).to include("13:58  #42")
    end

    with_server(digest) do |api_url, _requests|
      stdout, _stderr, status = run_cli(api_url, "digest", "--since", "2h", "--json")

      expect(status).to be_success
      expect(stdout).to eq(JSON.dump(JSON.parse(JSON.dump(digest))) + "\n")
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

  it "watches dashboard output for a capped number of iterations" do
    responses = {
      "/api/v1/queues/development/stages" => { queue: { name: "Development", slug: "development" }, stages: [] },
      "/api/v1/work_items?queue=development" => { work_items: [{ id: 12, status: "pending", stage_name: "build", title: "Add calendar" }] },
      "/api/v1/costs" => {}
    }

    with_server(responses) do |api_url, requests|
      stdout, _stderr, status = run_cli(
        api_url,
        "dashboard", "--queue", "development", "--watch", "--refresh", "0",
        env: { "STUPIDCLAW_DASHBOARD_ITERATIONS" => "2" }
      )

      expect(status).to be_success
      expect(stdout.scan("StupidClaw Dashboard").size).to eq(2)
      expect(stdout).to include("\e[H\e[2J")
      expect(6.times.map { requests.pop }.count).to eq(6)
    end
  end

  it "requires a queue for dashboard" do
    with_server do |api_url, _requests|
      _stdout, stderr, status = run_cli(api_url, "dashboard")

      expect(status).not_to be_success
      expect(stderr).to include("missing queue")
    end
  end

  it "runs doctor checks against core endpoints" do
    responses = {
      "/api/v1/queues" => { queues: [{ slug: "development" }] },
      "/api/v1/costs" => { total_cost_cents: 0, total_tokens_in: 0, total_tokens_out: 0 },
      "/up" => { status: "ok" }
    }

    with_server(responses) do |api_url, requests|
      stdout, _stderr, status = run_cli(api_url, "doctor")

      expect(status).to be_success
      expect(stdout).to include("StupidClaw doctor")
      expect(stdout).to include("[OK] queues endpoint /api/v1/queues")
      expect(stdout).to include("[OK] costs endpoint /api/v1/costs")
      expect(stdout).to include("[OK] rails health endpoint /up")
      expect(stdout).to include("Doctor passed.")
      expect(3.times.map { requests.pop }.map { |request| request[:path] }).to contain_exactly(
        "/api/v1/queues",
        "/api/v1/costs",
        "/up"
      )
    end
  end
end
