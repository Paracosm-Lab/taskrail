# Validates queue YAML configuration files without requiring the Rails environment.
# Used by the queues:validate Rake task and its spec.
class QueueConfigValidator
  REQUIRED_KEYS = %w[name slug stages stage_configs].freeze

  # Validate a single parsed queue config hash, identified by +label+ (e.g. the filename).
  # Returns an Array of error message strings (empty means valid).
  def self.validate(config, label: "queue")
    errors = []

    unless config.is_a?(Hash)
      return ["#{label}: file did not parse to a Hash"]
    end

    missing = REQUIRED_KEYS - config.keys
    unless missing.empty?
      errors << "#{label}: missing required keys: #{missing.join(', ')}"
    end

    stages = config["stages"]
    unless stages.is_a?(Array) && stages.all? { |s| s.is_a?(String) } && stages.any?
      errors << "#{label}: 'stages' must be a non-empty Array of Strings"
    end

    stage_configs = config["stage_configs"]
    unless stage_configs.is_a?(Hash)
      errors << "#{label}: 'stage_configs' must be a Hash"
      # Can't validate stage_config entries without a valid Hash
      return errors
    end

    valid_stages = stages.is_a?(Array) ? stages : []

    stages_without_config = valid_stages - stage_configs.keys
    stages_without_config.each do |s|
      errors << "#{label}: stage '#{s}' is listed in 'stages' but has no entry in 'stage_configs'"
    end

    stage_configs.each do |stage_name, entry|
      unless valid_stages.include?(stage_name)
        errors << "#{label}: stage_configs key '#{stage_name}' is not listed in 'stages'"
      end

      adapter_type = entry.is_a?(Hash) ? entry["adapter_type"] : nil
      unless adapter_type.is_a?(String) && !adapter_type.strip.empty?
        errors << "#{label}: stage_configs['#{stage_name}'] is missing a non-blank string 'adapter_type'"
      end
    end

    errors
  end

  # Validate all *.yml files in +dir+.
  # Returns a Hash: { path => [error, ...] } for files with errors.
  # Files that cannot be loaded are recorded as errors too.
  def self.validate_dir(dir)
    results = {}
    files = Dir[File.join(dir, "*.yml")].sort

    files.each do |path|
      label = File.basename(path)
      begin
        config = YAML.safe_load_file(path)
        errs = validate(config, label: label)
        results[path] = errs unless errs.empty?
      rescue => e
        results[path] = ["#{label}: YAML parse error — #{e.message}"]
      end
    end

    results
  end
end
