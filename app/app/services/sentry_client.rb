require "json"
require "net/http"
require "uri"

class SentryClient
  BASE_URL = "https://sentry.io/api/0"

  def initialize(api_token: ENV["SENTRY_API_TOKEN"], org: ENV["SENTRY_ORG"])
    @api_token = api_token
    @org = org
  end

  def fetch_issues(since:, project: nil)
    return [] unless configured?

    uri = URI("#{BASE_URL}/organizations/#{URI.encode_uri_component(@org)}/issues/")
    params = { query: "is:unresolved", sort: "freq", statsPeriod: stats_period(since) }
    params[:project] = project if project
    uri.query = URI.encode_www_form(params)

    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{@api_token}"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10, write_timeout: 5) { |http| http.request(request) }
    return JSON.parse(response.body) if response.code.to_i == 200

    Rails.logger.error("Sentry API error: #{response.code} #{response.body.to_s.truncate(200)}")
    []
  rescue StandardError => e
    Rails.logger.error("Sentry fetch failed: #{e.message}")
    []
  end

  private

  def configured?
    if @api_token.blank? || @org.blank?
      Rails.logger.error("Sentry fetch skipped: missing Sentry configuration")
      false
    else
      true
    end
  end

  def stats_period(since)
    seconds = [(Time.current - since).to_i, 1.hour.to_i].max
    hours = (seconds / 1.hour.to_i.to_f).ceil
    "#{hours}h"
  end
end
