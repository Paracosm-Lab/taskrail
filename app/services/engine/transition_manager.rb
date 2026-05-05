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

      results
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
  end
end
