resolve_prompt = lambda do |prompt|
  next prompt unless prompt.is_a?(String) && prompt.start_with?("file://")

  prompt_path = prompt.delete_prefix("file://")
  Rails.root.join(prompt_path).read
end

Rails.root.glob("config/queues/*.yml").sort.each do |queue_path|
  queue_config = YAML.load_file(queue_path)

  queue = WorkQueue.find_or_initialize_by(slug: queue_config.fetch("slug"))
  queue.update!(
    name: queue_config.fetch("name"),
    stages: queue_config.fetch("stages"),
    config: queue_config.fetch("config", {})
  )

  queue_config.fetch("stage_configs").each do |stage_name, config|
    stage_config = queue.stage_configs.find_or_initialize_by(stage_name: stage_name)
    stage_config.update!(
      allowed_skills: config.fetch("allowed_skills", []),
      forbidden_skills: config.fetch("forbidden_skills", []),
      max_retries: config["max_retries"],
      escalation_target: config["escalation_target"],
      completion_criteria: config.fetch("completion_criteria", []),
      agent_prompt: resolve_prompt.call(config["agent_prompt"]),
      model_override: config["model_override"],
      timeout_seconds: config["timeout_seconds"],
      adapter_type: config.fetch("adapter_type", "fake"),
      adapter_config: config.fetch("adapter_config", {})
    )
  end
end
