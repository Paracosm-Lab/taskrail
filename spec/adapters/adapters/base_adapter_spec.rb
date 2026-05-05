require "rails_helper"

RSpec.describe Adapters::BaseAdapter do
  describe "#heartbeat" do
    it "updates heartbeat columns without validations or callbacks" do
      queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build done])
      work_item = WorkItem.create!(work_queue: queue, title: "Build", spec_url: "opaque", stage_name: "build")
      claim = Claim.create!(work_item: work_item, agent_type: "codex", status: :active)
      claim.agent_type = nil

      described_class.new.heartbeat(claim, "60% complete")

      claim.reload
      expect(claim.last_heartbeat_at).to be_present
      expect(claim.heartbeat_message).to eq("60% complete")
    end
  end
end
