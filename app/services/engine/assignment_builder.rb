module Engine
  class AssignmentBuilder
    def initialize(claim:, stage_config:)
      @claim = claim
      @stage_config = stage_config
      @work_item = claim.work_item
    end

    def build
      {
        claim_id: @claim.id,
        callback_url: "/api/v1/claims/#{@claim.id}/report",
        work_item: work_item_payload,
        stage: stage_payload,
        stage_config: stage_config_payload,
        prompt: @stage_config.agent_prompt,
        model: @stage_config.model_override,
        context: context_payload,
        skills: skills_payload,
        limits: limits_payload
      }
    end

    private

    def work_item_payload
      {
        id: @work_item.id,
        title: @work_item.title,
        spec_url: @work_item.spec_url,
        tags: @work_item.tags,
        parent_id: @work_item.parent_id
      }
    end

    def stage_payload
      {
        name: @stage_config.stage_name,
        adapter_type: @stage_config.adapter_type,
        adapter_config: @stage_config.adapter_config,
        allowed_skills: @stage_config.allowed_skills,
        forbidden_skills: @stage_config.forbidden_skills,
        completion_criteria: @stage_config.completion_criteria
      }
    end

    def stage_config_payload
      {
        stage_name: @stage_config.stage_name,
        adapter_type: @stage_config.adapter_type,
        allowed_skills: @stage_config.allowed_skills,
        forbidden_skills: @stage_config.forbidden_skills,
        completion_criteria: @stage_config.completion_criteria,
        agent_prompt: @stage_config.agent_prompt,
        timeout_seconds: @stage_config.timeout_seconds,
        adapter_config: @stage_config.adapter_config
      }
    end

    def context_payload
      spec_content = begin
        SpecResolver.new(@work_item.spec_url).resolve
      rescue SpecResolver::FetchError => e
        Rails.logger.warn "SpecResolver failed for work_item #{@work_item.id}: #{e.message}"
        nil
      end

      {
        spec_content: spec_content,
        upstream_reports: upstream_reports,
        upstream_artifacts: upstream_artifacts,
        feedback: @work_item.metadata["feedback"],
        human_answer: @work_item.metadata["human_answer"]
      }
    end

    def upstream_reports
      @work_item.reports.where.not(claim_id: @claim.id).order(:created_at).map(&:body)
    end

    def upstream_artifacts
      @work_item.artifacts.where("claim_id != ? OR claim_id IS NULL", @claim.id).order(:created_at).map do |artifact|
        { "kind" => artifact.kind, "data" => artifact.data }
      end
    end

    def limits_payload
      {
        timeout_seconds: @claim.timeout_seconds || @stage_config.timeout_seconds,
        max_tokens: @stage_config.work_queue.config["max_tokens"],
        max_cost_cents: @stage_config.work_queue.config["max_cost_cents"]
      }
    end

    def skills_payload
      allowed = @stage_config.allowed_skills || []
      forbidden = @stage_config.forbidden_skills || []

      {
        allowed: Engine::SkillLoader.load_all(allowed),
        forbidden: forbidden
      }
    end
  end
end
