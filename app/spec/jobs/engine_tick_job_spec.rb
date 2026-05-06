require "rails_helper"

RSpec.describe EngineTickJob, type: :job do
  it "runs one engine tick" do
    runner = instance_double(Engine::Runner)
    allow(Engine::Runner).to receive(:new).and_return(runner)
    allow(runner).to receive(:call)

    described_class.perform_now

    expect(runner).to have_received(:call)
  end
end
