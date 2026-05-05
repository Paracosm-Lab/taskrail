module Engine
  class TransitionManager
    class InvalidSpawnDefinition < StandardError; end

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
      return regress_or_block_generated_tests if generated_test_regression_requested?(results)

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

      ActiveRecord::Base.transaction do
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

        spawn_cross_queue_items!(from_stage: from_stage)
      end
    end

    def spawn_cross_queue_items!(from_stage:)
      report = @claim.reports.success.where(stage_name: from_stage).order(created_at: :desc, id: :desc).first
      spawn_items = normalized_spawn_items(report)
      return if spawn_items.blank?

      spawned_ids = spawn_items.map do |item_def|
        target_queue = WorkQueue.find_by!(slug: item_def.fetch("queue_slug"))
        title = item_def.fetch("title")

        WorkItem.create!(
          title: title,
          spec_url: item_def["spec_url"].presence || "spawned://#{@work_item.id}/#{title.parameterize}",
          work_queue: target_queue,
          stage_name: target_queue.stages.first,
          parent_id: @work_item.id,
          tags: item_def.fetch("tags", {}).merge(
            "source_queue" => @work_item.work_queue.slug,
            "source_work_item" => @work_item.id
          ),
          metadata: item_def["spec_inline"].present? ? { "spec_inline" => item_def["spec_inline"] } : {}
        ).id
      end

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: @work_item.stage_name,
        trigger: "spawn",
        details: {
          spawned_count: spawn_items.length,
          spawned_item_ids: spawned_ids,
          target_queues: spawn_items.map { |item_def| item_def.fetch("queue_slug") }.uniq
        }
      )
    end

    def normalized_spawn_items(report)
      raw_items = report&.body&.fetch("spawn_work_items", []) || []
      raise InvalidSpawnDefinition, "spawn_work_items must be an array" unless raw_items.is_a?(Array)

      raw_items.map do |item_def|
        raise InvalidSpawnDefinition, "spawn item must be an object" unless item_def.is_a?(Hash)
        raise InvalidSpawnDefinition, "spawn item queue_slug is required" if item_def["queue_slug"].blank?
        raise InvalidSpawnDefinition, "spawn item title is required" if item_def["title"].blank?
        raise InvalidSpawnDefinition, "spawn item tags must be an object" unless item_def.fetch("tags", {}).is_a?(Hash)

        item_def
      end
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
      reason = reasons.join("; ")
      escalation = human_escalation_payload(reason)

      @work_item.update!(
        status: :blocked,
        metadata: @work_item.metadata.merge("blocked_reason" => reason, "escalation" => escalation)
      )

      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "blocked",
        details: { reasons: reasons, retry_count: @work_item.retry_count, escalation_target: escalation.fetch("target"), human_action_required: true }
      )
    end

    def max_retries
      @stage_config.max_retries || @work_item.work_queue.config["default_max_retries"] || 3
    end

    def human_escalation_payload(reason)
      {
        "target" => escalation_target,
        "reason" => reason,
        "stage_name" => @work_item.stage_name,
        "retry_count" => @work_item.retry_count,
        "human_action_required" => true,
        "question" => "Work item blocked in #{@work_item.stage_name}: #{reason}. Provide guidance or retry/cancel."
      }
    end

    def escalation_target
      raw_target = @stage_config.escalation_target.presence || @work_item.work_queue.config["default_escalation"]
      raw_target == "block_and_notify" ? "human" : (raw_target.presence || "human")
    end

    def review_regression_requested?
      @work_item.stage_name == "review" && review_report&.body&.fetch("verdict", nil) == "request_changes"
    end

    def generated_test_regression_requested?(results)
      @work_item.stage_name == "run_tests" && results.any? { |result| !result.passed? } && previous_stage_named?("generate_tests")
    end

    def previous_stage_named?(stage_name)
      stages = @work_item.work_queue.stages
      current_index = stages.index(@work_item.stage_name)
      current_index.present? && current_index.positive? && stages.fetch(current_index - 1) == stage_name
    end

    def regress_or_block_generated_tests
      if @work_item.regression_count < max_regression_loops
        regress_generated_tests
      else
        block_regression_exhausted
      end
    end

    def regress_generated_tests
      from_stage = @work_item.stage_name
      feedback = generated_test_feedback
      next_regression_count = @work_item.regression_count + 1

      @work_item.update!(
        stage_name: "generate_tests",
        status: :pending,
        retry_count: 0,
        regression_count: next_regression_count,
        metadata: @work_item.metadata.merge("feedback" => feedback)
      )

      @work_item.transition_logs.create!(
        from_stage: from_stage,
        to_stage: "generate_tests",
        trigger: "regression",
        details: { feedback: feedback, regression_count: next_regression_count }
      )
    end

    def generated_test_feedback
      artifact = @claim.artifacts.where(kind: "test_results").order(created_at: :desc, id: :desc).first
      output = artifact&.data&.fetch("output", nil).presence
      failures = Array(artifact&.data&.fetch("failures", [])).join("; ").presence
      [output, failures].compact.join("\n").presence || "generated tests failed"
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
      escalation = human_escalation_payload(reason)

      @work_item.update!(
        status: :blocked,
        metadata: @work_item.metadata.merge("blocked_reason" => reason, "escalation" => escalation)
      )

      @work_item.transition_logs.create!(
        from_stage: @work_item.stage_name,
        to_stage: @work_item.stage_name,
        trigger: "blocked",
        details: { reasons: [reason], regression_count: @work_item.regression_count, escalation_target: escalation.fetch("target"), human_action_required: true }
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
