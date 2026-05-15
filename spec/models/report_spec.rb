require "rails_helper"

RSpec.describe Report, type: :model do
  it { is_expected.to belong_to(:claim) }
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to validate_presence_of(:stage_name) }
  it { is_expected.to define_enum_for(:status).backed_by_column_of_type(:integer).with_values(success: 0, failure: 1, blocked: 2) }
end
