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

    def heartbeat(claim, message = nil)
      claim.update_columns(
        last_heartbeat_at: Time.current,
        heartbeat_message: message
      )
    end
  end
end
