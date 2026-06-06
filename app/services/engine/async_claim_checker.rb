module Engine
  class AsyncClaimChecker
    BASE_BACKOFF_SECONDS = 10
    MAX_BACKOFF_SECONDS = 300

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
      return if in_backoff_window?(claim)

      if claim_age_exceeded?(claim)
        claim.update!(
          status: :timed_out,
          async_execution: false,
          completed_at: Time.current,
          metadata: claim.metadata.merge("error" => "async claim exceeded max age")
        )
        return
      end

      if claim.heartbeat_stale?
        claim.update!(
          status: :failed,
          async_execution: false,
          completed_at: Time.current,
          metadata: claim.metadata.merge("error" => "async heartbeat stale")
        )
        return
      end

      provider = claim.assignment.dig("async", "provider")

      if provider == "github_ci_poll"
        adapter = Adapters::GithubCiPollAdapter.new
        poll_result = adapter.check_status(claim)
        return if poll_result == :running

        stage_config = claim.work_item.work_queue.stage_configs.find_by!(stage_name: claim.work_item.stage_name)
        Engine::ClaimResultPersister.new(claim: claim, stage_config: stage_config).call(poll_result)
        claim.update!(status: :completed, async_execution: false, completed_at: Time.current)
        Engine::TransitionManager.new(work_item: claim.work_item, claim: claim, stage_config: stage_config).call
        return
      end

      return unless provider == "codex"

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
      record_poll_failure(claim, e)
    end

    DEFAULT_MAX_ASYNC_CLAIM_AGE_SECONDS = 3600

    def claim_age_exceeded?(claim)
      return false unless claim.started_at.present?

      max_age_seconds = claim.work_item&.work_queue&.config&.dig("max_async_claim_age_seconds") ||
        DEFAULT_MAX_ASYNC_CLAIM_AGE_SECONDS
      claim.started_at < max_age_seconds.seconds.ago
    end

    def in_backoff_window?(claim)
      backoff_until = claim.metadata["async_poll_backoff_until"]
      return false unless backoff_until

      Time.iso8601(backoff_until) > Time.current
    rescue ArgumentError
      false
    end

    def record_poll_failure(claim, _error)
      failures = claim.metadata.fetch("async_poll_failures", 0) + 1
      backoff_seconds = [BASE_BACKOFF_SECONDS * (2**(failures - 1)), MAX_BACKOFF_SECONDS].min
      jitter = rand(0..(backoff_seconds / 2))
      claim.update!(
        metadata: claim.metadata.merge(
          "async_poll_failures" => failures,
          "async_poll_backoff_until" => (Time.current + backoff_seconds + jitter).iso8601
        )
      )
    end
  end
end
