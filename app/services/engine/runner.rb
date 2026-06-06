module Engine
  class Runner
    def call
      advance_waiting_parents

      first_processed = nil
      processed_ids = []

      while (claim_context = next_claim_context(excluded_ids: processed_ids))
        work_item = claim_context.fetch(:work_item)
        claim = claim_context.fetch(:claim)
        stage_config = claim_context.fetch(:stage_config)
        first_processed ||= work_item
        processed_ids << work_item.id

        process_claim(work_item:, claim:, stage_config:)
      end

      first_processed
    end

    private

    def next_claim_context(excluded_ids:)
      WorkItem.transaction do
        # FOR UPDATE SKIP LOCKED: each engine tick atomically claims the first
        # available item, skipping any rows already locked by a concurrent tick.
        # The NOT EXISTS clause excludes items that already have an active claim.
        scope = WorkItem
          .pending
          .lock("FOR UPDATE SKIP LOCKED")
          .order(:created_at)
          .where("NOT EXISTS (SELECT 1 FROM claims WHERE claims.work_item_id = work_items.id AND claims.status = ?)", Claim.statuses[:active])
        scope = scope.where.not(id: excluded_ids) if excluded_ids.any?
        work_item = scope.first
        next unless work_item

        match = AgentMatcher.new(work_item: work_item).call
        claim = work_item.claims.create!(agent_type: match.agent_type, status: :active)

        { work_item:, claim:, stage_config: match.stage_config }
      end
    end

    def process_claim(work_item:, claim:, stage_config:)
      result = ClaimExecutor.new(claim:, stage_config:).call
      TransitionManager.new(work_item:, claim:, stage_config:).call unless result.is_a?(Engine::AsyncAdapterResult)
    rescue StandardError, SecurityError => e
      Rails.logger.error("Engine::Runner failed for WorkItem##{work_item.id}: #{e.class}: #{e.message}")
      claim.update!(
        status: :failed,
        completed_at: Time.current,
        metadata: claim.metadata.merge("error" => e.message, "error_class" => e.class.name)
      )
    end

    def advance_waiting_parents
      WorkItem.waiting.find_each do |work_item|
        TransitionManager.advance_waiting_parent(work_item)
      end
    end
  end
end
