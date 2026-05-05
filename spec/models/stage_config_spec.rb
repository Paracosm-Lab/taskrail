require "rails_helper"

RSpec.describe StageConfig, type: :model do
  subject { described_class.new(work_queue: WorkQueue.new(name: "Development", slug: "development"), stage_name: "intake", adapter_type: "fake") }

  it { is_expected.to belong_to(:work_queue) }
  it { is_expected.to validate_presence_of(:stage_name) }
  it { is_expected.to validate_presence_of(:adapter_type) }
  it { is_expected.to validate_uniqueness_of(:stage_name).scoped_to(:work_queue_id) }
end
