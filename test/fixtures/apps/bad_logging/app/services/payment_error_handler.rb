class PaymentErrorHandler
  def self.handle(error)
    Rails.logger.error error.message
    false
  end
end
