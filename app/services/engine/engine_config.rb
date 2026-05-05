# app/services/engine/engine_config.rb
module Engine
  class EngineConfig
    DEFAULT_MAX_PIPE_DEPTH = 3
    DEFAULT_MAX_CHILDREN_PER_PIPE = 5
    DEFAULT_PIPES_ENABLED = true

    def self.instance
      @instance ||= new
    end

    # Call in tests to force reload after changing config/engine.yml
    def self.reset!
      @instance = nil
    end

    def initialize
      config = load_config
      pipes = config.fetch("pipes", {})
      @max_pipe_depth = pipes.fetch("max_depth", DEFAULT_MAX_PIPE_DEPTH)
      @max_children_per_pipe = pipes.fetch("max_children_per_pipe", DEFAULT_MAX_CHILDREN_PER_PIPE)
      @pipes_enabled = pipes.fetch("enabled", DEFAULT_PIPES_ENABLED)
    end

    def pipes_enabled?
      @pipes_enabled
    end

    def max_pipe_depth
      @max_pipe_depth
    end

    def max_children_per_pipe
      @max_children_per_pipe
    end

    private

    def load_config
      config_path = Rails.root.join("config/engine.yml")
      return {} unless config_path.exist?

      YAML.load_file(config_path) || {}
    end
  end
end
