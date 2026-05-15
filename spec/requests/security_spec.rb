require "rails_helper"

RSpec.describe "security scenarios", type: :request do
  around do |example|
    original_service = ENV["TASKRAIL_SERVICE_TOKEN"]
    original_admin = ENV["TASKRAIL_ADMIN_TOKEN"]
    ENV["TASKRAIL_SERVICE_TOKEN"] = "service-token"
    ENV["TASKRAIL_ADMIN_TOKEN"] = "admin-token"
    example.run
  ensure
    ENV["TASKRAIL_SERVICE_TOKEN"] = original_service
    ENV["TASKRAIL_ADMIN_TOKEN"] = original_admin
  end

  it "rejects missing, malformed, wrong, and empty API bearer tokens" do
    get "/api/v1/work_items"
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/work_items", headers: { "Authorization" => "NotBearer service-token" }
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/work_items", headers: { "Authorization" => "Bearer wrong" }
    expect(response).to have_http_status(:unauthorized)

    get "/api/v1/work_items", headers: { "Authorization" => "Bearer " }
    expect(response).to have_http_status(:unauthorized)
  end

  it "keeps service and admin tokens separate" do
    get "/api/v1/work_items", headers: { "Authorization" => "Bearer admin-token" }
    expect(response).to have_http_status(:unauthorized)

    put "/admin/log-level", params: { level: "info" }, headers: { "Authorization" => "Bearer service-token" }
    expect(response).to have_http_status(:forbidden)
  end

  it "handles SQL injection-looking query params safely" do
    queue = WorkQueue.create!(name: "Development", slug: "development-sec-#{SecureRandom.hex(4)}", stages: %w[intake done])
    WorkItem.create!(work_queue: queue, title: "Safe", spec_url: "opaque", stage_name: "intake")

    expect do
      get "/api/v1/work_items",
        params: { stage: "'; DROP TABLE work_items;--" },
        headers: { "Authorization" => "Bearer service-token" }
    end.not_to change(WorkItem, :count)
    expect(response).to have_http_status(:ok)
  end

  it "rejects oversized request bodies" do
    post "/api/v1/work_items",
      params: { title: "Huge", spec_url: "opaque", queue: "missing" },
      headers: { "Authorization" => "Bearer service-token", "CONTENT_LENGTH" => (2.megabytes).to_s }

    expect(response).to have_http_status(:payload_too_large)
  end

  it "rejects invalid JSON bodies" do
    post "/api/v1/work_items",
      params: "{",
      headers: { "Authorization" => "Bearer service-token", "CONTENT_TYPE" => "application/json" }

    expect(response).to have_http_status(:bad_request)
  end
end
