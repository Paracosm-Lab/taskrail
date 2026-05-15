class ExternalApi
  def self.sync(user)
    HTTP.get("https://api.example.com/sync/#{user.id}") # no timeout
  end
end
