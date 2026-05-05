require "rails_helper"

RSpec.describe "feature development cookbook fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/feature_development") }

  it "ships a self-contained fixture app without absolute paths" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("Gemfile")).to exist
    expect(fixture_root.join("lib/calendar_export.rb")).to exist
    expect(fixture_root.join("spec/calendar_export_spec.rb")).to exist

    files = Dir[fixture_root.join("**/*")].select { |path| File.file?(path) }
    contents = files.map { |path| File.read(path) }.join("
")
    absolute_users_path = ["", "Users", ""].join(File::SEPARATOR)
    expect(contents).not_to include(absolute_users_path)
    expect(contents).not_to include(Rails.root.to_s)
  end

  it "documents the feature development cookbook workflow and CLI commands" do
    doc = Rails.root.join("docs/cookbooks/04-feature-development.md")
    expect(doc).to exist

    content = doc.read
    expect(content).to include("# Cookbook 04: Feature Development")
    expect(content).to include("development-codex")
    expect(content).to include("intake -> decompose -> build -> test -> review -> done")
    expect(content).to include("stupidclaw submit --queue development-codex")
    expect(content).to include("stupidclaw status")
    expect(content).to include("stupidclaw answer")
    expect(content).to include("test/fixtures/apps/feature_development")
    absolute_users_path = ["", "Users", ""].join(File::SEPARATOR)
    expect(content).not_to include(absolute_users_path)
  end
end
