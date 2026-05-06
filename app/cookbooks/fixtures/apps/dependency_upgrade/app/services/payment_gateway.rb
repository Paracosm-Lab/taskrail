class PaymentGateway
  def initialize(client: nil)
    @client = client
  end

  def charge(order)
    return :skipped unless order.payable?

    :charged
  end
end
