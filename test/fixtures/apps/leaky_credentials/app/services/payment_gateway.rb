require "yaml"

class PaymentGateway
  CONFIG = YAML.load_file(File.expand_path("../../config/payment.yml", __dir__)).fetch("production")

  def self.charge(cents)
    key = CONFIG.fetch("stripe_secret_key")
    "charged #{cents} with #{key[0, 7]}"
  end
end
