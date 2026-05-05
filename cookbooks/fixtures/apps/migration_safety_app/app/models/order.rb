class Order < ApplicationRecord
  validates :number, presence: true

  scope :missing_region, -> { where(region: nil) }
end
