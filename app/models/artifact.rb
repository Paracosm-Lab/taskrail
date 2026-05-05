class Artifact < ApplicationRecord
  belongs_to :work_item
  belongs_to :claim, optional: true

  validates :kind, presence: true
end
