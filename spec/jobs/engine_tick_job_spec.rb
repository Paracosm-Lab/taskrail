require "rails_helper"

RSpec.describe EngineTickJob, type: :job do
  it "runs one engine tick" do
    runner = instance_double(Engine::Runner)
    allow(Engine::Runner).to receive(:new).and_return(runner)
    allow(runner).to receive(:call)

    described_class.perform_now

    expect(runner).to have_received(:call)
  end

  it "processes pending work across queues" do
    first_queue = queue_with_stage("first")
    second_queue = queue_with_stage("second")
    first = WorkItem.create!(work_queue: first_queue, title: "First", spec_url: "opaque", stage_name: "intake")
    second = WorkItem.create!(work_queue: second_queue, title: "Second", spec_url: "opaque", stage_name: "intake")

    described_class.perform_now

    expect(first.reload.claims.completed.count).to eq(1)
    expect(second.reload.claims.completed.count).to eq(1)
    expect(first.stage_name).to eq("done")
    expect(second.stage_name).to eq("done")
  end

  it "does nothing when there are no pending items" do
    queue = queue_with_stage("empty")
    WorkItem.create!(work_queue: queue, title: "Blocked", spec_url: "opaque", stage_name: "intake", status: :blocked)

    expect { described_class.perform_now }.not_to change(Claim, :count)
  end

  it "marks adapter failures and continues with other work" do
    queue = WorkQueue.create!(name: "Mixed", slug: "mixed-#{SecureRandom.hex(4)}", stages: %w[ok boom done])
    StageConfig.create!(work_queue: queue, stage_name: "ok", adapter_type: "fake", completion_criteria: ["report_present"])
    StageConfig.create!(work_queue: queue, stage_name: "boom", adapter_type: "raising_fake", completion_criteria: ["report_present"])
    ok = WorkItem.create!(work_queue: queue, title: "OK", spec_url: "opaque", stage_name: "ok")
    boom = WorkItem.create!(work_queue: queue, title: "Boom", spec_url: "opaque", stage_name: "boom")
    adapter_class = Class.new { def execute(_assignment) = raise("adapter failed") }
    stub_const("Engine::ClaimExecutor::ADAPTERS", Engine::ClaimExecutor::ADAPTERS.merge("raising_fake" => adapter_class))

    described_class.perform_now

    expect(ok.reload.claims.completed.count).to eq(1)
    expect(boom.reload.claims.last).to be_failed
  end

  it "does not create duplicate claims under concurrent ticks" do
    queue = WorkQueue.create!(name: "Async", slug: "async-job-#{SecureRandom.hex(4)}", stages: %w[build done])
    StageConfig.create!(work_queue: queue, stage_name: "build", adapter_type: "async_fake", completion_criteria: ["branch_created"])
    item = WorkItem.create!(work_queue: queue, title: "Async", spec_url: "opaque", stage_name: "build")
    adapter_class = Class.new do
      def execute(_assignment)
        Engine::AsyncAdapterResult.new(provider: "codex", external_id: SecureRandom.uuid, status: "submitted", metadata: {}, trace_events: [])
      end
    end
    stub_const("Engine::ClaimExecutor::ADAPTERS", Engine::ClaimExecutor::ADAPTERS.merge("async_fake" => adapter_class))

    threads = 2.times.map { Thread.new { ActiveRecord::Base.connection_pool.with_connection { described_class.perform_now } } }
    threads.each(&:join)

    expect(item.reload.claims.count).to eq(1)
  end

  it "only claims pending items" do
    queue = queue_with_stage("statuses")
    pending = WorkItem.create!(work_queue: queue, title: "Pending", spec_url: "opaque", stage_name: "intake")
    active = WorkItem.create!(work_queue: queue, title: "Active", spec_url: "opaque", stage_name: "intake")
    Claim.create!(work_item: active, agent_type: "fake", status: :active)
    WorkItem.create!(work_queue: queue, title: "Completed", spec_url: "opaque", stage_name: "intake", status: :completed)
    WorkItem.create!(work_queue: queue, title: "Blocked", spec_url: "opaque", stage_name: "intake", status: :blocked)

    described_class.perform_now

    expect(pending.reload.claims.completed.count).to eq(1)
    expect(active.reload.claims.count).to eq(1)
    expect(Claim.count).to eq(2)
  end

  def queue_with_stage(slug_prefix)
    queue = WorkQueue.create!(name: slug_prefix, slug: "#{slug_prefix}-#{SecureRandom.hex(4)}", stages: %w[intake done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake", completion_criteria: ["report_present"])
    queue
  end
end
