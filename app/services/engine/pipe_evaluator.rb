module Engine
  class PipeEvaluator
    def self.call(work_item:, from_stage:)
      new(work_item: work_item, from_stage: from_stage).call
    end

    def initialize(work_item:, from_stage:)
      @work_item = work_item
      @from_stage = from_stage
      @config = EngineConfig.instance
    end

    def call
      return unless @config.pipes_enabled?

      depth = pipe_depth
      if depth >= @config.max_pipe_depth
        log_limit_reached(nil, "max_depth", depth, @config.max_pipe_depth)
        return
      end

      pipes = Pipe.where(from_queue: @work_item.work_queue, from_stage: @from_stage, enabled: true)
      pipes.each { |pipe| evaluate_pipe(pipe) }
    end

    private

    def evaluate_pipe(pipe)
      return unless conditions_pass?(pipe)

      existing = WorkItem.where(pipe_id: pipe.id, parent_id: @work_item.id).count

      # Idempotency: if the pipe already fired for this source item, skip silently.
      # This check must come before max_children so a repeated call doesn't log a
      # spurious pipe_limit_reached event.
      return if existing >= 1

      max_children = effective_max_children(pipe)
      if existing >= max_children
        log_limit_reached(pipe, "max_children", existing, max_children)
        return
      end

      create_downstream_item(pipe)
    end

    def conditions_pass?(pipe)
      when_config = pipe.when_config
      return true if when_config.blank?

      conditions = when_config.fetch("conditions", [])
      return true if conditions.blank?

      artifact_kind = when_config["artifact_kind"]
      artifact = @work_item.artifacts.where(kind: artifact_kind).order(created_at: :desc).first
      return false unless artifact

      PipeConditionEvaluator.new(artifact_data: artifact.data, conditions: conditions).passes?
    end

    def create_downstream_item(pipe)
      target_queue = pipe.to_queue
      target_stage = pipe.to_stage.presence || target_queue.stages.first

      downstream = WorkItem.create!(
        title: interpolate_title(pipe),
        spec_url: "pipe://#{pipe.slug}/#{@work_item.id}",
        work_queue: target_queue,
        stage_name: target_stage,
        status: :pending,
        parent_id: @work_item.id,
        pipe_id: pipe.id,
        tags: build_tags(pipe)
      )

      copy_artifacts(pipe, downstream)

      @work_item.transition_logs.create!(
        from_stage: @from_stage,
        to_stage: @work_item.stage_name,
        trigger: "pipe",
        details: {
          pipe_slug: pipe.slug,
          target_queue: target_queue.slug,
          created_item_id: downstream.id
        }
      )

      downstream.transition_logs.create!(
        from_stage: nil,
        to_stage: target_stage,
        trigger: "pipe_received",
        details: {
          pipe_slug: pipe.slug,
          source_queue: @work_item.work_queue.slug,
          source_work_item_id: @work_item.id
        }
      )

      downstream
    end

    def copy_artifacts(pipe, downstream)
      mappings = pipe.transform_config.fetch("artifacts", [])
      mappings.each do |mapping|
        from_kind = mapping.fetch("from_kind")
        to_kind = mapping["to_kind"].presence || from_kind

        source = @work_item.artifacts.where(kind: from_kind).order(created_at: :desc).first
        next unless source

        downstream.artifacts.create!(kind: to_kind, data: source.data)
      end
    end

    def build_tags(pipe)
      transform_tags = pipe.transform_config.fetch("tags", {})
      auto_tags = {
        "pipe_slug" => pipe.slug,
        "source_queue" => @work_item.work_queue.slug,
        "source_work_item" => @work_item.id
      }
      transform_tags.merge(auto_tags)
    end

    def interpolate_title(pipe)
      template = pipe.transform_config["title_template"].presence ||
                 "#{@work_item.title} (via #{pipe.name})"
      template
        .gsub("{{source.title}}", @work_item.title)
        .gsub("{{source.id}}", @work_item.id.to_s)
        .gsub("{{pipe.name}}", pipe.name)
    end

    def pipe_depth
      PipeDepth.for(@work_item)
    end

    def effective_max_children(pipe)
      per_pipe = pipe.limits["max_children"]
      global = @config.max_children_per_pipe
      per_pipe ? [per_pipe, global].min : global
    end

    def log_limit_reached(pipe, limit_type, current_count, max)
      @work_item.transition_logs.create!(
        from_stage: @from_stage,
        to_stage: @work_item.stage_name,
        trigger: "pipe_limit_reached",
        details: {
          pipe_slug: pipe&.slug,
          limit_type: limit_type,
          current_count: current_count,
          max: max
        }
      )
    end
  end
end
