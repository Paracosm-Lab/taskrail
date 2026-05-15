module Engine
  class Digest
    def self.generate(since:, window: nil)
      new(since: since, window: window).generate
    end

    def initialize(since:, window: nil, generated_at: Time.zone.now)
      @since = since
      @window = window
      @generated_at = generated_at
    end

    def generate
      {
        since: iso8601(@since),
        generated_at: iso8601(@generated_at),
        window: @window,
        summary: summary,
        costs: costs,
        blocked_items: blocked_items,
        recent_transitions: recent_transitions
      }
    end

    private

    def summary
      {
        clusters_created: Artifact.where(kind: "clusters", created_at: @since..).count,
        runbooks_drafted: Artifact.where(kind: "runbook_draft", created_at: @since..).count,
        runbooks_published: Artifact.where(kind: "runbook_published", created_at: @since..).count,
        items_completed: WorkItem.completed.where(updated_at: @since..).count,
        items_spawned: TransitionLog.where(trigger: "spawn", created_at: @since..).count,
        items_blocked: blocked_scope.count
      }
    end

    def costs
      traces = Trace.where(created_at: @since..)
      {
        cents: traces.sum(:total_cost_cents),
        tokens_in: traces.sum(:total_tokens_in),
        tokens_out: traces.sum(:total_tokens_out)
      }
    end

    def blocked_items
      blocked_scope.order(:created_at).map do |item|
        report = item.reports.blocked.order(created_at: :desc).first
        {
          id: item.id,
          title: item.title,
          stage_name: item.stage_name,
          question: report&.blocked_question
        }
      end
    end

    def recent_transitions
      TransitionLog.includes(:work_item).where(created_at: @since..).order(created_at: :desc).limit(50).map do |transition|
        {
          work_item_id: transition.work_item_id,
          title: transition.work_item.title,
          from_stage: transition.from_stage,
          to_stage: transition.to_stage,
          trigger: transition.trigger,
          at: iso8601(transition.created_at)
        }
      end
    end

    def blocked_scope
      WorkItem.blocked
    end

    def iso8601(time)
      time.utc.iso8601
    end
  end
end
