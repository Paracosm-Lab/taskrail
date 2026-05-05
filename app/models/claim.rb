class Claim < ApplicationRecord
  belongs_to :work_item

  has_many :reports, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_one :trace, dependent: :destroy

  enum :status, { active: 0, completed: 1, failed: 2, timed_out: 3 }

  validates :agent_type, presence: true
end
