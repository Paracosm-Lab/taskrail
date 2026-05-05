module Engine
  AsyncAdapterResult = Data.define(:provider, :external_id, :status, :metadata, :trace_events)
end
