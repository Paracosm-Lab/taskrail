require "rails_helper"

RSpec.describe Engine::PredicateResult do
  it "represents passing predicate evidence" do
    result = described_class.pass(evidence: { artifact_id: "123" })

    expect(result).to be_passed
    expect(result.reason).to be_nil
    expect(result.evidence).to eq(artifact_id: "123")
  end

  it "represents failing predicate reason" do
    result = described_class.fail(reason: "missing test_results artifact")

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing test_results artifact")
    expect(result.evidence).to eq({})
  end
end
