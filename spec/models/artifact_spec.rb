require "rails_helper"

RSpec.describe Artifact, type: :model do
  it { is_expected.to belong_to(:work_item) }
  it { is_expected.to belong_to(:claim).optional }
  it { is_expected.to validate_presence_of(:kind) }
end
