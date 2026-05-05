module Engine
  class TransitionManager
    def self.advance_waiting_parent(work_item)
      return unless work_item.waiting?
      return unless work_item.children.any?
      return unless work_item.children.all?(&:completed?)

      from_stage = work_item.stage_name
      stages = work_item.work_queue.stages
      to_stage = stages.fetch(stages.index(from_stage) + 1)

      work_item.update!(stage_name: to_stage, status: :pending)
      work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: to_stage,
        trigger: "children_completed",
        details: { children_count: work_item.children.count }
      )
    end

    def initialize(work_item:, claim:, stage_config:)
      @work_item = work_item
      @claim = claim
      @stage_config = stage_config
    end

    def call
      results = predicate_results
      return decompose if results.all?(&:passed?) && decompose_children.any?
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

    def decompose
      from_stage = @work_item.stage_name
      child_stage = next_stage

      decompose_children.each_with_index do |child, index|
        @work_item.children.create!(
          work_queue: @work_item.work_queue,
          title: child.fetch("title"),
          spec_url: child.fetch("spec_url", @work_item.spec_url),
          stage_name: child_stage,
          status: :pending,
          position: index,
          tags: child.fetch("tags", {})
        )
      end

      @work_item.update!(status: :waiting)

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: child_stage,
        trigger: "rule_satisfied",
        details: { criteria: @stage_config.completion_criteria, children_count: decompose_children.count }
      )
    end

    def decompose_children
      return [] unless @work_item.stage_name == "decompose"

      decompose_report&.body&.fetch("children", []) || []
    end

    def decompose_report
      @decompose_report ||= @claim.reports.where(stage_name: "decompose").order(created_at: :desc).first
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
