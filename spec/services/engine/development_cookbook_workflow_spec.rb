require "rails_helper"

RSpec.describe "feature development cookbook workflow", type: :model do
  it "creates child build items from a successful decompose report" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "development-codex")
    work_item = WorkItem.create!(
      work_queue: queue,
      title: "Add calendar export",
      spec_url: "specs/add-calendar-export.md",
      stage_name: "decompose",
      status: :claimed
    )
    stage_config = queue.stage_configs.find_by!(stage_name: "decompose")
    claim = Claim.create!(work_item: work_item, agent_type: "inline_claude", status: :completed)
    Report.create!(
      claim: claim,
      work_item: work_item,
      stage_name: "decompose",
      status: :success,
      body: {
        "summary" => "Split into model and API slices",
        "children" => [
          {
            "title" => "Add calendar export model",
            "spec_inline" => "Create export model and validations using TDD",
            "tags" => { "domain" => "models" }
          },
          {
            "title" => "Add calendar export endpoint",
            "spec_inline" => "Expose export endpoint using TDD",
            "tags" => { "domain" => "api" }
          }
        ]
      }
    )

    Engine::TransitionManager.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload).to be_waiting
    expect(work_item.stage_name).to eq("decompose")
    expect(work_item.children.count).to eq(2)
    expect(work_item.children.pluck(:stage_name)).to eq(%w[build build])
    expect(work_item.children.pluck(:status).uniq).to eq(["pending"])
    expect(work_item.children.first.spec_inline).to include("Create export model")
    expect(work_item.transition_logs.last.trigger).to eq("decompose")
  end
end
