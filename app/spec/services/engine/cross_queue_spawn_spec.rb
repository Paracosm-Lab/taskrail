require "rails_helper"

RSpec.describe "TransitionManager cross-queue spawn" do
  it "creates work items in target queue when report includes spawn_work_items" do
    ops_queue = WorkQueue.create!(name: "Ops", slug: "ops-spawn-#{SecureRandom.hex(4)}", stages: ["assess", "map", "done"])
    ops_queue.stage_configs.create!(stage_name: "assess", adapter_type: "fake", completion_criteria: ["report_present"])
    ops_queue.stage_configs.create!(stage_name: "map", adapter_type: "fake")

    dev_queue = WorkQueue.create!(name: "Dev", slug: "dev-spawn-#{SecureRandom.hex(4)}", stages: ["intake", "build", "done"])

    item = WorkItem.create!(title: "Test ops", spec_url: "opaque spec", work_queue: ops_queue, stage_name: "assess")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Report.create!(claim: claim, work_item: item, stage_name: "assess", status: "success", body: {
      "spawn_work_items" => [{
        "queue_slug" => dev_queue.slug,
        "title" => "Improve instrumentation",
        "spec_inline" => "Add Sentry.set_context calls",
        "tags" => { "domain" => "instrumentation" }
      }]
    })

    stage_config = ops_queue.stage_configs.find_by!(stage_name: "assess")
    Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call

    expect(item.reload.stage_name).to eq("map")

    spawned = WorkItem.where(work_queue: dev_queue)
    expect(spawned.count).to eq(1)
    expect(spawned.first.title).to eq("Improve instrumentation")
    expect(spawned.first.spec_url).to start_with("spawned://#{item.id}/")
    expect(spawned.first.stage_name).to eq("intake")
    expect(spawned.first.parent_id).to eq(item.id)
    expect(spawned.first.tags["domain"]).to eq("instrumentation")
    expect(spawned.first.tags["source_queue"]).to eq(ops_queue.slug)
    expect(spawned.first.tags["source_work_item"]).to eq(item.id)
    expect(spawned.first.metadata["spec_inline"]).to eq("Add Sentry.set_context calls")

    spawn_log = item.transition_logs.find_by(trigger: "spawn")
    expect(spawn_log).to be_present
    expect(spawn_log.details["spawned_count"]).to eq(1)
    expect(spawn_log.details["target_queues"]).to eq([dev_queue.slug])
  end

  it "does nothing when report has no spawn_work_items" do
    queue = WorkQueue.create!(name: "Ops", slug: "ops-nospawn-#{SecureRandom.hex(4)}", stages: ["assess", "done"])
    queue.stage_configs.create!(stage_name: "assess", adapter_type: "fake", completion_criteria: ["report_present"])

    item = WorkItem.create!(title: "Test", spec_url: "opaque spec", work_queue: queue, stage_name: "assess")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Report.create!(claim: claim, work_item: item, stage_name: "assess", status: "success", body: {})

    stage_config = queue.stage_configs.find_by!(stage_name: "assess")

    expect do
      Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call
    end.not_to change(WorkItem, :count).from(1)
  end

  it "uses spawn items only from the stage being advanced" do
    ops_queue = WorkQueue.create!(name: "Ops", slug: "ops-stage-spawn-#{SecureRandom.hex(4)}", stages: ["assess", "map", "done"])
    ops_queue.stage_configs.create!(stage_name: "assess", adapter_type: "fake", completion_criteria: ["report_present"])
    dev_queue = WorkQueue.create!(name: "Dev", slug: "dev-stage-spawn-#{SecureRandom.hex(4)}", stages: ["intake", "done"])

    item = WorkItem.create!(title: "Test ops", spec_url: "opaque spec", work_queue: ops_queue, stage_name: "assess")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Report.create!(claim: claim, work_item: item, stage_name: "other", status: "success", created_at: 1.minute.from_now, body: {
      "spawn_work_items" => [{ "queue_slug" => dev_queue.slug, "title" => "Wrong stage spawn" }]
    })
    Report.create!(claim: claim, work_item: item, stage_name: "assess", status: "success", created_at: Time.current, body: {})

    stage_config = ops_queue.stage_configs.find_by!(stage_name: "assess")
    Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call

    expect(WorkItem.where(work_queue: dev_queue)).to be_empty
    expect(item.reload.stage_name).to eq("map")
  end

  it "does not advance or partially spawn when spawn payload is malformed" do
    ops_queue = WorkQueue.create!(name: "Ops", slug: "ops-bad-spawn-#{SecureRandom.hex(4)}", stages: ["assess", "map", "done"])
    ops_queue.stage_configs.create!(stage_name: "assess", adapter_type: "fake", completion_criteria: ["report_present"])
    dev_queue = WorkQueue.create!(name: "Dev", slug: "dev-bad-spawn-#{SecureRandom.hex(4)}", stages: ["intake", "done"])

    item = WorkItem.create!(title: "Test ops", spec_url: "opaque spec", work_queue: ops_queue, stage_name: "assess")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Report.create!(claim: claim, work_item: item, stage_name: "assess", status: "success", body: {
      "spawn_work_items" => [
        { "queue_slug" => dev_queue.slug, "title" => "Should roll back" },
        { "queue_slug" => dev_queue.slug, "tags" => [] }
      ]
    })

    stage_config = ops_queue.stage_configs.find_by!(stage_name: "assess")

    expect do
      expect do
        Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call
      end.to raise_error(Engine::TransitionManager::InvalidSpawnDefinition)
    end.not_to change(WorkItem, :count)
    expect(item.reload.stage_name).to eq("assess")
    expect(item.transition_logs).to be_empty
  end
end
