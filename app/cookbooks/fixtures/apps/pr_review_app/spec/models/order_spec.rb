RSpec.describe Order do
  it "requires a name" do
    order = described_class.new(name: nil, total_cents: 100)
    expect(order).not_to be_valid
  end
end
