require "rails_helper"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.describe SentryClient do
  let(:client) { described_class.new(api_token: "fake-token", org: "scribbl") }

  describe "#fetch_issues" do
    it "returns parsed issues from Sentry API" do
      fixture = [
        {
          "id" => "12345",
          "title" => "ActiveRecord::ConnectionTimeoutError",
          "culprit" => "app.controllers.sessions",
          "count" => 143,
          "userCount" => 12,
          "firstSeen" => "2026-05-04T14:03:00Z",
          "lastSeen" => "2026-05-04T14:45:00Z",
          "project" => { "slug" => "crm-service" },
          "metadata" => { "type" => "ActiveRecord::ConnectionTimeoutError", "value" => "pool timeout" },
          "level" => "error",
          "status" => "unresolved"
        }
      ]

      stub_request(:get, %r{sentry.io/api/0/organizations/scribbl/issues/})
        .with(headers: { "Authorization" => "Bearer fake-token" })
        .to_return(status: 200, body: fixture.to_json, headers: { "Content-Type" => "application/json" })

      issues = client.fetch_issues(since: 24.hours.ago)

      expect(issues.length).to eq(1)
      expect(issues[0]["title"]).to eq("ActiveRecord::ConnectionTimeoutError")
      expect(issues[0]["project"]["slug"]).to eq("crm-service")
    end

    it "returns empty array on API error" do
      stub_request(:get, %r{sentry.io/api/0/organizations/scribbl/issues/})
        .to_return(status: 500, body: "Internal Server Error")

      issues = client.fetch_issues(since: 24.hours.ago)

      expect(issues).to eq([])
    end

    it "encodes optional project query parameter" do
      request = stub_request(:get, "https://sentry.io/api/0/organizations/scribbl/issues/")
        .with(query: hash_including("query" => "is:unresolved", "sort" => "freq", "statsPeriod" => "24h", "project" => "crm-service"))
        .to_return(status: 200, body: [].to_json, headers: { "Content-Type" => "application/json" })

      expect(client.fetch_issues(since: 24.hours.ago, project: "crm-service")).to eq([])
      expect(request).to have_been_requested
    end

    it "does not make a request when credentials are missing" do
      client = described_class.new(api_token: nil, org: "")

      expect(client.fetch_issues(since: 24.hours.ago)).to eq([])
      expect(WebMock).not_to have_requested(:get, %r{sentry.io/api/0})
    end
  end
end
