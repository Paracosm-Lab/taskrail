require "rails_helper"

RSpec.describe Adapters::DockerComposeAdapter do
  it "spawns docker compose and starts heartbeat updates for the process" do
    queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build done])
    work_item = WorkItem.create!(work_queue: queue, title: "Build", spec_url: "opaque", stage_name: "build")
    claim = Claim.create!(work_item: work_item, agent_type: "docker_compose", status: :active)
    assignment = {
      claim_id: claim.id,
      stage: {
        adapter_config: {
          "compose_file" => "docker-compose.test.yml",
          "working_directory" => Rails.root.to_s
        }
      }
    }

    allow(Process).to receive(:spawn).and_return(12_345)
    allow(Process).to receive(:detach)
    allow_any_instance_of(described_class).to receive(:process_running?).and_return(false)

    result = described_class.new.execute(assignment)

    expect(Process).to have_received(:spawn).with("docker", "compose", "-f", "docker-compose.test.yml", "up", "--abort-on-container-exit", chdir: Rails.root.to_s)
    expect(Process).to have_received(:detach).with(12_345)
    expect(result).to be_a(Engine::AsyncAdapterResult)
    expect(result.provider).to eq("docker_compose")
    expect(result.external_id).to eq("12345")
    expect(claim.reload.last_heartbeat_at).to be_present
    expect(claim.heartbeat_message).to eq("pid 12345 spawned")
  end
end
