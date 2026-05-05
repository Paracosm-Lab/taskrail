class Pipe < ApplicationRecord
  belongs_to :from_queue, class_name: "WorkQueue"
  belongs_to :to_queue, class_name: "WorkQueue"

  validates :name, :slug, :from_stage, presence: true
  validates :slug, uniqueness: true
  validate :from_stage_exists_in_queue
  validate :to_stage_exists_in_queue
  validate :no_backward_same_queue_loop

  private

  def from_stage_exists_in_queue
    return unless from_queue
    return if from_queue.stages.include?(from_stage)

    errors.add(:from_stage, "#{from_stage.inspect} does not exist in queue #{from_queue.slug.inspect}")
  end

  def to_stage_exists_in_queue
    return unless to_queue && to_stage.present?
    return if to_queue.stages.include?(to_stage)

    errors.add(:to_stage, "#{to_stage.inspect} does not exist in queue #{to_queue.slug.inspect}")
  end

  def no_backward_same_queue_loop
    return unless from_queue && to_queue && to_stage.present?
    return unless from_queue.id == to_queue.id

    from_index = from_queue.stages.index(from_stage)
    to_index = to_queue.stages.index(to_stage)
    return unless from_index && to_index
    return if to_index > from_index

    errors.add(:to_stage, "must come after from_stage in the stage sequence for same-queue pipes")
  end
end
