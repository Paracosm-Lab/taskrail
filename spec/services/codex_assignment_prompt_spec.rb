require "rails_helper"

RSpec.describe CodexAssignmentPrompt do
  it "includes build context, feedback, criteria, and safety boundaries" do
    assignment = {
      claim_id: 123,
      work_item: {
        id: 7,
        title: "Implement billing export",
        spec_url: "./spec.md",
        stage_name: "build",
        tags: ["backend"],
        metadata: { "feedback" => "Fix the CSV headers" }
      },
      stage: {
        name: "build",
        allowed_skills: ["test-driven-development"],
        forbidden_skills: ["deploy"],
        completion_criteria: ["branch_created"]
      },
      prompt: "Implement the assigned build slice.",
      context: {
        spec_content: "Export invoices as CSV",
        upstream_reports: [{ "summary" => "intake accepted" }],
        upstream_artifacts: []
      }
    }

    prompt = described_class.new(assignment).to_s

    expect(prompt).to include("Implement billing export")
    expect(prompt).to include("./spec.md")
    expect(prompt).to include("backend")
    expect(prompt).to include("build")
    expect(prompt).to include("Implement the assigned build slice")
    expect(prompt).to include("test-driven-development")
    expect(prompt).to include("deploy")
    expect(prompt).to include("branch_created")
    expect(prompt).to include("Fix the CSV headers")
    expect(prompt).to include("Export invoices as CSV")
    expect(prompt).to include("create or modify code only for the assigned scope")
    expect(prompt).to include("produce branch and artifact evidence")
    expect(prompt).to include("do not merge, deploy, or mutate production data")
    expect(prompt).to include("do not decide the workflow transition")
  end
end
