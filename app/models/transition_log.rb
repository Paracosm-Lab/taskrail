class TransitionLog < ApplicationRecord
  belongs_to :work_item

  validates :trigger, presence: true
end
