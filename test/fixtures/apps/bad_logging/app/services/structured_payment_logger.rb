class StructuredPaymentLogger
  def self.payment_authorized(payment_id:, user_id:, request_id:)
    Rails.logger.info(
      {
        event: "payment_authorized",
        operation: "StructuredPaymentLogger.payment_authorized",
        payment_id: payment_id,
        user_id: user_id,
        request_id: request_id
      }.to_json
    )
  end
end
