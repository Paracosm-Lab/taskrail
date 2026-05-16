class DashboardPayloadBuilder
  ACTIVE_LIMIT = 200
  COMPLETED_LIMIT = 10
  COST_CACHE_TTL = 5.seconds

  def self.snapshot(queue_slug:, limit: ACTIVE_LIMIT)
    new(queue_slug:, limit:).snapshot
  end

  def self.cursor(queue_slug:)
    queue = WorkQueue.find_by!(slug: queue_slug)
    [
      queue.updated_at.to_i,
      queue.work_items.maximum(:updated_at)&.to_i,
      queue.work_items.count,
      Trace.maximum(:updated_at)&.to_i,
      Trace.count
    ].join(":")
  end

  def initialize(queue_slug:, limit: ACTIVE_LIMIT)
    @queue = WorkQueue.find_by!(slug: queue_slug)
    @limit = [[limit.to_i, 1].max, ACTIVE_LIMIT].min
  end

  def snapshot
    active_items = @queue.work_items
      .includes(:work_queue, :claims)
      .where.not(status: :completed)
      .order(updated_at: :desc)
      .limit(@limit)
      .to_a
    completed_items = @queue.work_items
      .includes(:work_queue, :claims)
      .where(status: :completed)
      .order(updated_at: :desc)
      .limit(COMPLETED_LIMIT)
      .to_a
    items = active_items + completed_items

    {
      event_type: "snapshot",
      cursor: self.class.cursor(queue_slug: @queue.slug),
      queue: { id: @queue.id, name: @queue.name, slug: @queue.slug, stages: @queue.stages },
      stages: stages,
      work_items: items.map { |item| serialize_work_item(item) },
      meta: {
        active_limit: @limit,
        completed_limit: COMPLETED_LIMIT,
        active_truncated: @queue.work_items.where.not(status: :completed).count > @limit,
        completed_truncated: @queue.work_items.where(status: :completed).count > COMPLETED_LIMIT
      },
      today_costs: cached_totals("today", Trace.where(created_at: Time.zone.today.beginning_of_day..)),
      total_costs: cached_totals("total", Trace.all)
    }
  end

  private

  def stages
    configs = @queue.stage_configs.index_by(&:stage_name)
    @queue.stages.map do |stage_name|
      config = configs[stage_name]
      { name: stage_name, adapter_type: config&.adapter_type, completion_criteria: config&.completion_criteria || [] }
    end
  end

  def serialize_work_item(item)
    {
      id: item.id,
      title: item.title,
      spec_url: item.spec_url,
      queue: item.work_queue.slug,
      stage_name: item.stage_name,
      status: item.status,
      tags: item.tags,
      metadata: item.metadata.except("escalation"),
      retry_count: item.retry_count,
      regression_count: item.regression_count,
      active_claim: active_claim_summary(item),
      escalation: escalation_summary(item)
    }
  end

  def active_claim_summary(item)
    claim = item.claims.active.order(created_at: :desc).first
    return nil unless claim

    {
      id: claim.id,
      agent_type: claim.agent_type,
      status: claim.status,
      async_execution: claim.async_execution,
      external_id: claim.assignment.dig("async", "external_id"),
      last_heartbeat_at: claim.last_heartbeat_at&.iso8601,
      heartbeat_message: claim.heartbeat_message,
      heartbeat_stale: claim.heartbeat_stale?
    }
  end

  def escalation_summary(item)
    escalation = item.metadata["escalation"]
    return nil unless item.blocked? && escalation.present?

    {
      target: escalation["target"],
      reason: escalation["reason"] || item.metadata["blocked_reason"],
      question: escalation["question"],
      human_action_required: escalation.fetch("human_action_required", item.blocked?)
    }
  end

  def cached_totals(name, scope)
    Rails.cache.fetch(cost_cache_key(name, scope), expires_in: COST_CACHE_TTL) do
      {
        total_tokens_in: scope.sum(:total_tokens_in),
        total_tokens_out: scope.sum(:total_tokens_out),
        total_cost_cents: scope.sum(:total_cost_cents),
        total_duration_ms: scope.sum(:total_duration_ms)
      }
    end
  end

  def cost_cache_key(name, scope)
    "dashboard-costs/#{name}/#{scope.maximum(:updated_at)&.to_i}/#{scope.count}"
  end
end
