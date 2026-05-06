require "rails_helper"

RSpec.describe Engine::Digest do
  include ActiveSupport::Testing::TimeHelpers

  around do |example|
    travel_to Time.zone.parse("2026-05-05 14:00:00 UTC") do
      example.run
    end
  end

  it "summarizes pipeline activity scoped to the window and includes current blockers" do
    queue = WorkQueue.create!(name: "Operations", slug: "operations-#{SecureRandom.hex(4)}", stages: %w[ingest cluster review done])
    inside_item = WorkItem.create!(work_queue: queue, title: "db-pool-timeout", spec_url: "opaque spec", stage_name: "cluster", status: :pending)
    old_item = WorkItem.create!(work_queue: queue, title: "old", spec_url: "opaque spec", stage_name: "ingest", status: :pending)
    completed_inside = WorkItem.create!(work_queue: queue, title: "fixed", spec_url: "opaque spec", stage_name: "done", status: :completed)
    completed_old = WorkItem.create!(work_queue: queue, title: "fixed-old", spec_url: "opaque spec", stage_name: "done", status: :completed)
    blocked_item = WorkItem.create!(work_queue: queue, title: "rate-limit-exceeded", spec_url: "opaque spec", stage_name: "human_review", status: :blocked)
    claim = Claim.create!(work_item: inside_item, agent_type: "fake")
    blocked_claim = Claim.create!(work_item: blocked_item, agent_type: "fake")

    Artifact.create!(claim: claim, work_item: inside_item, kind: "clusters", data: {})
    Artifact.create!(claim: claim, work_item: inside_item, kind: "runbook_draft", data: {})
    Artifact.create!(claim: claim, work_item: inside_item, kind: "runbook_published", data: {})
    old_artifact = Artifact.create!(claim: claim, work_item: old_item, kind: "clusters", data: {})
    old_artifact.update_column(:created_at, 3.hours.ago)

    completed_inside.update_column(:updated_at, 30.minutes.ago)
    completed_old.update_column(:updated_at, 3.hours.ago)

    Trace.create!(claim: claim, work_item: inside_item, stage_name: "cluster", agent_type: "fake", total_tokens_in: 10, total_tokens_out: 20, total_cost_cents: 7)
    old_trace = Trace.create!(claim: claim, work_item: old_item, stage_name: "ingest", agent_type: "fake", total_tokens_in: 100, total_tokens_out: 200, total_cost_cents: 70)
    old_trace.update_column(:created_at, 3.hours.ago)

    spawn_log = TransitionLog.create!(work_item: inside_item, from_stage: "assess", to_stage: "build", trigger: "spawn")
    transition = TransitionLog.create!(work_item: inside_item, from_stage: "ingest_signals", to_stage: "cluster_failures", trigger: "advance")
    transition.update_column(:created_at, spawn_log.created_at + 1.second)
    old_transition = TransitionLog.create!(work_item: old_item, from_stage: "old", to_stage: "older", trigger: "advance")
    old_transition.update_column(:created_at, 3.hours.ago)
    Report.create!(claim: blocked_claim, work_item: blocked_item, stage_name: "human_review", status: :blocked, blocked_question: "Key on IP or user_id?")

    digest = described_class.generate(since: 2.hours.ago, window: "2h")

    expect(digest).to include(
      since: "2026-05-05T12:00:00Z",
      generated_at: "2026-05-05T14:00:00Z",
      window: "2h"
    )
    expect(digest.fetch(:summary)).to eq(
      clusters_created: 1,
      runbooks_drafted: 1,
      runbooks_published: 1,
      items_completed: 1,
      items_spawned: 1,
      items_blocked: 1
    )
    expect(digest.fetch(:costs)).to eq(cents: 7, tokens_in: 10, tokens_out: 20)
    expect(digest.fetch(:blocked_items)).to eq([
      {
        id: blocked_item.id,
        title: "rate-limit-exceeded",
        stage_name: "human_review",
        question: "Key on IP or user_id?"
      }
    ])
    expect(digest.fetch(:recent_transitions)).to eq([
      {
        work_item_id: transition.work_item_id,
        title: "db-pool-timeout",
        from_stage: "ingest_signals",
        to_stage: "cluster_failures",
        trigger: "advance",
        at: transition.created_at.utc.iso8601
      },
      {
        work_item_id: spawn_log.work_item_id,
        title: "db-pool-timeout",
        from_stage: "assess",
        to_stage: "build",
        trigger: "spawn",
        at: spawn_log.created_at.utc.iso8601
      }
    ])
  end
end
