require "rails_helper"

RSpec.describe "Web::WorkItems", type: :request do
  let!(:queue) do
    WorkQueue.create!(
      name: "Security Scan", slug: "security_scan",
      stages: %w[scan classify done]
    )
  end
  let!(:work_item) do
    WorkItem.create!(
      work_queue: queue,
      title: "Fix CVE-2024-001",
      spec_url: "https://example.com",
      stage_name: "classify"
    )
  end

  describe "GET /work_items/:id" do
    it "returns 200 and shows work item title" do
      get "/work_items/#{work_item.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fix CVE-2024-001")
    end

    it "shows the pipeline stages" do
      get "/work_items/#{work_item.id}"
      expect(response.body).to include("scan")
      expect(response.body).to include("classify")
      expect(response.body).to include("done")
    end

    it "returns 404 for unknown id" do
      get "/work_items/00000000-0000-0000-0000-000000000000"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /work_items/:id — claims" do
    let!(:claim) do
      Claim.create!(work_item: work_item, agent_type: "inline_claude",
                    status: "completed", started_at: 5.minutes.ago, completed_at: Time.current)
    end

    it "includes the adapter type in the response" do
      get "/work_items/#{work_item.id}"
      expect(response.body).to include("inline_claude")
    end
  end

  describe "GET /work_items/:id — artifacts" do
    let!(:claim) do
      Claim.create!(work_item: work_item, agent_type: "inline_claude",
                    status: "completed", started_at: Time.current)
    end
    let!(:artifact) do
      Artifact.create!(
        work_item: work_item, claim: claim,
        kind: "severity_report",
        data: { "findings" => [{ "severity" => "high" }] }
      )
    end

    it "shows artifact kind in the response" do
      get "/work_items/#{work_item.id}"
      expect(response.body).to include("severity_report")
    end
  end

  describe "GET /work_items/:id — transition log" do
    let!(:log_entry) do
      TransitionLog.create!(
        work_item: work_item,
        from_stage: "scan",
        to_stage: "classify",
        trigger: "completed"
      )
    end

    it "shows the trigger in the response" do
      get "/work_items/#{work_item.id}"
      expect(response.body).to include("completed")
    end
  end

  describe "GET /work_items/:id — children" do
    let!(:child_queue) do
      WorkQueue.create!(name: "Dev", slug: "development", stages: %w[intake done])
    end
    let!(:child) do
      WorkItem.create!(
        work_queue: child_queue,
        title: "Child task",
        spec_url: "https://example.com",
        stage_name: "intake",
        parent_id: work_item.id
      )
    end

    it "shows the child title in the response" do
      get "/work_items/#{work_item.id}"
      expect(response.body).to include("Child task")
    end
  end
end
