require "rails_helper"

RSpec.describe CheckAsyncClaimsJob, type: :job do
  it "no-ops when there are no active async claims" do
    expect { described_class.perform_now }.not_to raise_error
  end
end
