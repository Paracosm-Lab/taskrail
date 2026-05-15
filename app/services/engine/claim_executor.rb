module Engine
  class ClaimExecutor
    class UnknownAdapter < StandardError; end

    ADAPTERS = {
      "fake" => Adapters::FakeAdapter,
      "shell_script" => Adapters::ShellScriptAdapter,
      "inline_claude" => Adapters::InlineClaudeAdapter,
      "codex" => Adapters::CodexAdapter,
      "docker_compose" => Adapters::DockerComposeAdapter
    }.freeze

    def initialize(claim:, stage_config:)
      @claim = claim
      @stage_config = stage_config
    end

    def call
      @claim.update!(started_at: Time.current) unless @claim.started_at
      assignment = AssignmentBuilder.new(claim: @claim, stage_config: @stage_config).build
      @claim.update!(assignment: assignment.deep_stringify_keys)

      result = adapter.execute(assignment)
      return start_async_result(result) if result.is_a?(Engine::AsyncAdapterResult)

      persist_result(result)
      @claim.update!(status: :completed, completed_at: Time.current)
      result
    rescue UnknownAdapter
      @claim.update!(status: :failed, completed_at: Time.current)
      raise
    rescue StandardError, SecurityError
      @claim.update!(status: :failed, completed_at: Time.current)
      raise
    end

    private

    def adapter
      adapter_class = ADAPTERS[@stage_config.adapter_type]
      raise UnknownAdapter, "unknown adapter: #{@stage_config.adapter_type}" unless adapter_class

      adapter_class.new
    end

    def start_async_result(result)
      @claim.update!(
        status: :active,
        async_execution: true,
        assignment: @claim.assignment.merge(
          "async" => {
            "provider" => result.provider,
            "external_id" => result.external_id,
            "status" => result.status,
            "metadata" => result.metadata
          }
        )
      )
      result
    end

    def persist_result(result)
      Engine::ClaimResultPersister.new(claim: @claim, stage_config: @stage_config).call(result)
    end

  end
end
