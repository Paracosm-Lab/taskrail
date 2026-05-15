require "rails_helper"
require "json"
require "rbconfig"

RSpec.describe "validate_api_docs_artifact.rb" do
  let(:script_path) { Rails.root.join("scripts/validate_api_docs_artifact.rb").to_s }

  def run_script(draft_docs)
    output = IO.popen({ "DRAFT_DOCS_JSON" => draft_docs.to_json }, [RbConfig.ruby, script_path], &:read)
    JSON.parse(output)
  end

  it "outputs passing validation results when no draft OpenAPI file is present" do
    parsed = run_script("draft_docs" => { "files" => [{ "path" => "docs/api.md", "content" => "# API" }] })

    expect(parsed).to eq("validation_results" => { "valid" => true, "errors" => [] })
  end

  it "validates parseable draft OpenAPI YAML content" do
    parsed = run_script(
      "draft_docs" => {
        "format" => "openapi_yaml",
        "files" => [{ "path" => "docs/openapi.yml", "content" => "openapi: 3.1.0\ninfo:\n  title: Widget API\n" }]
      }
    )

    expect(parsed.dig("validation_results", "valid")).to eq(true)
    expect(parsed.dig("validation_results", "errors")).to eq([])
  end

  it "reports invalid validation results when draft OpenAPI YAML cannot parse" do
    parsed = run_script(
      "draft_docs" => {
        "files" => [{ "path" => "docs/openapi.yml", "content" => "openapi: [unterminated" }]
      }
    )

    expect(parsed.dig("validation_results", "valid")).to eq(false)
    expect(parsed.dig("validation_results", "errors").first).to include("docs/openapi.yml")
  end
end
