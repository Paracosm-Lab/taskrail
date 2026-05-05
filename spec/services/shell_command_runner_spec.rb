require "rails_helper"

RSpec.describe ShellCommandRunner do
  it "captures stdout, stderr, exit status, and duration" do
    result = described_class.new(command: "ruby -e 'puts 123'", working_directory: Rails.root.to_s).call

    expect(result.stdout).to include("123")
    expect(result.stderr).to eq("")
    expect(result.exit_status).to eq(0)
    expect(result.duration_ms).to be >= 0
  end

  it "captures failures without raising" do
    result = described_class.new(command: "ruby -e 'warn 456; exit 7'", working_directory: Rails.root.to_s).call

    expect(result.stderr).to include("456")
    expect(result.exit_status).to eq(7)
  end
end
