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

  it "terminates child processes when a command times out" do
    marker = Rails.root.join("tmp", "shell-runner-child-#{SecureRandom.hex(4)}.pid")
    command = <<~SH.squish
      ruby -e 'pid = spawn("sleep", "30"); File.write("#{marker}", pid); sleep 30'
    SH

    result = described_class.new(command: command, working_directory: Rails.root.to_s, timeout_seconds: 1).call
    child_pid = marker.read.to_i

    expect(result.exit_status).to eq(124)
    expect(result.stderr).to include("timed out after 1 seconds")
    expect(process_alive?(child_pid)).to eq(false)
  ensure
    FileUtils.rm_f(marker) if marker
  end

  it "bounds captured output" do
    result = described_class.new(command: "ruby -e 'print \"x\" * (2 * 1024 * 1024)'", working_directory: Rails.root.to_s).call

    expect(result.stdout.bytesize).to eq(described_class::OUTPUT_LIMIT)
  end

  def process_alive?(pid)
    Process.kill(0, pid)
    true
  rescue Errno::ESRCH
    false
  end
end
