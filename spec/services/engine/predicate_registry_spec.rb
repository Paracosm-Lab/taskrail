require "rails_helper"

RSpec.describe Engine::PredicateRegistry do
  it "resolves known predicate names" do
    expect(described_class.resolve("tests_passed")).to eq(Engine::Predicates::TestsPassed)
    expect(described_class.resolve("review_verdict")).to eq(Engine::Predicates::ReviewVerdict)
    expect(described_class.resolve("clusters_created")).to eq(Engine::Predicates::ClustersCreated)
    expect(described_class.resolve("assessment_complete")).to eq(Engine::Predicates::AssessmentComplete)
    expect(described_class.resolve("runbook_mapped")).to eq(Engine::Predicates::RunbookMapped)
    expect(described_class.resolve("runbook_drafted")).to eq(Engine::Predicates::RunbookDrafted)
    expect(described_class.resolve("validation_passed")).to eq(Engine::Predicates::ValidationPassed)
    expect(described_class.resolve("query_inventory_produced")).to eq(Engine::Predicates::QueryInventoryProduced)
    expect(described_class.resolve("query_analyzed")).to eq(Engine::Predicates::QueryAnalyzed)
    expect(described_class.resolve("query_fixes_drafted")).to eq(Engine::Predicates::QueryFixesDrafted)
  end

  it "raises for unknown predicate names" do
    expect { described_class.resolve("teleport_completed") }.to raise_error(Engine::PredicateRegistry::UnknownPredicate)
  end
end
