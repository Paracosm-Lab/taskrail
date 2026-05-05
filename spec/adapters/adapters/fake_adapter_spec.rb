require "rails_helper"

RSpec.describe Adapters::FakeAdapter do
  it "returns intake success with classification report" do
    assignment = { stage: { name: "intake" }, work_item: { title: "Add calendar" } }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.report["summary"]).to include("classified")
    expect(result.report["tags"]).to include("risk" => "low")
    expect(result.trace_events.first["event_type"]).to eq("decision")
  end

  it "returns child definitions for decompose stage" do
    assignment = { stage: { name: "decompose" }, work_item: { title: "Add calendar", spec_url: "spec.md" } }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.report["children"].first).to include("title", "spec_url", "tags")
  end

  it "returns build artifacts for build stage" do
    assignment = { stage: { name: "build" }, work_item: { id: "123", title: "Add calendar" } }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.artifacts.map { |a| a["kind"] }).to include("branch")
  end

  it "returns validation artifacts for test stage" do
    assignment = { stage: { name: "test" }, work_item: { id: "123", title: "Add calendar" } }

    result = described_class.new.execute(assignment)

    expect(result.artifacts).to include({ "kind" => "test_results", "data" => { "passed" => true } })
    expect(result.artifacts).to include({ "kind" => "lint", "data" => { "clean" => true } })
    expect(result.artifacts).to include({ "kind" => "coverage", "data" => { "current" => 95.0, "previous" => 94.0 } })
  end

  it "returns approved verdict for review stage" do
    assignment = { stage: { name: "review" }, work_item: { id: "123", title: "Add calendar" } }

    result = described_class.new.execute(assignment)

    expect(result.status).to eq("success")
    expect(result.report["verdict"]).to eq("approved")
  end
end
