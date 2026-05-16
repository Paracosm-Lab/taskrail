require "yaml"
require_relative "../queue_config_validator"

namespace :queues do
  desc "Validate all config/queues/*.yml files for required structure"
  task :validate do
    dir = File.expand_path("../../config/queues", __dir__)
    errors_by_file = QueueConfigValidator.validate_dir(dir)

    if errors_by_file.any?
      errors_by_file.each do |path, errs|
        errs.each { |msg| warn msg }
      end
      exit 1
    else
      file_count = Dir[File.join(dir, "*.yml")].length
      puts "Validated #{file_count} queue files — all valid."
    end
  end
end
