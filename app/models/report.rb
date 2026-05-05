class Report < ApplicationRecord
  belongs_to :claim
  belongs_to :work_item

  enum :status, { success: 0, failure: 1, blocked: 2 }

  validates :stage_name, presence: true
end
