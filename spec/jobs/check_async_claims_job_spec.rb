require "rails_helper"

RSpec.describe CheckAsyncClaimsJob, type: :job do
  it "runs the async claim checker" do
    checker = instance_double(Engine::AsyncClaimChecker, call: nil)
    allow(Engine::AsyncClaimChecker).to receive(:new).and_return(checker)

    described_class.perform_now

    expect(checker).to have_received(:call)
  end
end
