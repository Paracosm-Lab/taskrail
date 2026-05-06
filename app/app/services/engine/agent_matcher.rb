module Engine
  class AgentMatcher
    Match = Struct.new(:stage_config, :agent_type, keyword_init: true)

    def initialize(work_item:)
      @work_item = work_item
    end

    def call
      Match.new(stage_config: stage_config, agent_type: stage_config.adapter_type)
    end

    private

    def stage_config
      @stage_config ||= StageConfig.find_by!(
        work_queue: @work_item.work_queue,
        stage_name: @work_item.stage_name
      )
    end
  end
end
