# spec/jobs/linear_poll_job_spec.rb
require "rails_helper"

RSpec.describe LinearPollJob, type: :job do
  let!(:queue) do
    q = WorkQueue.create!(
      name: "Postrunner Fix",
      slug: "postrunner-fix",
      stages: %w[fix open_pr await_ci review merge]
    )
    StageConfig.create!(work_queue: q, stage_name: "fix", adapter_type: "fake", completion_criteria: ["report_present"])
    q
  end

  before do
    allow(ENV).to receive(:fetch).with("LINEAR_API_KEY", "").and_return("test-key")
  end

  it "creates work items for new postrunner issues" do
    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      {
        "id" => "linear-uuid-1", "identifier" => "ENG-173",
        "title" => "[shellcheck] SC2086 in bin/deploy.sh",
        "description" => "## Finding\n...",
        "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "crm-service" }] }
      }
    ])

    expect { described_class.perform_now }.to change(WorkItem, :count).by(1)

    item = WorkItem.last
    expect(item.title).to eq("[shellcheck] SC2086 in bin/deploy.sh")
    expect(item.tags["linear_issue_id"]).to eq("linear-uuid-1")
    expect(item.tags["repository"]).to eq("MyScribbl/crm-service")
    expect(item.spec_url).to include("ENG-173")
  end

  it "skips issues that already have work items" do
    WorkItem.create!(
      work_queue: queue,
      title: "existing",
      spec_url: "https://linear.app/myscribbl/issue/ENG-173",
      stage_name: "fix",
      status: :pending,
      tags: { "linear_issue_id" => "linear-uuid-1" }
    )

    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      { "id" => "linear-uuid-1", "identifier" => "ENG-173", "title" => "test",
        "description" => "d", "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "crm-service" }] } }
    ])

    expect { described_class.perform_now }.not_to change(WorkItem, :count)
  end

  it "skips voice-agent-service because postrunner does not target retired services" do
    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      {
        "id" => "linear-uuid-3", "identifier" => "ENG-175",
        "title" => "[bandit] B601 in voice_agent/handler.py",
        "description" => "## Finding\n...",
        "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "voice-agent-service" }] }
      }
    ])

    expect { described_class.perform_now }.not_to change(WorkItem, :count)
  end

  it "skips issues with postrunner-ignore label" do
    client = instance_double(LinearClient)
    allow(LinearClient).to receive(:new).and_return(client)
    allow(client).to receive(:postrunner_issues).and_return([
      { "id" => "linear-uuid-2", "identifier" => "ENG-174", "title" => "test",
        "description" => "d", "labels" => { "nodes" => [{ "name" => "postrunner" }, { "name" => "postrunner-ignore" }, { "name" => "crm-service" }] } }
    ])

    expect { described_class.perform_now }.not_to change(WorkItem, :count)
  end
end
