require "rails_helper"

RSpec.describe Claim, type: :model do
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to have_many(:reports).dependent(:destroy) }
  it { is_expected.to have_many(:artifacts).dependent(:destroy) }
  it { is_expected.to have_one(:trace).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:agent_type) }
  it { is_expected.to define_enum_for(:status).backed_by_column_of_type(:integer).with_values(active: 0, completed: 1, failed: 2, timed_out: 3) }
end
