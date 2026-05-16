require "open3"

class ShellCommandRunner
  Result = Data.define(:stdout, :stderr, :exit_status, :duration_ms)
  OUTPUT_LIMIT = 1.megabyte
  KILL_GRACE_SECONDS = 0.1

  def initialize(command:, working_directory: Rails.root.to_s, timeout_seconds: nil)
    @command = command
    @working_directory = working_directory
    @timeout_seconds = timeout_seconds
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    Open3.popen3(@command, chdir: @working_directory, pgroup: true) do |stdin, stdout_io, stderr_io, wait_thread|
      stdin.close
      stdout = +""
      stderr = +""
      stdout_reader = read_stream(stdout_io, stdout)
      stderr_reader = read_stream(stderr_io, stderr)

      unless wait_thread.join(@timeout_seconds)
        terminate_process_group(wait_thread.pid)
        wait_thread.join
        stdout_reader.join(1)
        stderr_reader.join(1)
        finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)

        return Result.new(
          stdout: stdout,
          stderr: [stderr, "timed out after #{@timeout_seconds} seconds"].reject(&:blank?).join("\n"),
          exit_status: 124,
          duration_ms: ((finished - started) * 1000).round
        )
      end

      stdout_reader.join
      stderr_reader.join
      finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Result.new(
        stdout: stdout,
        stderr: stderr,
        exit_status: wait_thread.value.exitstatus,
        duration_ms: ((finished - started) * 1000).round
      )
    end
  end

  private

  def read_stream(io, buffer)
    Thread.new do
      loop do
        chunk = io.readpartial(16.kilobytes)
        remaining = OUTPUT_LIMIT - buffer.bytesize
        next if remaining <= 0

        buffer << chunk.byteslice(0, remaining)
      end
    rescue EOFError, IOError
      nil
    end
  end

  def terminate_process_group(pid)
    Process.kill("TERM", -pid)
    sleep KILL_GRACE_SECONDS
    Process.kill("KILL", -pid)
  rescue Errno::ESRCH
    nil
  end
end
