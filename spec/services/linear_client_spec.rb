# spec/services/linear_client_spec.rb
require "rails_helper"
require "webmock/rspec"

WebMock.disable_net_connect!(allow_localhost: true)

RSpec.describe LinearClient do
  let(:client) { described_class.new(api_key: "test-key") }

  describe "#postrunner_issues" do
    it "returns issues with postrunner label" do
      stub_request(:post, "https://api.linear.app/graphql")
        .to_return(body: {
          data: {
            issues: {
              nodes: [
                { id: "issue-1", identifier: "ENG-173", title: "test finding",
                  description: "details", labels: { nodes: [{ name: "postrunner" }, { name: "crm-service" }] } }
              ]
            }
          }
        }.to_json)

      issues = client.postrunner_issues
      expect(issues.size).to eq(1)
      expect(issues.first["identifier"]).to eq("ENG-173")
    end

    it "returns empty array on API error" do
      stub_request(:post, "https://api.linear.app/graphql")
        .to_return(status: 500)

      expect(client.postrunner_issues).to eq([])
    end
  end
end
