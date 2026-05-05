development_queue_path = Rails.root.join("config/queues/development.yml")
development_queue = YAML.load_file(development_queue_path)

queue = WorkQueue.find_or_initialize_by(slug: development_queue.fetch("slug"))
queue.update!(
  name: development_queue.fetch("name"),
  stages: development_queue.fetch("stages"),
  config: development_queue.fetch("config", {})
)

development_queue.fetch("stage_configs").each do |stage_name, config|
  stage_config = queue.stage_configs.find_or_initialize_by(stage_name: stage_name)
  stage_config.update!(
    allowed_skills: config.fetch("allowed_skills", []),
    forbidden_skills: config.fetch("forbidden_skills", []),
    max_retries: config["max_retries"],
    escalation_target: config["escalation_target"],
    completion_criteria: config.fetch("completion_criteria", []),
    agent_prompt: config["agent_prompt"],
    model_override: config["model_override"],
    timeout_seconds: config["timeout_seconds"],
    adapter_type: config.fetch("adapter_type", "fake")
  )
end
