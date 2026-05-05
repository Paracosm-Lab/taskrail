class Artifact < ApplicationRecord
  belongs_to :work_item
  belongs_to :claim

  validates :kind, presence: true
end
