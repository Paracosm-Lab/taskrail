class PaymentProviderSwitch
  def initialize(provider: ENV.fetch("PAYMENT_PROVIDER", "legacy"))
    @provider = provider
  end

  def enabled?
    @provider == "next"
  end
end
