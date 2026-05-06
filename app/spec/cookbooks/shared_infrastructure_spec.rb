require "rails_helper"
require "yaml"

RSpec.describe "shared cookbook infrastructure" do
  let(:root) { Rails.root.join("cookbooks") }

  it "defines the shared cookbook directory contract" do
    expect(root.join("README.md")).to exist
    expect(root.join("docker-compose.yml")).to exist
    expect(root.join(".env.example")).to exist
    expect(root.join("fake_services", "README.md")).to exist
    expect(root.join("fake_services", "fake_service.rb")).to exist
    expect(root.join("fixtures", "README.md")).to exist
    expect(root.join("fixtures", "apps", ".keep")).to exist
    expect(root.join("queues", "README.md")).to exist
    expect(root.join("prompts", "README.md")).to exist
    expect(root.join("runbooks", "README.md")).to exist
  end

  it "defines docker-friendly fake services with Rails-root-relative mounts" do
    compose = YAML.safe_load_file(root.join("docker-compose.yml"))
    services = compose.fetch("services")

    expect(services.keys).to include(
      "fake-sentry",
      "fake-logs",
      "fake-api",
      "fake-worker",
      "fake-monitoring",
      "fake-staging-app"
    )

    serialized = compose.to_yaml
    expect(serialized).to include("./fake_services:/app:ro")
    expect(serialized).not_to include(Rails.root.to_s)
    expect(serialized).not_to include("/Users/")
  end

  it "documents portable queue YAML expectations for cookbook-specific specs" do
    readme = root.join("README.md").read

    expect(readme).to include("file://cookbooks/prompts/")
    expect(readme).to include("Do not commit absolute checkout paths")
    expect(readme).to include("cookbooks/docker-compose.yml")
  end

  it "keeps shared cookbook files free of local absolute checkout paths" do
    shared_files = Dir[root.join("**", "*")].select { |path| File.file?(path) }
    offenders = shared_files.select do |path|
      content = File.read(path)
      content.include?(Rails.root.to_s) || content.include?("/Users/")
    end

    expect(offenders).to eq([])
  end
end
