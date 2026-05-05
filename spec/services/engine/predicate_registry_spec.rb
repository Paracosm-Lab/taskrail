require "rails_helper"

RSpec.describe Engine::PredicateRegistry do
  it "resolves known predicate names" do
    expect(described_class.resolve("tests_passed")).to eq(Engine::Predicates::TestsPassed)
    expect(described_class.resolve("review_verdict")).to eq(Engine::Predicates::ReviewVerdict)
  end

  it "raises for unknown predicate names" do
    expect { described_class.resolve("teleport_completed") }.to raise_error(Engine::PredicateRegistry::UnknownPredicate)
  end
end
