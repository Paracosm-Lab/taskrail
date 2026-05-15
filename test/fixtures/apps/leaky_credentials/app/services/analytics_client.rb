class AnalyticsClient
  def self.write_key
    ENV["ANALYTICS_WRITE_KEY"]
  end
end
