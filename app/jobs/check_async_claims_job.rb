class CheckAsyncClaimsJob < ApplicationJob
  queue_as :default

  def perform
    Claim.active.where(async_execution: true).find_each do |_claim|
      # MVP-0 has no async adapters yet.
    end
  end
end
