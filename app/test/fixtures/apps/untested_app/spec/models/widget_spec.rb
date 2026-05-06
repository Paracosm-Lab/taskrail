require_relative "../../../app/models/widget"

RSpec.describe Widget do
  it "is valid with a name and positive quantity" do
    widget = described_class.new(name: "Sprocket", quantity: 5)

    expect(widget).to be_valid
  end
end
