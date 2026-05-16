require "json"
require "open3"
require "timeout"

class CodexCliSubmitter
  TIMEOUT_EXIT_STATUS = 124

  Result = Data.define(:stdout, :stderr, :exit_status, :duration_ms, :external_id, :metadata)

  def initialize(command:, args: [], prompt:, working_directory: Rails.root.to_s, timeout_seconds: nil)
    @command = command
    @args = args
    @prompt = prompt
    @working_directory = working_directory
    @timeout_seconds = timeout_seconds
  end

  def call
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    stdout, stderr, exit_status = capture_process
    finished = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    parsed = parse_stdout(stdout)

    Result.new(
      stdout: stdout,
      stderr: stderr,
      exit_status: exit_status,
      duration_ms: ((finished - started) * 1000).round,
      external_id: parsed["id"] || parsed["thread_id"],
      metadata: parsed
    )
  end

  private

  def capture_process
    Open3.popen3(@command, *@args, chdir: @working_directory) do |stdin, stdout, stderr, wait_thread|
      stdin.write(@prompt)
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
    parsed = JSON.parse(stdout)
    return parsed if parsed.is_a?(Hash)

    {}
  rescue JSON::ParserError, TypeError
    parse_jsonl_stdout(stdout)
  end

  def parse_jsonl_stdout(stdout)
    events = stdout.to_s.lines.filter_map do |line|
      JSON.parse(line)
    rescue JSON::ParserError
      nil
    end
    return {} if events.empty?

    thread_started = events.find { |event| event["type"] == "thread.started" }
    final_message = events.reverse.find { |event| event.dig("item", "type") == "agent_message" }
    turn_completed = events.reverse.find { |event| event["type"] == "turn.completed" }

    {
      "thread_id" => thread_started&.fetch("thread_id", nil),
      "status" => turn_completed ? "succeeded" : "running",
      "final_message" => final_message&.dig("item", "text"),
      "usage" => turn_completed&.fetch("usage", nil),
      "events" => events,
      "mode" => "jsonl"
    }.compact
  end
end
