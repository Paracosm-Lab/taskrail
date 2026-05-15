class Claim < ApplicationRecord
  belongs_to :work_item

  has_many :reports, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_one :trace, dependent: :destroy

  enum :status, { active: 0, completed: 1, failed: 2, timed_out: 3 }

  HEARTBEAT_STALE_AFTER = 120.seconds

  validates :agent_type, presence: true

  def heartbeat_stale?
    active? && async_execution? && last_heartbeat_at.present? && last_heartbeat_at < HEARTBEAT_STALE_AFTER.ago
  end
end
