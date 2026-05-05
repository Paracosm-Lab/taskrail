require "json"

class CodexAssignmentPrompt
  def initialize(assignment)
    @assignment = assignment.deep_stringify_keys
  end

  def to_s
    <<~PROMPT
      You are executing one StupidClaw build/fix workflow stage with Codex.

      Important boundaries:
      - create or modify code only for the assigned scope.
      - produce branch and artifact evidence for StupidClaw to inspect.
      - do not merge, deploy, or mutate production data.
      - do not decide the workflow transition.
      - StupidClaw will persist your evidence and apply queue-owned transition rules.

      Stage: #{stage.fetch("name")}
      Work item: #{JSON.pretty_generate(work_item)}
      Stage prompt: #{assignment["prompt"]}
      Allowed skills: #{stage.fetch("allowed_skills", []).join(", ")}
      Forbidden skills: #{stage.fetch("forbidden_skills", []).join(", ")}
      Completion criteria: #{stage.fetch("completion_criteria", []).join(", ")}
      Feedback: #{feedback}

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

  def feedback
    work_item.fetch("metadata", {}).fetch("feedback", "none")
  end
end
