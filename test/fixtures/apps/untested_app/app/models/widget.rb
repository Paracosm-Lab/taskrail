class Widget
  attr_reader :name, :quantity

  def initialize(name:, quantity:)
    @name = name
    @quantity = quantity
  end

  def valid?
    name.to_s.strip != "" && quantity.to_i.positive?
  end

  def reorder_message(threshold: 10)
    return "invalid widget" unless valid?
    return "reorder #{name}" if quantity < threshold

    "stock ok"
  end
end
