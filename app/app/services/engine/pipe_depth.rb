# app/services/engine/pipe_depth.rb
module Engine
  module PipeDepth
    def self.for(work_item)
      depth = work_item.pipe_id.present? ? 1 : 0
      current = work_item
      while current.parent_id.present?
        current = WorkItem.find(current.parent_id)
        depth += 1 if current.pipe_id.present?
      end
      depth
    end
  end
end
