class Order
  attr_reader :total_cents

  def initialize(total_cents:)
    @total_cents = total_cents
  end

  def payable?
    total_cents.positive?
  end
end
