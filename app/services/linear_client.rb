require "net/http"
require "json"

class LinearClient
  API_URL = "https://api.linear.app/graphql"

  def initialize(api_key:)
    @api_key = api_key
  end

  def postrunner_issues
    query = <<~GQL
      {
        issues(filter: {
          labels: { some: { name: { eq: "postrunner" } } }
          state: { type: { nin: ["completed", "canceled", "duplicate"] } }
        }, first: 50) {
          nodes {
            id
            identifier
            title
            description
            labels { nodes { name } }
          }
        }
      }
    GQL
    post(query).dig("data", "issues", "nodes") || []
  rescue StandardError => e
    Rails.logger.error("[LinearClient] Failed to fetch issues: #{e.message}")
    []
  end

  private

  def post(query)
    uri = URI(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    req = Net::HTTP::Post.new(uri.path, {
      "Authorization" => @api_key,
      "Content-Type" => "application/json"
    })
    req.body = { query: query }.to_json
    resp = http.request(req)
    JSON.parse(resp.body)
  end
end
