require "rails_helper"

RSpec.describe "API hardening", type: :request do
  before do
    Rack::Attack.cache.store.clear
  end

  it "paginates work items with default and explicit limits" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    55.times do |index|
      WorkItem.create!(work_queue: queue, title: "Item #{index}", spec_url: "opaque spec", stage_name: "intake")
    end

    get "/api/v1/work_items", params: { queue: queue.slug }
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("data").size).to eq(50)
    expect(response.parsed_body.fetch("meta")).to include("total" => 55, "limit" => 50, "offset" => 0)

    get "/api/v1/work_items", params: { queue: queue.slug, limit: 10, offset: 20 }
    expect(response.parsed_body.fetch("data").map { |item| item.fetch("title") }).to eq((20..29).map { |index| "Item #{index}" })
    expect(response.parsed_body.fetch("meta")).to include("total" => 55, "limit" => 10, "offset" => 20)

    get "/api/v1/work_items", params: { queue: queue.slug, limit: 500, offset: 1000 }
    expect(response.parsed_body.fetch("data")).to eq([])
    expect(response.parsed_body.fetch("meta")).to include("total" => 55, "limit" => 200, "offset" => 1000)
  end

  it "paginates costs traces while preserving aggregate totals" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    work_item = WorkItem.create!(work_queue: queue, title: "Costly", spec_url: "opaque spec", stage_name: "intake")
    claim = Claim.create!(work_item: work_item, agent_type: "fake")
    3.times do |index|
      Trace.create!(claim: claim, work_item: work_item, stage_name: "intake", agent_type: "fake", total_tokens_in: index + 1, total_tokens_out: 1, total_cost_cents: 1)
    end

    get "/api/v1/costs", params: { limit: 2, offset: 1 }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.fetch("data").size).to eq(2)
    expect(response.parsed_body.fetch("meta")).to include("total" => 3, "limit" => 2, "offset" => 1)
    expect(response.parsed_body.fetch("total_tokens_in")).to eq(6)
  end

  it "rejects oversized create and answer fields" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake")

    post "/api/v1/work_items",
      params: { title: "Tagged", spec_url: "opaque spec", queue: queue.slug, tags: { env: "x" * 300 } }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to include("tag value")

    post "/api/v1/work_items",
      params: { title: "Long spec", spec_url: "x" * 2050, queue: queue.slug }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to include("spec_url")

    item = WorkItem.create!(work_queue: queue, title: "Blocked", spec_url: "opaque spec", stage_name: "intake", status: :blocked)
    post "/api/v1/work_items/#{item.id}/answer", params: { answer: "x" * (65.kilobytes) }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.parsed_body.fetch("error")).to include("answer")
  end

  it "rejects request bodies over 1 MB" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    item = WorkItem.create!(work_queue: queue, title: "Blocked", spec_url: "opaque spec", stage_name: "intake", status: :blocked)

    post "/api/v1/work_items/#{item.id}/answer",
      params: { answer: "ok" },
      headers: { "CONTENT_LENGTH" => (2.megabytes).to_s }

    expect(response).to have_http_status(:payload_too_large)
  end

  it "rate limits API requests by bearer token" do
    WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake done])
    headers = { "Authorization" => "Bearer service-token" }

    300.times do
      get "/api/v1/queues", headers: headers
      expect(response).to have_http_status(:ok)
    end

    get "/api/v1/queues", headers: headers
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
  end

  it "rate limits admin requests by bearer token" do
    original = ENV["TASKRAIL_ADMIN_TOKEN"]
    ENV["TASKRAIL_ADMIN_TOKEN"] = "admin-token"
    headers = { "Authorization" => "Bearer admin-token" }

    30.times do
      put "/admin/log-level", params: { level: "info" }, headers: headers
      expect(response).to have_http_status(:ok)
    end

    put "/admin/log-level", params: { level: "info" }, headers: headers
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
  ensure
    ENV["TASKRAIL_ADMIN_TOKEN"] = original
  end
end
