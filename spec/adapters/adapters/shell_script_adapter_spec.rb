require "rails_helper"
require "tmpdir"

RSpec.describe Adapters::ShellScriptAdapter do
  around do |example|
    original = ENV["TASKRAIL_WORKSPACE_ROOT"]
    ENV["TASKRAIL_WORKSPACE_ROOT"] = Rails.root.to_s
    example.run
  ensure
    ENV["TASKRAIL_WORKSPACE_ROOT"] = original
  end

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

  it "captures multiple command outputs in sequence" do
    result = described_class.new.execute(
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "one", "command" => "ruby -e 'puts 1'" },
            { "name" => "two", "command" => "ruby -e 'puts 2'" },
            { "name" => "three", "command" => "ruby -e 'puts 3'" }
          ]
        }
      }
    )

    commands = result.artifacts.find { |artifact| artifact["kind"] == "test_results" }.dig("data", "commands")
    expect(commands.map { |command| command["name"] }).to eq(%w[one two three])
    expect(commands.map { |command| command["stdout"].strip }).to eq(%w[1 2 3])
  end

  it "returns failure when a command times out" do
    result = described_class.new.execute(
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [{ "name" => "slow", "command" => "ruby -e 'sleep 2'" }]
        }
      },
      limits: { timeout_seconds: 1 }
    )

    expect(result.status).to eq("failure")
    expect(result.report.dig("commands", 0, "stderr")).to include("timed out")
  end

  it "allows configured working directories inside the sandbox root" do
    Dir.mktmpdir("taskrail-workspaces") do |root|
      job_dir = File.join(root, "job-123")
      Dir.mkdir(job_dir)
      original = ENV["TASKRAIL_WORKSPACE_ROOT"]
      ENV["TASKRAIL_WORKSPACE_ROOT"] = root

      result = described_class.new.execute(
        stage: {
          name: "test",
          adapter_config: {
            "working_directory" => job_dir,
            "commands" => [{ "name" => "pwd", "command" => "ruby -e 'exit 0'" }]
          }
        }
      )

      expect(result.status).to eq("success")
    ensure
      ENV["TASKRAIL_WORKSPACE_ROOT"] = original
    end
  end

  it "rejects configured working directories outside the sandbox root" do
    Dir.mktmpdir("taskrail-workspaces") do |root|
      original = ENV["TASKRAIL_WORKSPACE_ROOT"]
      ENV["TASKRAIL_WORKSPACE_ROOT"] = root

      expect do
        described_class.new.execute(
          stage: {
            name: "test",
            adapter_config: {
              "working_directory" => "/etc",
              "commands" => [{ "name" => "pwd", "command" => "ruby -e 'exit 0'" }]
            }
          }
        )
      end.to raise_error(SecurityError)
    ensure
      ENV["TASKRAIL_WORKSPACE_ROOT"] = original
    end
  end

  it "rejects symlink escapes from the sandbox root" do
    Dir.mktmpdir("taskrail-workspaces") do |root|
      link = File.join(root, "escape")
      File.symlink("/etc", link)
      original = ENV["TASKRAIL_WORKSPACE_ROOT"]
      ENV["TASKRAIL_WORKSPACE_ROOT"] = root

      expect do
        described_class.new.execute(
          stage: {
            name: "test",
            adapter_config: {
              "working_directory" => link,
              "commands" => [{ "name" => "pwd", "command" => "ruby -e 'exit 0'" }]
            }
          }
        )
      end.to raise_error(SecurityError)
    ensure
      ENV["TASKRAIL_WORKSPACE_ROOT"] = original
    end
  end

  it "redacts bearer secrets from command trace input summaries" do
    assignment = {
      stage: {
        name: "test",
        adapter_config: {
          "working_directory" => Rails.root.to_s,
          "commands" => [
            { "name" => "curl", "command" => "ruby -e 'exit 0' # Authorization: Bearer sk-12345" }
          ]
        }
      }
    }

    result = described_class.new.execute(assignment)

    expect(result.trace_events.first.fetch("input_summary")).to include("Bearer [REDACTED]")
    expect(result.trace_events.first.fetch("input_summary")).not_to include("sk-12345")
  end
end
