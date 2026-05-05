require "rails_helper"

RSpec.describe Trace, type: :model do
  it { is_expected.to belong_to(:claim) }
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to have_many(:trace_events).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:stage_name) }
  it { is_expected.to validate_presence_of(:agent_type) }
end
