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

    get "/api/v1/work_items", params: { queue: queue.slug, stage: "intake" }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("work_items").map { |item| item.fetch("id") }).to include(id)
  end

  it "answers, retries, and cancels work items" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake build done])
    work_item = WorkItem.create!(work_queue: queue, title: "Blocked", spec_url: "opaque spec", stage_name: "build", status: :blocked, metadata: { "blocked_reason" => "Need token" })

    post "/api/v1/work_items/#{work_item.id}/answer", params: { answer: "Use bearer tokens" }
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_pending
    expect(work_item.metadata["human_answer"]).to eq("Use bearer tokens")
    expect(work_item.metadata).not_to have_key("blocked_reason")

    work_item.update!(status: :blocked, metadata: { "blocked_reason" => "Retry manually" })
    post "/api/v1/work_items/#{work_item.id}/retry"
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_pending
    expect(work_item.reload.transition_logs.order(:created_at).last.trigger).to eq("manual_retry")

    post "/api/v1/work_items/#{work_item.id}/cancel"
    expect(response).to have_http_status(:ok)
    expect(work_item.reload).to be_cancelled
  end

  it "reports total and per-work-item costs" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    work_item = WorkItem.create!(work_queue: queue, title: "Costly", spec_url: "opaque spec", stage_name: "intake")
    claim = Claim.create!(work_item: work_item, agent_type: "fake")
    Trace.create!(claim: claim, work_item: work_item, stage_name: "intake", agent_type: "fake", total_tokens_in: 10, total_tokens_out: 20, total_cost_cents: 7)

    get "/api/v1/costs"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("total_cost_cents")).to eq(7)

    get "/api/v1/costs/work_items/#{work_item.id}"
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("total_tokens_out")).to eq(20)
  end
end
