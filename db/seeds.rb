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

Rails.root.glob("config/pipes/*.yml").sort.each do |pipe_path|
  next if File.basename(pipe_path) == ".gitkeep"

  pipe_config = YAML.safe_load(File.read(pipe_path))

  from_slug = pipe_config.dig("from", "queue")
  to_slug = pipe_config.dig("to", "queue")

  from_queue = WorkQueue.find_by(slug: from_slug) or
    raise "Pipe #{pipe_path}: from.queue '#{from_slug}' not found — seed queues first"
  to_queue = WorkQueue.find_by(slug: to_slug) or
    raise "Pipe #{pipe_path}: to.queue '#{to_slug}' not found — seed queues first"

  pipe = Pipe.find_or_initialize_by(slug: pipe_config.fetch("slug"))
  pipe.assign_attributes(
    name: pipe_config.fetch("name"),
    from_queue: from_queue,
    from_stage: pipe_config.dig("from", "stage"),
    to_queue: to_queue,
    to_stage: pipe_config.dig("to", "stage"),
    when_config: pipe_config.fetch("when", {}),
    transform_config: pipe_config.fetch("transform", {}),
    limits: pipe_config.fetch("limits", {}),
    enabled: pipe_config.fetch("enabled", true)
  )

  unless pipe.valid?
    raise "Pipe #{pipe_path} is invalid: #{pipe.errors.full_messages.join(", ")}"
  end

  pipe.save!
  puts "  pipe: #{pipe.slug} (#{pipe.persisted? ? "updated" : "created"})"
end
