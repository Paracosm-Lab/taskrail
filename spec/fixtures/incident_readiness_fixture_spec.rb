require "rails_helper"

RSpec.describe "incident readiness fixtures" do
  it "provides docker-friendly service evidence without absolute paths" do
    root = Rails.root.join("spec/fixtures/incident_readiness")

    expect(root.join("docker-compose.yml")).to exist
    expect(root.join("CODEOWNERS")).to exist
    expect(root.join("services/api/config/routes.rb")).to exist
    expect(root.join("services/api/docs/runbooks/api-down.md")).to exist
    expect(root.join("services/worker/README.md")).to exist

    contents = root.glob("**/*").select(&:file?).map(&:read).join("
")
    expect(contents).not_to include("/Users/gregmushen/work/code/stupidclaw")
  end
end
