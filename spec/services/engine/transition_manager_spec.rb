require "rails_helper"

RSpec.describe Engine::TransitionManager do
  it "advances to the next stage when criteria pass" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["branch_created"])
    work_item = WorkItem.create!(work_queue: queue, title: "Build thing", spec_url: "opaque spec", stage_name: "build", retry_count: 2, status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "build", status: :success)
    Artifact.create!(claim: claim, work_item: work_item, kind: "branch", data: { "name" => "sc/test" })

    described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("test")
    expect(work_item).to be_pending
    expect(work_item.retry_count).to eq(0)
    expect(work_item.transition_logs.last.trigger).to eq("rule_satisfied")
    expect(work_item.transition_logs.last.from_stage).to eq("build")
    expect(work_item.transition_logs.last.to_stage).to eq("test")
  end

  it "marks the work item completed when advancing into done" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[review done])
    stage_config = StageConfig.create!(work_queue: queue, stage_name: "review", completion_criteria: ["review_verdict"])
    work_item = WorkItem.create!(work_queue: queue, title: "Review thing", spec_url: "opaque spec", stage_name: "review", status: :claimed)
    claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    Report.create!(claim: claim, work_item: work_item, stage_name: "review", status: :success, body: { "verdict" => "approved" })

    described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call

    expect(work_item.reload.stage_name).to eq("done")
    expect(work_item).to be_completed
  end

  describe "spawn_cross_queue_items! — Gap 1: unknown queue_slug" do
    it "raises InvalidSpawnDefinition (not RecordNotFound) when queue_slug does not exist" do
      queue = WorkQueue.create!(name: "Source Queue", slug: "source-queue-#{SecureRandom.hex(4)}", stages: %w[build done])
      stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["report_present"])
      work_item = WorkItem.create!(work_queue: queue, title: "Spawn thing", spec_url: "opaque spec", stage_name: "build", status: :claimed)
      claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
      Report.create!(
        claim: claim,
        work_item: work_item,
        stage_name: "build",
        status: :success,
        body: {
          "spawn_work_items" => [
            { "queue_slug" => "nonexistent-queue-slug", "title" => "Spawned item" }
          ]
        }
      )

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /nonexistent-queue-slug/)
    end

    it "wraps the error as InvalidSpawnDefinition, not ActiveRecord::RecordNotFound" do
      queue = WorkQueue.create!(name: "Source Queue", slug: "source-queue-#{SecureRandom.hex(4)}", stages: %w[build done])
      stage_config = StageConfig.create!(work_queue: queue, stage_name: "build", completion_criteria: ["report_present"])
      work_item = WorkItem.create!(work_queue: queue, title: "Spawn thing", spec_url: "opaque spec", stage_name: "build", status: :claimed)
      claim = Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
      Report.create!(
        claim: claim,
        work_item: work_item,
        stage_name: "build",
        status: :success,
        body: {
          "spawn_work_items" => [
            { "queue_slug" => "nonexistent-queue-slug", "title" => "Spawned item" }
          ]
        }
      )

      raised_class = nil
      begin
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      rescue => e
        raised_class = e.class
      end

      expect(raised_class).to eq(Engine::TransitionManager::InvalidSpawnDefinition)
    end
  end

  describe "decompose — Gap 2: malformed children validation" do
    let(:hex) { SecureRandom.hex(4) }
    let(:queue) do
      WorkQueue.create!(name: "Decompose Queue", slug: "decompose-queue-#{hex}", stages: %w[decompose build done])
    end
    let(:stage_config) do
      StageConfig.create!(work_queue: queue, stage_name: "decompose", completion_criteria: ["report_present"])
    end
    let(:work_item) do
      WorkItem.create!(work_queue: queue, title: "Parent item", spec_url: "opaque spec", stage_name: "decompose", status: :claimed)
    end
    let(:claim) do
      Claim.create!(work_item: work_item, agent_type: "fake", status: :completed)
    end

    def make_decompose_report(children:)
      Report.create!(
        claim: claim,
        work_item: work_item,
        stage_name: "decompose",
        status: :success,
        body: { "children" => children }
      )
    end

    it "raises InvalidSpawnDefinition when children is not an array" do
      make_decompose_report(children: { "not" => "an array" })

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /must be an array/)
    end

    it "raises InvalidSpawnDefinition when a child is not a hash" do
      make_decompose_report(children: ["just a string"])

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /must be an object/)
    end

    it "raises InvalidSpawnDefinition when a child is missing title" do
      make_decompose_report(children: [{ "spec_url" => "http://example.com/spec" }])

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /title is required/)
    end

    it "raises InvalidSpawnDefinition when a child has a blank title" do
      make_decompose_report(children: [{ "title" => "  " }])

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /title is required/)
    end

    it "raises InvalidSpawnDefinition when a child tags is not a hash" do
      make_decompose_report(children: [{ "title" => "Child A", "tags" => ["not", "a", "hash"] }])

      expect {
        described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call
      }.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition, /tags must be an object/)
    end

    it "decomposes successfully with valid children" do
      make_decompose_report(children: [
        { "title" => "Child A", "tags" => { "priority" => "high" } },
        { "title" => "Child B" }
      ])

      described_class.new(work_item: work_item, claim: claim, stage_config: stage_config).call

      work_item.reload
      expect(work_item).to be_waiting
      expect(work_item.children.count).to eq(2)
      expect(work_item.children.map(&:title)).to contain_exactly("Child A", "Child B")
      expect(work_item.children.first.stage_name).to eq("build")
      expect(work_item.transition_logs.last.trigger).to eq("decompose")
    end
  end
end
