module Engine
  class TransitionManager
    def initialize(work_item:, claim:, stage_config:)
      @work_item = work_item
      @claim = claim
      @stage_config = stage_config
    end

    def call
      results = predicate_results
      return advance if results.all?(&:passed?)
      return regress_or_block_review if review_regression_requested?

      retry_or_block(results)
    end

    private

    def predicate_results
      @stage_config.completion_criteria.map do |criterion|
        PredicateRegistry.resolve(criterion).new(claim: @claim).call
      end
    end

    def advance
      from_stage = @work_item.stage_name
      to_stage = next_stage
      terminal = to_stage == "done"

      @work_item.update!(
        stage_name: to_stage,
        status: terminal ? :completed : :pending,
        retry_count: 0
      )

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: to_stage,
        trigger: "rule_satisfied",
        details: { criteria: @stage_config.completion_criteria }
      )
    end

    def next_stage
      stages = @work_item.work_queue.stages
      current_index = stages.index(@work_item.stage_name)
      stages.fetch(current_index + 1)
    end

    def retry_or_block(results)
      reasons = results.reject(&:passed?).map(&:reason).compact

      if @work_item.retry_count < max_retries
        retry_with_feedback(reasons)
      else
        block_with_reasons(reasons)
      end
    end

    def retry_with_feedback(reasons)
      @work_item.update!(
        status: :pending,
        retry_count: @work_item.retry_count + 1,
        metadata: @work_item.metadata.merge("feedback" => reasons.join("; "))
      )

      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "retry",
        details: { reasons: reasons, retry_count: @work_item.retry_count }
      )
    end

    def block_with_reasons(reasons)
      @work_item.update!(
        status: :blocked,
        metadata: @work_item.metadata.merge("blocked_reason" => reasons.join("; "))
      )

      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "blocked",
        details: { reasons: reasons, retry_count: @work_item.retry_count }
      )
    end

    def max_retries
      @stage_config.max_retries || @work_item.work_queue.config["default_max_retries"] || 3
    end

    def review_regression_requested?
      @work_item.stage_name == "review" && review_report&.body&.fetch("verdict", nil) == "request_changes"
    end

    def regress_or_block_review
      if @work_item.regression_count < max_regression_loops
        regress_review
      else
        block_regression_exhausted
      end
    end

    def regress_review
      from_stage = @work_item.stage_name
      feedback = review_feedback
      next_regression_count = @work_item.regression_count + 1

      @work_item.update!(
        stage_name: "build",
        status: :pending,
        retry_count: 0,
        regression_count: next_regression_count,
        metadata: @work_item.metadata.merge("feedback" => feedback)
      )

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: "build",
        trigger: "regression",
        details: { feedback: feedback, regression_count: next_regression_count }
      )
    end

    def block_regression_exhausted
      reason = "regression loop budget exhausted"

      @work_item.update!(
        status: :blocked,
        metadata: @work_item.metadata.merge("blocked_reason" => reason)
      )

      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "blocked",
        details: { reasons: [reason], regression_count: @work_item.regression_count }
      )
    end

    def max_regression_loops
      @work_item.work_queue.config["max_regression_loops"] || 3
    end

    def review_feedback
      review_report&.body&.fetch("feedback", nil).presence || "review requested changes"
    end

    def review_report
      @review_report ||= @claim.reports.where(stage_name: "review").order(created_at: :desc).first
    end
  end
end
