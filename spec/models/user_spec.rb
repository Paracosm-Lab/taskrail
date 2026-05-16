require "rails_helper"

RSpec.describe User, type: :model do
  it "normalizes email addresses" do
    user = described_class.create!(email: " ADMIN@Example.COM ", password: "password123")

    expect(user.email).to eq("admin@example.com")
  end

  it "requires case-insensitive unique email addresses" do
    described_class.create!(email: "admin@example.com", password: "password123")

    duplicate = described_class.new(email: "ADMIN@example.com", password: "password123")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:email]).to be_present
  end
end
