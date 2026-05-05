require "rails_helper"
require "yaml"

RSpec.describe "test coverage backfill cookbook" do
  it "keeps queue prompts and fixture paths portable under the cookbook tree" do
    queue = YAML.safe_load(Rails.root.join("config/queues/test_backfill.yml").read)
    prompt_paths = queue.fetch("stage_configs").values.filter_map do |config|
      prompt = config["agent_prompt"]
      prompt.delete_prefix("file://") if prompt.is_a?(String) && prompt.start_with?("file://")
    end

    expect(prompt_paths).to contain_exactly(
      "cookbooks/prompts/test_backfill/scan_coverage.md",
      "cookbooks/prompts/test_backfill/identify_gaps.md",
      "cookbooks/prompts/test_backfill/generate_tests.md"
    )
    prompt_paths.each do |relative_path|
      prompt_file = Rails.root.join(relative_path)
      expect(prompt_file).to exist
      expect(prompt_file.read).to include("# Backfill")
      expect(prompt_file.read).not_to include(Rails.root.to_s)
    end

    serialized_queue = Rails.root.join("config/queues/test_backfill.yml").read
    expect(serialized_queue).not_to include(Rails.root.to_s)
    expect(serialized_queue).not_to include("/Users/")
  end

  it "provides a deterministic untested app fixture for generated spec repair" do
    fixture_root = Rails.root.join("test/fixtures/apps/untested_app")

    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/models/widget.rb")).to exist
    expect(fixture_root.join("spec/models/widget_spec.rb")).to exist
    expect(fixture_root.join("README.md").read).to include("Widget#reorder_message")
    expect(fixture_root.join("app/models/widget.rb").read).to include("def reorder_message")
    expect(fixture_root.join("spec/models/widget_spec.rb").read).not_to include("reorder_message")
  end

  it "documents the cookbook source spec and verification workflow" do
    doc = Rails.root.join("docs/cookbooks/test-coverage-backfill.md")

    expect(doc).to exist
    content = doc.read
    expect(content).to include("docs/specs/cookbook-01-test-coverage-backfill.md")
    expect(content).to include("test_backfill")
    expect(content).to include("scan_coverage -> identify_gaps -> generate_tests -> run_tests -> human_review -> done")
    expect(content).not_to include(Rails.root.to_s)
  end
end
