class OrderBackfill
  BATCH_SIZE = 1_000

  def self.region!(default_region: "us")
    Order.missing_region.in_batches(of: BATCH_SIZE) do |relation|
      relation.update_all(region: default_region, updated_at: Time.current)
    end
  end
end
