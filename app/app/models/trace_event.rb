class TraceEvent < ApplicationRecord
  belongs_to :trace

  validates :sequence, :event_type, presence: true
end
