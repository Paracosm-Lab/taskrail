require "rails_helper"

RSpec.describe "Workflow API", type: :request do
  it "lists queues and stages" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake build done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake")

    get "/api/v1/queues"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("queues").map { |item| item.fetch("slug") }).to include(queue.slug)

    get "/api/v1/queues/#{queue.slug}/stages"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("stages").map { |item| item.fetch("name") }).to eq(%w[intake build done])
  end

  it "creates, shows, and lists work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake build done])

    post "/api/v1/work_items", params: { title: "Add calendar", spec_url: "opaque spec", queue: queue.slug, tags: { complexity: "small" } }
    expect(response).to have_http_status(:created)
    id = response.parsed_body.fetch("id")
    work_item = WorkItem.find(id)
    expect(work_item.stage_name).to eq("intake")
    expect(work_item).to be_pending

    get "/api/v1/work_items/#{id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("title")).to eq("Add calendar")
    expect(response.parsed_body.fetch("active_claim")).to be_nil

    get "/api/v1/work_items", params: { queue: queue.slug, stage: "intake" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("work_items").map { |item| item.fetch("id") }).to include(id)
  end

  it "includes a safe active claim summary for work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build done])
    work_item = WorkItem.create!(work_queue: queue, title: "Codex smoke", spec_url: "opaque spec", stage_name: "build")
    claim = Claim.create!(
      work_item: work_item,
      agent_type: "codex",
      status: :active,
      async_execution: true,
      assignment: { "async" => { "external_id" => "run-123", "prompt" => "do not expose" } }
    )

    get "/api/v1/work_items", params: { queue: queue.slug }
    expect(response).to have_http_status(:ok)
    listed_item = response.parsed_body.fetch("work_items").find { |item| item.fetch("id") == work_item.id }
    expect(listed_item.fetch("active_claim")).to eq(
      "id" => claim.id,
      "agent_type" => "codex",
      "status" => "active",
      "async_execution" => true,
      "external_id" => "run-123"
    )
    expect(listed_item.to_json).not_to include("do not expose")

    get "/api/v1/work_items/#{work_item.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("active_claim").fetch("external_id")).to eq("run-123")
  end

  it "includes a safe escalation summary for blocked work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build done])
    plain_item = WorkItem.create!(work_queue: queue, title: "Plain", spec_url: "opaque spec", stage_name: "build")
    blocked_item = WorkItem.create!(
      work_queue: queue,
      title: "Blocked",
      spec_url: "opaque spec",
      stage_name: "build",
      status: :blocked,
      metadata: {
        "blocked_reason" => "tests_passed missing",
        "escalation" => {
          "target" => "human",
          "question" => "Please advise",
          "human_action_required" => true,
          "prompt" => "do not expose"
        }
      }
    )

    get "/api/v1/work_items", params: { queue: queue.slug }
    expect(response).to have_http_status(:ok)
    listed_blocked = response.parsed_body.fetch("work_items").find { |item| item.fetch("id") == blocked_item.id }
    listed_plain = response.parsed_body.fetch("work_items").find { |item| item.fetch("id") == plain_item.id }
    expect(listed_blocked.fetch("escalation")).to eq(
      "target" => "human",
      "reason" => "tests_passed missing",
      "question" => "Please advise",
      "human_action_required" => true
    )
    expect(listed_plain.fetch("escalation")).to be_nil
    expect(listed_blocked.to_json).not_to include("do not expose")

    get "/api/v1/work_items/#{blocked_item.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("escalation").fetch("target")).to eq("human")
  end

  it "includes trace summaries when requested" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build done])
    work_item = WorkItem.create!(work_queue: queue, title: "Traceable", spec_url: "opaque spec", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "codex", assignment: { "prompt" => "do not expose" })
    trace = Trace.create!(
      claim: claim,
      work_item: work_item,
      stage_name: "build",
      agent_type: "codex",
      model: "codex-mini",
      total_tokens_in: 10,
      total_tokens_out: 20,
      total_cost_cents: 7,
      total_duration_ms: 123
    )
    trace.trace_events.create!(
      sequence: 1,
      event_type: "tool_use",
      tokens_in: 3,
      tokens_out: 4,
      cost_cents: 5,
      duration_ms: 6,
      input_summary: "Prompt says do not expose",
      output_summary: "Authorization Bearer do not expose",
      metadata: {
        "tool" => "git",
        "prompt" => "do not expose",
        "access_token" => "do not expose",
        "nested" => { "client_secret" => "do not expose", "safe" => "kept", "command_output" => "api_key do not expose" },
        "events" => [{ "bearer_token" => "do not expose", "name" => "tool-call" }]
      }
    )

    get "/api/v1/work_items/#{work_item.id}", params: { traces: true }
    expect(response).to have_http_status(:ok)
    traces = response.parsed_body.fetch("traces")
    expect(traces.first).to include(
      "id" => trace.id,
      "stage_name" => "build",
      "agent_type" => "codex",
      "model" => "codex-mini",
      "total_tokens_in" => 10,
      "total_tokens_out" => 20,
      "total_cost_cents" => 7,
      "total_duration_ms" => 123
    )
    expect(traces.first.fetch("events").first).to include(
      "sequence" => 1,
      "event_type" => "tool_use",
      "input_summary" => "[REDACTED]",
      "output_summary" => "[REDACTED]",
      "tokens_in" => 3,
      "tokens_out" => 4,
      "cost_cents" => 5,
      "duration_ms" => 6,
      "metadata" => {
        "tool" => "git",
        "prompt" => "[REDACTED]",
        "access_token" => "[REDACTED]",
        "nested" => { "client_secret" => "[REDACTED]", "safe" => "kept", "command_output" => "[REDACTED]" },
        "events" => [{ "bearer_token" => "[REDACTED]", "name" => "tool-call" }]
      }
    )
    expect(response.body).not_to include("do not expose")

    get "/api/v1/work_items/#{work_item.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).not_to have_key("traces")
  end

  it "answers, retries, and cancels work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake build done])
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Blocked",
      spec_url: "opaque spec",
      stage_name: "build",
      status: :blocked,
      metadata: {
        "blocked_reason" => "Need token",
        "escalation" => {
          "target" => "human",
          "reason" => "Need token",
          "question" => "Which token?",
          "human_action_required" => true
        }
      }
    )

    post "/api/v1/work_items/#{work_item.id}/answer", params: { answer: "Use bearer tokens" }
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_pending
    expect(work_item.metadata["human_answer"]).to eq("Use bearer tokens")
    expect(work_item.metadata).not_to have_key("blocked_reason")
    expect(work_item.metadata).not_to have_key("escalation")
    expect(response.parsed_body.fetch("escalation")).to be_nil

    work_item.update!(status: :blocked, metadata: { "blocked_reason" => "Retry manually" })
    post "/api/v1/work_items/#{work_item.id}/retry"
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_pending
    expect(work_item.reload.transition_logs.order(:created_at).last.trigger).to eq("manual_retry")

    post "/api/v1/work_items/#{work_item.id}/cancel"
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_cancelled
  end

  it "reports total, today, and per-work-item costs" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    work_item = WorkItem.create!(work_queue: queue, title: "Costly", spec_url: "opaque spec", stage_name: "intake")
    claim = Claim.create!(work_item: work_item, agent_type: "fake")
    today_trace = Trace.create!(claim: claim, work_item: work_item, stage_name: "intake", agent_type: "fake", total_tokens_in: 10, total_tokens_out: 20, total_cost_cents: 7)
    old_trace = Trace.create!(claim: claim, work_item: work_item, stage_name: "intake", agent_type: "fake", total_tokens_in: 100, total_tokens_out: 200, total_cost_cents: 70)
    old_trace.update_column(:created_at, 2.days.ago)

    get "/api/v1/costs"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("total_cost_cents")).to eq(77)

    get "/api/v1/costs", params: { period: "today" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to include(
      "total_tokens_in" => today_trace.total_tokens_in,
      "total_tokens_out" => today_trace.total_tokens_out,
      "total_cost_cents" => today_trace.total_cost_cents
    )

    get "/api/v1/costs/work_items/#{work_item.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("total_tokens_out")).to eq(220)
  end
end
