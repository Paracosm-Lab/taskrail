require "rails_helper"

RSpec.describe "GitHub PR webhooks", type: :request do
  it "creates a PR review work item for opened pull requests" do
    load Rails.root.join("db/seeds.rb")

    payload = {
      "action" => "opened",
      "repository" => { "full_name" => "acme/store", "html_url" => "https://github.example/acme/store" },
      "pull_request" => {
        "number" => 42,
        "html_url" => "https://github.example/acme/store/pull/42",
        "head" => { "ref" => "feature/search", "sha" => "abc123" },
        "base" => { "ref" => "main" },
        "title" => "Add order search"
      }
    }

    expect do
      post "/api/v1/webhooks/github/pull_request", params: payload, as: :json
    end.to change(WorkItem, :count).by(1)

    expect(response).to have_http_status(:created)
    item = WorkItem.order(:created_at).last
    expect(item.work_queue.slug).to eq("pr_review")
    expect(item.title).to eq("PR #42: Add order search")
    expect(item.spec_url).to eq("https://github.example/acme/store/pull/42")
    expect(item.stage_name).to eq("run_checks")
    expect(item.tags).to include(
      "repository" => "acme/store",
      "pull_request_number" => "42",
      "branch" => "feature/search",
      "base_branch" => "main",
      "head_sha" => "abc123"
    )
  end

  it "creates a PR review work item for synchronize pull requests" do
    load Rails.root.join("db/seeds.rb")

    payload = {
      "action" => "synchronize",
      "repository" => { "full_name" => "acme/store" },
      "pull_request" => {
        "number" => 43,
        "html_url" => "https://github.example/acme/store/pull/43",
        "head" => { "ref" => "feature/payments", "sha" => "def456" },
        "base" => { "ref" => "main" },
        "title" => "Add payments"
      }
    }

    expect do
      post "/api/v1/webhooks/github/pull_request", params: payload, as: :json
    end.to change(WorkItem, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(WorkItem.order(:created_at).last.tags).to include("pull_request_number" => "43", "head_sha" => "def456")
  end

  it "ignores unsupported pull request actions" do
    load Rails.root.join("db/seeds.rb")

    expect do
      post "/api/v1/webhooks/github/pull_request", params: { action: "closed", pull_request: { number: 1 } }, as: :json
    end.not_to change(WorkItem, :count)

    expect(response).to have_http_status(:accepted)
  end
end
