require "rails_helper"

RSpec.describe ClaudeAssignmentPrompt do
  it "includes work item, stage, prompt, completion criteria, and context" do
    assignment = {
      claim_id: 123,
      work_item: { id: 7, title: "Add billing", spec_url: "./spec.md", tags: ["backend"] },
      stage: {
        name: "intake",
        allowed_skills: ["read_spec"],
        forbidden_skills: ["deploy"],
        completion_criteria: ["report_present"]
      },
      prompt: "Classify the work item.",
      context: {
        spec_content: "Build the thing",
        upstream_reports: [{ "summary" => "prior" }],
        upstream_artifacts: []
      },
      limits: { timeout_seconds: 600, max_tokens: nil, max_cost_cents: nil }
    }

    prompt = described_class.new(assignment).to_s

    expect(prompt).to include("Add billing")
    expect(prompt).to include("intake")
    expect(prompt).to include("Classify the work item")
    expect(prompt).to include("report_present")
    expect(prompt).to include("Build the thing")
    expect(prompt).to include("Do not decide the workflow transition")
  end
end
