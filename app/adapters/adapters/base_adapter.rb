module Adapters
  class BaseAdapter
    def execute(_assignment)
      raise NotImplementedError, "#{self.class.name} must implement #execute"
    end

    def check_status(_claim)
      :completed
    end

    def cancel(_claim)
      nil
    end
  end
end
