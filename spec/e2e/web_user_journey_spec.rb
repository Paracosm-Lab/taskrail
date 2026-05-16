require "rails_helper"

RSpec.describe "web user journey", type: :request do
  it "logs in, creates a PAT, creates work through the API, runs the engine, and verifies the web UI" do
    user = create(:user, password: "correct-password", password_confirmation: "correct-password")
    queue = WorkQueue.create!(
      name: "E2E Web Journey",
      slug: "e2e_web_journey",
      stages: %w[intake done]
    )
    queue.stage_configs.create!(
      stage_name: "intake",
      adapter_type: "fake",
      completion_criteria: ["report_present"]
    )

    post user_session_path, params: {
      user: {
        email: user.email,
        password: "correct-password"
      }
    }
    expect(response).to redirect_to(root_path)

    post personal_access_tokens_path, params: {
      personal_access_token: {
        name: "E2E automation",
        scopes: %w[read write]
      }
    }
    expect(response).to redirect_to(personal_access_tokens_path)

    follow_redirect!
    raw_token = response.body[/trpat_[A-Za-z0-9_-]+/]
    expect(raw_token).to be_present

    post "/api/v1/work_items",
      params: {
        queue: queue.slug,
        title: "Exercise full web and API journey",
        spec_url: "opaque://web-user-journey",
        tags: { "source" => "e2e" }
      },
      headers: { "Authorization" => "Bearer #{raw_token}" }

    expect(response).to have_http_status(:created)
    work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
    expect(work_item).to be_pending
    expect(work_item.stage_name).to eq("intake")

    5.times do
      Engine::Runner.new.call
      break if work_item.reload.completed?
    end

    expect(work_item).to be_completed
    expect(work_item.stage_name).to eq("done")
    expect(work_item.claims.completed.count).to eq(1)
    expect(work_item.reports.success.count).to eq(1)
    expect(work_item.transition_logs.pluck(:trigger)).to include("rule_satisfied")

    get queue_path(queue.slug)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exercise full web and API journey")
    expect(response.body).to include("done")

    get work_item_path(work_item)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Exercise full web and API journey")
    expect(response.body).to include("completed")
    expect(response.body).to include("rule_satisfied")
  end
end
