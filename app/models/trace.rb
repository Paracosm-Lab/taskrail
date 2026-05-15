class Trace < ApplicationRecord
  belongs_to :claim
  belongs_to :work_item

  has_many :trace_events, dependent: :destroy

  validates :stage_name, :agent_type, presence: true
end
