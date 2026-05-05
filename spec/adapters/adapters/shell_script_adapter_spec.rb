require "rails_helper"

RSpec.describe Adapters::ShellScriptAdapter do
  it "returns success when all commands exit zero" do
    assignment = {
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "unit", "command" => "ruby -e 'puts 123'" }
          ]
        }
      }
    }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.report["summary"]).to include("1 command")
    expect(result.artifacts.map { |artifact| artifact["kind"] }).to include("test_results")
    expect(result.artifacts.find { |artifact| artifact["kind"] == "test_results" }["data"]["passed"]).to eq(true)
    expect(result.trace_events.first["event_type"]).to eq("shell_command")
  end

  it "returns failure when any command exits non-zero" do
    assignment = {
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "unit", "command" => "ruby -e 'warn 456; exit 2'" }
          ]
        }
      }
    }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("failure")
    expect(result.report["failed_commands"]).to include("unit")
    expect(result.artifacts.find { |artifact| artifact["kind"] == "test_results" }["data"]["passed"]).to eq(false)
  end

  it "maps configured commands to validation artifacts" do
    assignment = {
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "rspec", "command" => "ruby -e 'exit 0'", "artifact" => "test_results" },
            { "name" => "rubocop", "command" => "ruby -e 'exit 0'", "artifact" => "lint" },
            { "name" => "coverage", "command" => "ruby -e 'exit 0'", "artifact" => "coverage", "previous_coverage" => 90.0, "current_coverage" => 90.0 }
          ]
        }
      }
    }

    result = described_class.new.execute(assignment)

    expect(result.artifacts.find { |artifact| artifact["kind"] == "test_results" }["data"]["passed"]).to eq(true)
    expect(result.artifacts.find { |artifact| artifact["kind"] == "lint" }["data"]["clean"]).to eq(true)
    expect(result.artifacts.find { |artifact| artifact["kind"] == "coverage" }["data"]).to include("current" => 90.0, "previous" => 90.0)
  end

  it "includes unmapped commands in an aggregate test_results artifact" do
    assignment = {
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "setup", "command" => "ruby -e 'exit 0'" },
            { "name" => "rubocop", "command" => "ruby -e 'exit 0'", "artifact" => "lint" }
          ]
        }
      }
    }

    result = described_class.new.execute(assignment)
    test_results = result.artifacts.find { |artifact| artifact["kind"] == "test_results" }

    expect(test_results["data"]["passed"]).to eq(true)
    expect(test_results["data"]["commands"].map { |command| command["name"] }).to include("setup")
  end
end
