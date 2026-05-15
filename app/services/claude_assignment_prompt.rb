require "json"

class ClaudeAssignmentPrompt
  def initialize(assignment)
    @assignment = assignment.deep_stringify_keys
  end

  def to_s
    <<~PROMPT
      You are executing one TaskRail workflow stage.

      Important boundary:
      - Do not decide the workflow transition.
      - Produce the best report/evidence for the assigned stage.
      - TaskRail will persist your report and apply queue-owned transition rules.

      Stage: #{stage.fetch("name")}
      Work item: #{JSON.pretty_generate(work_item)}
      Stage prompt: #{assignment["prompt"]}
      Allowed skills: #{stage.fetch("allowed_skills", []).join(", ")}
      Forbidden skills: #{stage.fetch("forbidden_skills", []).join(", ")}
      Completion criteria: #{stage.fetch("completion_criteria", []).join(", ")}

      Context:
      #{JSON.pretty_generate(assignment.fetch("context", {}))}
    PROMPT
  end

  private

  attr_reader :assignment

  def work_item
    assignment.fetch("work_item")
  end

  def stage
    assignment.fetch("stage")
  end
end
