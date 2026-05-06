require "uri"

module Cli
  class DashboardDataLoader
    DashboardData = Data.define(:api_url, :queue_slug, :queue, :stages, :work_items, :costs)

    def initialize(client:, api_url:, queue_slug:, limit: nil, status: nil)
      @client = client
      @api_url = api_url
      @queue_slug = queue_slug
      @limit = limit
      @status = status
    end

    def call
      encoded_queue_slug = URI.encode_www_form_component(queue_slug)
      queue_query = URI.encode_www_form(queue: queue_slug)
      stages_payload = client.get_json("/api/v1/queues/#{encoded_queue_slug}/stages")
      work_items_payload = client.get_json("/api/v1/work_items?#{queue_query}")
      costs_payload = client.get_json("/api/v1/costs")

      DashboardData.new(
        api_url: api_url,
        queue_slug: queue_slug,
        queue: stages_payload.fetch("queue", {}),
        stages: stages_payload.fetch("stages", []),
        work_items: filtered_work_items(work_items_payload.fetch("work_items", [])),
        costs: costs_payload
      )
    end

    private

    attr_reader :client, :api_url, :queue_slug, :limit, :status

    def filtered_work_items(work_items)
      items = work_items
      items = items.select { |item| item["status"] == status } unless blank?(status)
      limit_value = limit.to_i
      items = items.first(limit_value) if limit_value.positive?
      items
    end

    def blank?(value)
      value.nil? || value.respond_to?(:empty?) && value.empty?
    end
  end
end
