# config/initializers/engine_config.rb
Rails.application.config.after_initialize do
  Engine::EngineConfig.instance
end
