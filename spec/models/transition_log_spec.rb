require "rails_helper"

RSpec.describe TransitionLog, type: :model do
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to validate_presence_of(:trigger) }
end
