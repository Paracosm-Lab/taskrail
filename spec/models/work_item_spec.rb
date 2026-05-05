require "rails_helper"

RSpec.describe WorkItem, type: :model do
  it { is_expected.to belong_to(:work_queue) }
  it { is_expected.to belong_to(:parent).class_name("WorkItem").optional }
  it { is_expected.to have_many(:children).class_name("WorkItem").with_foreign_key(:parent_id).dependent(:nullify) }
  it { is_expected.to have_many(:claims).dependent(:destroy) }
  it { is_expected.to have_many(:reports).dependent(:destroy) }
  it { is_expected.to have_many(:artifacts).dependent(:destroy) }
  it { is_expected.to have_many(:traces).dependent(:destroy) }
  it { is_expected.to have_many(:transition_logs).dependent(:destroy) }
  it { is_expected.to validate_presence_of(:title) }
  it { is_expected.to validate_presence_of(:spec_url) }
  it { is_expected.to validate_presence_of(:stage_name) }
  it { is_expected.to define_enum_for(:status).backed_by_column_of_type(:integer).with_values(pending: 0, claimed: 1, blocked: 2, waiting: 3, completed: 4, cancelled: 5) }
end
