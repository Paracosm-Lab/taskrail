class Claim < ApplicationRecord
  belongs_to :work_item

  has_many :reports, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_one :trace, dependent: :destroy

  enum :status, { active: 0, completed: 1, failed: 2, timed_out: 3 }

  HEARTBEAT_STALE_AFTER = 120.seconds

  validates :agent_type, presence: true

  def heartbeat_stale?
    active? && async_execution? && last_heartbeat_at.present? && last_heartbeat_at < stale_threshold.ago
  end

  private

  def stale_threshold
    work_item&.work_queue&.config&.dig("heartbeat_stale_seconds")&.seconds || HEARTBEAT_STALE_AFTER
  end
end
