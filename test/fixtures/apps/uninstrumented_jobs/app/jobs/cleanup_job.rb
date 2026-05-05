class CleanupJob < ApplicationJob
  def perform
    User.inactive.find_each do |user|
      user.anonymize!
    rescue => e
      # silently continue
    end
  end
end
