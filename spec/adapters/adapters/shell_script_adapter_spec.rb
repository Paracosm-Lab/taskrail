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
end
