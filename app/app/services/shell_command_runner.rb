require "open3"

class ShellCommandRunner
  Result = Data.define(:stdout, :stderr, :exit_status, :duration_ms)

  def initialize(command:, working_directory: Rails.root.to_s, timeout_seconds: nil)
    @command = command
    @working_directory = working_directory
    @timeout_seconds = timeout_seconds
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, status = Open3.capture3(@command, chdir: @working_directory)
    finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    Result.new(
      stdout: stdout,
      stderr: stderr,
      exit_status: status.exitstatus,
      duration_ms: ((finished - started) * 1000).round
    )
  end
end
