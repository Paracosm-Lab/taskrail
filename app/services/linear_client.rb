require "net/http"
require "json"

class LinearClient
  API_URL = "https://api.linear.app/graphql"

  def initialize(api_key:)
    @api_key = api_key
  end

  def close_issue(issue_id)
    # Fetch the first completed-type state for this issue's team
    state_query = <<~GQL
      {
        issue(id: "#{issue_id}") {
          team {
            states(filter: { type: { eq: "completed" } }) {
              nodes { id name }
            }
          }
        }
      }
    GQL
    state_id = post(state_query).dig("data", "issue", "team", "states", "nodes", 0, "id")
    return false unless state_id

    mutation = <<~GQL
      mutation {
        issueUpdate(id: "#{issue_id}", input: { stateId: "#{state_id}" }) {
          success
        }
      }
    GQL
    post(mutation).dig("data", "issueUpdate", "success") == true
  rescue StandardError => e
    Rails.logger.error("[LinearClient] Failed to close issue #{issue_id}: #{e.message}")
    false
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
