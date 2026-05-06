require "rails_helper"

RSpec.describe Engine::PipeEvaluator do
  def make_queue(slug, stages)
    WorkQueue.create!(name: slug, slug: "#{slug}-#{SecureRandom.hex(4)}", stages: stages)
  end

  def make_pipe(from_queue:, from_stage:, to_queue:, to_stage: nil, when_config: {}, transform_config: {}, limits: {})
    Pipe.create!(
      name: "Test Pipe",
      slug: "test-pipe-#{SecureRandom.hex(4)}",
      from_queue: from_queue,
      from_stage: from_stage,
      to_queue: to_queue,
      to_stage: to_stage,
      when_config: when_config,
      transform_config: transform_config,
      limits: limits
    )
  end

  def make_work_item(queue:, stage:, pipe: nil, parent: nil)
    WorkItem.create!(
      title: "Test item",
      spec_url: "opaque://spec",
      work_queue: queue,
      stage_name: stage,
      pipe: pipe,
      parent: parent
    )
  end

  it "creates a downstream work item in the target queue" do
    src_queue = make_queue("src", ["scan", "done"])
    dst_queue = make_queue("dst", ["intake", "done"])
    pipe = make_pipe(from_queue: src_queue, from_stage: "scan", to_queue: dst_queue)

    item = make_work_item(queue: src_queue, stage: "done") # already advanced past scan

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    downstream = WorkItem.where(work_queue: dst_queue)
    expect(downstream.count).to eq(1)
    expect(downstream.first.stage_name).to eq("intake")
    expect(downstream.first.parent_id).to eq(item.id)
    expect(downstream.first.pipe_id).to eq(pipe.id)
    expect(downstream.first.spec_url).to eq("pipe://#{pipe.slug}/#{item.id}")
    expect(downstream.first.tags["pipe_slug"]).to eq(pipe.slug)
    expect(downstream.first.tags["source_queue"]).to eq(src_queue.slug)
    expect(downstream.first.tags["source_work_item"]).to eq(item.id)
  end

  it "creates transition logs on source and downstream items" do
    src_queue = make_queue("src-log", ["scan", "done"])
    dst_queue = make_queue("dst-log", ["intake", "done"])
    make_pipe(from_queue: src_queue, from_stage: "scan", to_queue: dst_queue)

    item = make_work_item(queue: src_queue, stage: "done")

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    pipe_log = item.transition_logs.find_by(trigger: "pipe")
    expect(pipe_log).to be_present
    expect(pipe_log.details["target_queue"]).to eq(dst_queue.slug)

    downstream = WorkItem.where(work_queue: dst_queue).first
    recv_log = downstream.transition_logs.find_by(trigger: "pipe_received")
    expect(recv_log).to be_present
    expect(recv_log.details["source_work_item_id"]).to eq(item.id)
  end

  it "skips the pipe when when conditions do not match" do
    src_queue = make_queue("src-cond", ["scan", "done"])
    dst_queue = make_queue("dst-cond", ["intake", "done"])
    make_pipe(
      from_queue: src_queue, from_stage: "scan", to_queue: dst_queue,
      when_config: {
        "artifact_kind" => "severity_report",
        "conditions" => [{ "field" => "grade", "operator" => "equals", "value" => "F" }]
      }
    )

    item = make_work_item(queue: src_queue, stage: "done")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed)
    Artifact.create!(work_item: item, claim: claim, kind: "severity_report", data: { "grade" => "A" })

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    expect(WorkItem.where(work_queue: dst_queue)).to be_empty
  end

  it "fires the pipe when when conditions match" do
    src_queue = make_queue("src-match", ["scan", "done"])
    dst_queue = make_queue("dst-match", ["intake", "done"])
    make_pipe(
      from_queue: src_queue, from_stage: "scan", to_queue: dst_queue,
      when_config: {
        "artifact_kind" => "severity_report",
        "conditions" => [{ "field" => "grade", "operator" => "equals", "value" => "F" }]
      }
    )

    item = make_work_item(queue: src_queue, stage: "done")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed)
    Artifact.create!(work_item: item, claim: claim, kind: "severity_report", data: { "grade" => "F" })

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    expect(WorkItem.where(work_queue: dst_queue).count).to eq(1)
  end

  it "copies and remaps artifacts to the downstream item" do
    src_queue = make_queue("src-art", ["scan", "done"])
    dst_queue = make_queue("dst-art", ["intake", "done"])
    make_pipe(
      from_queue: src_queue, from_stage: "scan", to_queue: dst_queue,
      transform_config: {
        "artifacts" => [
          { "from_kind" => "severity_report", "to_kind" => "input_findings" },
          { "from_kind" => "raw_scan" }
        ]
      }
    )

    item = make_work_item(queue: src_queue, stage: "done")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: :completed)
    Artifact.create!(work_item: item, claim: claim, kind: "severity_report", data: { "count" => 3 })
    Artifact.create!(work_item: item, claim: claim, kind: "raw_scan", data: { "lines" => 10 })

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    downstream = WorkItem.where(work_queue: dst_queue).first
    findings = downstream.artifacts.find_by(kind: "input_findings")
    raw = downstream.artifacts.find_by(kind: "raw_scan")

    expect(findings).to be_present
    expect(findings.data["count"]).to eq(3)
    expect(findings.claim_id).to be_nil

    expect(raw).to be_present
    expect(raw.data["lines"]).to eq(10)
  end

  it "skips missing artifact kinds silently" do
    src_queue = make_queue("src-miss", ["scan", "done"])
    dst_queue = make_queue("dst-miss", ["intake", "done"])
    make_pipe(
      from_queue: src_queue, from_stage: "scan", to_queue: dst_queue,
      transform_config: { "artifacts" => [{ "from_kind" => "does_not_exist" }] }
    )

    item = make_work_item(queue: src_queue, stage: "done")

    expect { Engine::PipeEvaluator.call(work_item: item, from_stage: "scan") }.not_to raise_error
    downstream = WorkItem.where(work_queue: dst_queue).first
    expect(downstream.artifacts).to be_empty
  end

  it "does not fire when global pipes are disabled" do
    Engine::EngineConfig.instance.instance_variable_set(:@pipes_enabled, false)

    src_queue = make_queue("src-dis", ["scan", "done"])
    dst_queue = make_queue("dst-dis", ["intake", "done"])
    make_pipe(from_queue: src_queue, from_stage: "scan", to_queue: dst_queue)
    item = make_work_item(queue: src_queue, stage: "done")

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    expect(WorkItem.where(work_queue: dst_queue)).to be_empty
  ensure
    Engine::EngineConfig.instance.instance_variable_set(:@pipes_enabled, true)
  end

  it "enforces max_children per pipe and logs limit_reached" do
    src_queue = make_queue("src-lim", ["scan", "done"])
    dst_queue = make_queue("dst-lim", ["intake", "done"])
    pipe = make_pipe(from_queue: src_queue, from_stage: "scan", to_queue: dst_queue, limits: { "max_children" => 1 })

    item = make_work_item(queue: src_queue, stage: "done")
    # Pre-create an existing child for this pipe+parent
    WorkItem.create!(title: "Existing", spec_url: "pipe://x/y", work_queue: dst_queue, stage_name: "intake", pipe: pipe, parent: item)

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    expect(WorkItem.where(work_queue: dst_queue).count).to eq(1) # no new item created
    expect(item.transition_logs.find_by(trigger: "pipe_limit_reached")).to be_present
  end

  it "enforces max_depth and logs limit_reached" do
    Engine::EngineConfig.instance.instance_variable_set(:@max_pipe_depth, 1)

    q1 = make_queue("d1", ["s", "done"])
    q2 = make_queue("d2", ["s", "done"])
    q3 = make_queue("d3", ["s", "done"])
    pipe1 = make_pipe(from_queue: q1, from_stage: "s", to_queue: q2)
    make_pipe(from_queue: q2, from_stage: "s", to_queue: q3)

    root = make_work_item(queue: q1, stage: "done")
    child = make_work_item(queue: q2, stage: "done", pipe: pipe1, parent: root)

    Engine::PipeEvaluator.call(work_item: child, from_stage: "s")

    expect(WorkItem.where(work_queue: q3)).to be_empty
    expect(child.transition_logs.find_by(trigger: "pipe_limit_reached")).to be_present
  ensure
    Engine::EngineConfig.instance.instance_variable_set(:@max_pipe_depth, 3)
  end

  it "is idempotent — does not create a second item if pipe already fired" do
    src_queue = make_queue("src-idem", ["scan", "done"])
    dst_queue = make_queue("dst-idem", ["intake", "done"])
    pipe = make_pipe(from_queue: src_queue, from_stage: "scan", to_queue: dst_queue)
    item = make_work_item(queue: src_queue, stage: "done")

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")
    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    expect(WorkItem.where(work_queue: dst_queue, pipe: pipe, parent: item).count).to eq(1)
  end

  it "uses title_template interpolation" do
    src_queue = make_queue("src-title", ["scan", "done"])
    dst_queue = make_queue("dst-title", ["intake", "done"])
    make_pipe(
      from_queue: src_queue, from_stage: "scan", to_queue: dst_queue,
      transform_config: { "title_template" => "Fix for {{source.title}} via {{pipe.name}}" }
    )

    item = make_work_item(queue: src_queue, stage: "done")
    item.update!(title: "Big Security Bug")

    Engine::PipeEvaluator.call(work_item: item, from_stage: "scan")

    downstream = WorkItem.where(work_queue: dst_queue).first
    expect(downstream.title).to eq("Fix for Big Security Bug via Test Pipe")
  end
end
