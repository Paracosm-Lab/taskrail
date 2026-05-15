require "rails_helper"

RSpec.describe Claim, type: :model do
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to have_many(:reports).dependent(:destroy) }
  it { is_expected.to have_many(:artifacts).dependent(:destroy) }
  it { is_expected.to have_one(:trace).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:agent_type) }
  it { is_expected.to define_enum_for(:status).backed_by_column_of_type(:integer).with_values(active: 0, completed: 1, failed: 2, timed_out: 3) }

  describe "heartbeat_stale?" do
    it "is false for a fresh async heartbeat" do
      claim = new_claim(status: :active, async_execution: true, last_heartbeat_at: 1.minute.ago)

      expect(claim.heartbeat_stale?).to eq(false)
    end

    it "is true for an old active async heartbeat" do
      claim = new_claim(status: :active, async_execution: true, last_heartbeat_at: 121.seconds.ago)

      expect(claim.heartbeat_stale?).to eq(true)
    end

    it "is false for sync, missing, and inactive heartbeats" do
      expect(new_claim(status: :active, async_execution: false, last_heartbeat_at: 10.minutes.ago).heartbeat_stale?).to eq(false)
      expect(new_claim(status: :active, async_execution: true, last_heartbeat_at: nil).heartbeat_stale?).to eq(false)
      expect(new_claim(status: :completed, async_execution: true, last_heartbeat_at: 10.minutes.ago).heartbeat_stale?).to eq(false)
    end
  end

  def new_claim(attributes)
    described_class.new(attributes.merge(agent_type: "codex"))
  end
end
