class WorkQueue < ApplicationRecord
  has_many :stage_configs, dependent: :destroy
  has_many :work_items, dependent: :restrict_with_exception

  validates :name, presence: true
  validates :slug, presence: true, uniqueness: true
end
