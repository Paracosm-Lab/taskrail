class StageConfig < ApplicationRecord
  belongs_to :work_queue

  validates :stage_name, presence: true, uniqueness: { scope: :work_queue_id }
  validates :adapter_type, presence: true
end
