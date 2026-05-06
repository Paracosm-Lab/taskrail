module Adapters
  class DockerComposeAdapter < BaseAdapter
    DEFAULT_WORKING_DIRECTORY = Rails.root.to_s
    DEFAULT_COMPOSE_FILE = "docker-compose.yml"
    HEARTBEAT_INTERVAL = 30.seconds

    def execute(assignment)
      normalized_assignment = assignment.deep_stringify_keys
      claim = Claim.find(normalized_assignment.fetch("claim_id"))
      config = normalized_assignment.fetch("stage").fetch("adapter_config", {})
      compose_file = config.fetch("compose_file", DEFAULT_COMPOSE_FILE)
      working_directory = config.fetch("working_directory", DEFAULT_WORKING_DIRECTORY)
      pid = Process.spawn("docker", "compose", "-f", compose_file, "up", "--abort-on-container-exit", chdir: working_directory)
      Process.detach(pid)

      heartbeat(claim, "pid #{pid} spawned")
      start_heartbeat_thread(claim.id, pid)

      Engine::AsyncAdapterResult.new(
        provider: "docker_compose",
        external_id: pid.to_s,
        status: "running",
        metadata: {
          "pid" => pid,
          "compose_file" => compose_file,
          "working_directory" => working_directory
        },
        trace_events: [{
          "event_type" => "docker_compose_spawn",
          "input_summary" => "docker compose -f #{compose_file} up --abort-on-container-exit",
          "output_summary" => "spawned pid #{pid}",
          "duration_ms" => 0,
          "tokens_in" => 0,
          "tokens_out" => 0,
          "cost_cents" => 0,
          "metadata" => { "pid" => pid, "compose_file" => compose_file }
        }]
      )
    end

    def process_running?(pid)
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    private

    def start_heartbeat_thread(claim_id, pid)
      Thread.new do
        while process_running?(pid)
          sleep HEARTBEAT_INTERVAL
          claim = Claim.find_by(id: claim_id)
          break unless claim&.active?

          heartbeat(claim, "pid #{pid} running")
        end
      end
    end
  end
end
