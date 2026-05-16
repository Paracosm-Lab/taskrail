require "rails_helper"

RSpec.describe PersonalAccessToken, type: :model do
  it "generates a raw token once and stores only its digest" do
    user = create(:user)

    token, raw_token = described_class.generate!(user: user, name: "CLI", scopes: %w[read write])

    expect(raw_token).to start_with("trpat_")
    expect(token.token_digest).to eq(described_class.digest(raw_token))
    expect(token.token_digest).not_to include(raw_token)
    expect(token.token_prefix).to eq(raw_token.first(12))
  end

  it "authenticates active tokens" do
    user = create(:user)
    token, raw_token = described_class.generate!(user: user, name: "CLI", scopes: %w[read])

    expect(described_class.authenticate(raw_token)).to eq(token)
  end

  it "rejects revoked and expired tokens" do
    user = create(:user)
    revoked, revoked_raw = described_class.generate!(user: user, name: "Revoked", scopes: %w[read])
    expired, expired_raw = described_class.generate!(user: user, name: "Expired", scopes: %w[read], expires_at: 1.minute.ago)

    revoked.revoke!

    expect(described_class.authenticate(revoked_raw)).to be_nil
    expect(described_class.authenticate(expired_raw)).to be_nil
    expect(expired).to be_expired
  end

  it "requires an admin user for admin-scoped tokens" do
    user = create(:user)

    expect do
      described_class.generate!(user: user, name: "Admin", scopes: %w[admin])
    end.to raise_error(ActiveRecord::RecordInvalid, /admin scope/)
  end
end
