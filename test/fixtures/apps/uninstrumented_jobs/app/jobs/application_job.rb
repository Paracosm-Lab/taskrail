class ApplicationJob
  def self.sidekiq_options(*) = nil
  def self.sidekiq_retries_exhausted(&) = nil
end
