module Engine
  class AsyncClaimChecker
    def call
      Claim.active.where(async_execution: true).in_batches do |batch|
        Claim.transaction do
          batch.lock("FOR UPDATE SKIP LOCKED").each { |claim| process_claim(claim) }
        end
      end
    end

    private

    def process_claim(claim)
      # Re-check after acquiring the lock: another worker may have completed this claim
      # between the in_batches pluck and the FOR UPDATE SKIP LOCKED re-query.
      return unless claim.active? && claim.async_execution?

      if claim.heartbeat_stale?
        claim.update!(
          status: :failed,
          async_execution: false,
          completed_at: Time.current,
          metadata: claim.metadata.merge("error" => "async heartbeat stale")
        )
        return
      end

      return unless claim.assignment.dig("async", "provider") == "codex"

      stage_config = claim.work_item.work_queue.stage_configs.find_by!(stage_name: claim.work_item.stage_name)
      poll_result = CodexCliPoller.new(
        command: stage_config.adapter_config.fetch("poll_command", "codex"),
        args: stage_config.adapter_config.fetch("poll_args", ["status", "--json"]),
        external_id: claim.assignment.dig("async", "external_id"),
        working_directory: stage_config.adapter_config.fetch("working_directory", Rails.root.to_s),
        timeout_seconds: stage_config.timeout_seconds || claim.timeout_seconds
      ).call

      return if poll_result.status == "running"

      result = CodexResultNormalizer.new(claim: claim, poll_result: poll_result).call
      Engine::ClaimResultPersister.new(claim: claim, stage_config: stage_config).call(result)
      claim.update!(status: :completed, async_execution: false, completed_at: Time.current)
      Engine::TransitionManager.new(work_item: claim.work_item, claim: claim, stage_config: stage_config).call
    rescue StandardError => e
      Rails.logger.error("AsyncClaimChecker failed for Claim##{claim.id}: #{e.class}: #{e.message}")
    end
  end
end
