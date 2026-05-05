class ProcessUserJob < ApplicationJob
  queue_as :default

  def perform(user_id)
    Rails.logger.info "processing user"
    UserProcessor.call(user_id: user_id)
  end
end
