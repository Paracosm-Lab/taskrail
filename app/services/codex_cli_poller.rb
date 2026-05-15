require "json"
require "open3"
require "timeout"

class CodexCliPoller
  TIMEOUT_EXIT_STATUS = 124

  Result = Data.define(:status, :stdout, :stderr, :exit_status, :duration_ms, :metadata)

  def initialize(command:, args: [], external_id:, working_directory: Rails.root.to_s, timeout_seconds: nil)
    @command = command
    @args = args
    @external_id = external_id
    @working_directory = working_directory
    @timeout_seconds = timeout_seconds
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    raw_stdout, raw_stderr, process_exit_status = capture_process
    finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parsed = parse_stdout(raw_stdout)

    Result.new(
      status: result_status(parsed, process_exit_status),
      stdout: parsed.fetch("stdout", raw_stdout),
      stderr: parsed.fetch("stderr", raw_stderr),
      exit_status: parsed.fetch("exit_status", process_exit_status),
      duration_ms: ((finished - started) * 1000).round,
      metadata: parsed
    )
  end

  private

  def capture_process
    Open3.popen3(@command, *@args, @external_id, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
      stdin.close

      stdout_reader = Thread.new { stdout.read }
      stderr_reader = Thread.new { stderr.read }

      begin
        status = if @timeout_seconds
          Timeout.timeout(@timeout_seconds) { wait_thread.value }
        else
          wait_thread.value
        end
        [stdout_reader.value, stderr_reader.value, status.exitstatus]
      rescue Timeout::Error
        terminate_process(wait_thread.pid)
        [stdout_reader.value, [stderr_reader.value, "command timed out after #{@timeout_seconds} seconds"].reject(&:blank?).join("\n"), TIMEOUT_EXIT_STATUS]
      end
    end
  end

  def terminate_process(pid)
    Process.kill("TERM", pid)
    Timeout.timeout(1) { Process.wait(pid) }
  rescue Timeout::Error
    Process.kill("KILL", pid)
    Process.wait(pid)
  rescue Errno::ESRCH, Errno::ECHILD
    nil
  end

  def parse_stdout(stdout)
    JSON.parse(stdout)
  rescue JSON::ParserError, TypeError
    {}
  end

  def result_status(parsed, process_exit_status)
    return "failed" unless process_exit_status.zero?

    parsed.fetch("status", "running")
  end
end
