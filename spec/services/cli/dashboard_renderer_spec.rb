require "rails_helper"

RSpec.describe Cli::DashboardRenderer do
  it "renders stages, work items, and costs as stable terminal text" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: { "name" => "Development", "slug" => "development" },
      stages: [
        { "name" => "build", "adapter_type" => "codex", "completion_criteria" => %w[branch_created report_present] },
        { "name" => "test", "adapter_type" => "shell_script", "completion_criteria" => %w[tests_passed] }
      ],
      work_items: [
        { "id" => 12, "status" => "pending", "stage_name" => "build", "title" => "Add calendar" },
        { "id" => 13, "status" => "blocked", "stage_name" => "review", "title" => "Review auth changes" }
      ],
      costs: { "total_cost_cents" => 7, "total_tokens_in" => 10, "total_tokens_out" => 20 }
    )

    output = described_class.new(data: data).render

    expect(output).to include("TaskRail Dashboard")
    expect(output).to include("API: http://localhost:3000")
    expect(output).to include("Queue: Development (development)")
    expect(output).to include("Stages")
    expect(output).to include("build")
    expect(output).to include("codex")
    expect(output).to include("branch_created, report_present")
    expect(output).to include("Work Items")
    expect(output).to include("12")
    expect(output).to include("pending")
    expect(output).to include("Add calendar")
    expect(output).to include("Costs")
    expect(output).to include("Total cost: 7 cents")
    expect(output).to include("Tokens in/out: 10 / 20")
  end

  it "renders active async claim summaries on work item rows" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: {},
      stages: [],
      work_items: [{
        "id" => 12,
        "status" => "pending",
        "stage_name" => "build",
        "title" => "Codex smoke",
        "active_claim" => {
          "agent_type" => "codex",
          "status" => "active",
          "async_execution" => true,
          "external_id" => "run-123"
        }
      }],
      costs: {}
    )

    output = described_class.new(data: data).render

    expect(output).to include("codex:active async run-123")
  end

  it "renders human escalation summaries on work item rows" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: {},
      stages: [],
      work_items: [{
        "id" => 12,
        "status" => "blocked",
        "stage_name" => "build",
        "title" => "Fix flaky tests",
        "escalation" => {
          "target" => "human",
          "human_action_required" => true,
          "question" => "Tests failed.\nProvide guidance.\e[31m"
        }
      }],
      costs: {}
    )

    output = described_class.new(data: data).render

    expect(output).to include("HUMAN: Tests failed. Provide guidance.")
    expect(output).to include("Actions")
    expect(output).to include("1 blocked item needs a human answer.")
    expect(output).to include("Run: bin/taskrail answer WORK_ITEM_ID \"your guidance\"")
    expect(output).not_to include("\e")
    expect(output).not_to include("Tests failed.\nProvide guidance")
  end

  it "renders an empty work item state" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: {},
      stages: [],
      work_items: [],
      costs: {}
    )

    output = described_class.new(data: data).render

    expect(output).to include("No work items.")
    expect(output).to include("Total cost: 0 cents")
    expect(output).to include("Tokens in/out: 0 / 0")
  end

  it "sanitizes terminal control characters before rendering" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: { "name" => "Dev\e[31m\nInjected" },
      stages: [{ "name" => "build\nBAD", "adapter_type" => "codex\e[2J", "completion_criteria" => ["branch\tcreated"] }],
      work_items: [{ "id" => 1, "status" => "pending\nBAD", "stage_name" => "build", "title" => "Safe\nFake Section\e[31m" }],
      costs: { "total_cost_cents" => nil, "total_tokens_in" => nil, "total_tokens_out" => nil }
    )

    output = described_class.new(data: data).render

    expect(output).not_to include("\e")
    expect(output).not_to include("pending\nBAD")
    expect(output).not_to include("build\nBAD")
    expect(output).to include("pending BAD")
    expect(output).to include("build BAD")
    expect(output).to include("Safe Fake Section")
    expect(output).to include("Total cost: 0 cents")
    expect(output).to include("Tokens in/out: 0 / 0")
  end

  it "truncates long titles after sanitization" do
    data = Cli::DashboardDataLoader::DashboardData.new(
      api_url: "http://localhost:3000",
      queue_slug: "development",
      queue: {},
      stages: [],
      work_items: [{ "id" => 1, "status" => "pending", "stage_name" => "build", "title" => "A" * 80 }],
      costs: {}
    )

    output = described_class.new(data: data).render

    expect(output).to include("#{"A" * 47}…")
    expect(output).not_to include("A" * 80)
  end
end
