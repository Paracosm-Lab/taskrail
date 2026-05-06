require "rails_helper"

RSpec.describe Engine::PipeConditionEvaluator do
  def evaluator(data, conditions)
    described_class.new(artifact_data: data, conditions: conditions)
  end

  describe "includes operator" do
    it "passes when a flat field value is in the list" do
      data = { "grade" => "D" }
      conditions = [{ "field" => "grade", "operator" => "includes", "value" => ["D", "F"] }]
      expect(evaluator(data, conditions).passes?).to be true
    end

    it "fails when flat field value is not in the list" do
      data = { "grade" => "A" }
      conditions = [{ "field" => "grade", "operator" => "includes", "value" => ["D", "F"] }]
      expect(evaluator(data, conditions).passes?).to be false
    end

    it "passes when any array element matches" do
      data = { "findings" => [{ "severity" => "low" }, { "severity" => "critical" }] }
      conditions = [{ "field" => "findings[].severity", "operator" => "includes", "value" => ["critical", "high"] }]
      expect(evaluator(data, conditions).passes?).to be true
    end

    it "fails when no array element matches" do
      data = { "findings" => [{ "severity" => "low" }, { "severity" => "medium" }] }
      conditions = [{ "field" => "findings[].severity", "operator" => "includes", "value" => ["critical", "high"] }]
      expect(evaluator(data, conditions).passes?).to be false
    end
  end

  describe "equals operator" do
    it "passes when field matches exactly" do
      data = { "status" => "complete" }
      conditions = [{ "field" => "status", "operator" => "equals", "value" => "complete" }]
      expect(evaluator(data, conditions).passes?).to be true
    end

    it "fails when field does not match" do
      data = { "status" => "pending" }
      conditions = [{ "field" => "status", "operator" => "equals", "value" => "complete" }]
      expect(evaluator(data, conditions).passes?).to be false
    end
  end

  describe "exists operator" do
    it "passes when field is present and non-nil" do
      data = { "gaps" => [{ "missing_runbook" => true }] }
      conditions = [{ "field" => "gaps[].missing_runbook", "operator" => "exists" }]
      expect(evaluator(data, conditions).passes?).to be true
    end

    it "fails when array is empty" do
      data = { "gaps" => [] }
      conditions = [{ "field" => "gaps[].missing_runbook", "operator" => "exists" }]
      expect(evaluator(data, conditions).passes?).to be false
    end
  end

  describe "nested field paths" do
    it "resolves dot-separated keys" do
      data = { "meta" => { "source" => { "type" => "sentry" } } }
      conditions = [{ "field" => "meta.source.type", "operator" => "equals", "value" => "sentry" }]
      expect(evaluator(data, conditions).passes?).to be true
    end
  end

  describe "multiple conditions" do
    it "requires all conditions to pass (AND logic)" do
      data = { "grade" => "D", "count" => 5 }
      conditions = [
        { "field" => "grade", "operator" => "includes", "value" => ["D", "F"] },
        { "field" => "count", "operator" => "equals", "value" => 99 }
      ]
      expect(evaluator(data, conditions).passes?).to be false
    end
  end

  it "passes with no conditions" do
    expect(evaluator({}, []).passes?).to be true
  end
end
