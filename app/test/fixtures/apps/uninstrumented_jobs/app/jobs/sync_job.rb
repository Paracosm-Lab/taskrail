class SyncJob < ApplicationJob
  sidekiq_options retry: true # infinite retries, no dead letter

  def perform(record_id)
    ExternalApi.sync(record_id) # no timeout, no error handling
  end
end
