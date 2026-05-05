class SyncJob
  def perform(user_id)
    user = User.find(user_id)
    ExternalApi.sync(user)
  rescue
    # silently swallowed
  end
end
