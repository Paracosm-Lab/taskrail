module Engine
  class Runner
    def call
      advance_waiting_parents
      work_item = next_work_item
      return unless work_item

      match = AgentMatcher.new(work_item: work_item).call
      claim = work_item.claims.create!(agent_type: match.agent_type, status: :active)

      result = ClaimExecutor.new(claim: claim, stage_config: match.stage_config).call
      TransitionManager.new(work_item: work_item, claim: claim, stage_config: match.stage_config).call unless result.is_a?(Engine::AsyncAdapterResult)

      work_item
    end

    private

    def next_work_item
      WorkItem.pending.order(:created_at).detect { |work_item| work_item.claims.active.none? }
    end

    def advance_waiting_parents
      WorkItem.waiting.find_each do |work_item|
        TransitionManager.advance_waiting_parent(work_item)
      end
    end
  end
end
