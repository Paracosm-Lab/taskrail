require_relative "boot"
require "rails/all"

module VulnerableSecurityApp
  class Application < Rails::Application
    config.load_defaults 8.0
    config.force_ssl = false
  end
end
