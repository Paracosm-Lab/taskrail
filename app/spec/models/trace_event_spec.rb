require "rails_helper"

RSpec.describe TraceEvent, type: :model do
  it { is_expected.to belong_to(:trace) }
  it { is_expected.to validate_presence_of(:sequence) }
  it { is_expected.to validate_presence_of(:event_type) }
end
