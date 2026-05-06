require_relative "../../app/models/order"

RSpec.describe Order do
  it "marks positive totals payable" do
    expect(Order.new(total_cents: 1200)).to be_payable
  end
end
