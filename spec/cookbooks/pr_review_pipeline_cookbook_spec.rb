require "rails_helper"

RSpec.describe "PR review pipeline cookbook fixture" do
  let(:fixture_root) { Rails.root.join("cookbooks/fixtures/apps/pr_review_app") }

  it "provides a docker-friendly fixture app with security, coverage, and architecture examples" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("app/controllers/orders_controller.rb")).to exist
    expect(fixture_root.join("app/services/order_search.rb")).to exist
    expect(fixture_root.join("spec/requests/orders_spec.rb")).to exist

    readme = fixture_root.join("README.md").read
    expect(readme).to include("PR Review Pipeline")
    expect(readme).to include("SQL injection fixture")
    expect(readme).to include("missing authorization fixture")

    search_service = fixture_root.join("app/services/order_search.rb").read
    expect(search_service).to include("unsafe_search")
    expect(search_service).to include("safe_search")

    serialized = Dir[fixture_root.join("**", "*")].select { |path| File.file?(path) }.map { |path| File.read(path) }.join("\n")
    expect(serialized).not_to include(Rails.root.to_s)
    expect(serialized).not_to include("/Users/")
  end

  it "documents security scan spawn payloads for blocking systemic findings" do
    load Rails.root.join("db/seeds.rb")

    pr_queue = WorkQueue.find_by!(slug: "pr_review")
    security = pr_queue.stage_configs.find_by!(stage_name: "security_scan")

    expect(security.agent_prompt).to include("blocking_count")
    expect(security.agent_prompt).to include("spawn_work_items")
    expect(security.agent_prompt).to include("error_handling_audit")
    expect(security.agent_prompt).to include("development")
    expect(security.adapter_config.fetch("spawn_target_queues")).to contain_exactly("error_handling_audit", "development")
  end
end
