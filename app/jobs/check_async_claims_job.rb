class CheckAsyncClaimsJob < ApplicationJob
  queue_as :default

  def perform
    Engine::AsyncClaimChecker.new.call
  end
end
