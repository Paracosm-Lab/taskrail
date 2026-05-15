require "rails_helper"

RSpec.describe WorkQueue, type: :model do
  subject { described_class.new(name: "Development", slug: "development") }

  it { is_expected.to have_many(:stage_configs).dependent(:destroy) }
  it { is_expected.to have_many(:work_items).dependent(:restrict_with_exception) }
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:slug) }
  it { is_expected.to validate_uniqueness_of(:slug) }
end
