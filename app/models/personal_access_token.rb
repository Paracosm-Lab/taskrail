require "digest"

class PersonalAccessToken < ApplicationRecord
  TOKEN_PREFIX = "trpat".freeze
  RAW_TOKEN_BYTES = 32
  LAST_USED_WRITE_INTERVAL = 5.minutes
  SCOPES = %w[read write admin].freeze

  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :token_prefix, presence: true
  validates :scopes, presence: true
  validate :scopes_are_known
  validate :admin_scope_requires_admin_user

  scope :active, -> { where(revoked_at: nil).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  def self.generate!(user:, name:, scopes:, expires_at: nil)
    raw_token = "#{TOKEN_PREFIX}_#{SecureRandom.urlsafe_base64(RAW_TOKEN_BYTES)}"
    token = create!(
      user: user,
      name: name,
      token_digest: digest(raw_token),
      token_prefix: raw_token.first(12),
      scopes: Array(scopes).map(&:to_s).presence || ["read"],
      expires_at: expires_at
    )

    [token, raw_token]
  end

  def self.authenticate(raw_token)
    return nil unless raw_token.to_s.start_with?("#{TOKEN_PREFIX}_")

    active.includes(:user).find_by(token_digest: digest(raw_token))
  end

  def self.digest(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def active?
    !revoked? && !expired?
  end

  def includes_scope?(scope)
    scopes.include?(scope.to_s)
  end

  def mark_used!
    return if last_used_at.present? && last_used_at > LAST_USED_WRITE_INTERVAL.ago

    update_column(:last_used_at, Time.current)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def scopes_are_known
    unknown = scopes - SCOPES
    errors.add(:scopes, "include unknown scopes: #{unknown.join(', ')}") if unknown.any?
  end

  def admin_scope_requires_admin_user
    return unless scopes.include?("admin")
    return if user&.admin?

    errors.add(:scopes, "admin scope requires an admin user")
  end
end
