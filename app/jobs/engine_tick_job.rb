class EngineTickJob < ApplicationJob
  queue_as :default

  def perform
    Engine::Runner.new.call
  end
end
