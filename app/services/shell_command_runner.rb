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
    Open3.popen3(@command, chdir: @working_directory) do |stdin, stdout_io, stderr_io, wait_thread|
      stdin.close

      unless wait_thread.join(@timeout_seconds)
        terminate_process(wait_thread.pid)
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        return Result.new(
          stdout: stdout_io.read.to_s,
          stderr: [stderr_io.read, "timed out after #{@timeout_seconds} seconds"].reject(&:blank?).join("\n"),
          exit_status: 124,
          duration_ms: ((finished - started) * 1000).round
        )
      end

      finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Result.new(
        stdout: stdout_io.read,
        stderr: stderr_io.read,
        exit_status: wait_thread.value.exitstatus,
        duration_ms: ((finished - started) * 1000).round
      )
    end
  end

  private

  def terminate_process(pid)
    Process.kill("TERM", pid)
    sleep 0.1
    Process.kill("KILL", pid)
  rescue Errno::ESRCH
    nil
  end
end
