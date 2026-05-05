class WorkItem < ApplicationRecord
  belongs_to :work_queue
  belongs_to :parent, class_name: "WorkItem", optional: true

  has_many :children, -> { order(:position, :created_at, :id) }, class_name: "WorkItem", foreign_key: :parent_id, dependent: :nullify, inverse_of: :parent
  has_many :claims, dependent: :destroy
  has_many :reports, dependent: :destroy
  has_many :artifacts, dependent: :destroy
  has_many :traces, dependent: :destroy
  has_many :transition_logs, dependent: :destroy

  enum :status, { pending: 0, claimed: 1, blocked: 2, waiting: 3, completed: 4, cancelled: 5 }

  validates :title, :spec_url, :stage_name, presence: true

  def spec_inline
    metadata["spec_inline"]
  end
end
