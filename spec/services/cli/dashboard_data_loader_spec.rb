require "rails_helper"

RSpec.describe Cli::DashboardDataLoader do
  it "loads dashboard data from the API" do
    client = instance_double(Cli::TaskRailApiClient)
    allow(client).to receive(:get_json).with("/api/v1/queues/development/stages").and_return(
      "queue" => { "slug" => "development", "name" => "Development" },
      "stages" => [{ "name" => "build", "adapter_type" => "fake" }]
    )
    allow(client).to receive(:get_json).with("/api/v1/work_items?queue=development").and_return(
      "work_items" => [{ "id" => 1, "status" => "pending", "stage_name" => "build" }]
    )
    allow(client).to receive(:get_json).with("/api/v1/costs").and_return(
      "total_cost_cents" => 7,
      "total_tokens_in" => 10,
      "total_tokens_out" => 20
    )

    data = described_class.new(client: client, api_url: "http://example.test", queue_slug: "development").call

    expect(data.api_url).to eq("http://example.test")
    expect(data.queue_slug).to eq("development")
    expect(data.queue).to eq("slug" => "development", "name" => "Development")
    expect(data.stages).to eq([{ "name" => "build", "adapter_type" => "fake" }])
    expect(data.work_items).to eq([{ "id" => 1, "status" => "pending", "stage_name" => "build" }])
    expect(data.costs).to eq("total_cost_cents" => 7, "total_tokens_in" => 10, "total_tokens_out" => 20)
  end

  it "filters work items by status client-side" do
    client = dashboard_client_with_work_items([
      { "id" => 1, "status" => "pending" },
      { "id" => 2, "status" => "blocked" }
    ])

    data = described_class.new(client: client, api_url: "http://example.test", queue_slug: "development", status: "blocked").call

    expect(data.work_items).to eq([{ "id" => 2, "status" => "blocked" }])
  end

  it "limits work items client-side" do
    client = dashboard_client_with_work_items([
      { "id" => 1, "status" => "pending" },
      { "id" => 2, "status" => "pending" }
    ])

    data = described_class.new(client: client, api_url: "http://example.test", queue_slug: "development", limit: 1).call

    expect(data.work_items).to eq([{ "id" => 1, "status" => "pending" }])
  end

  it "ignores non-positive limits" do
    client = dashboard_client_with_work_items([
      { "id" => 1, "status" => "pending" },
      { "id" => 2, "status" => "pending" }
    ])

    data = described_class.new(client: client, api_url: "http://example.test", queue_slug: "development", limit: 0).call

    expect(data.work_items).to eq([
      { "id" => 1, "status" => "pending" },
      { "id" => 2, "status" => "pending" }
    ])
  end

  it "escapes queue slugs in path and query API calls" do
    client = instance_double(Cli::TaskRailApiClient)
    allow(client).to receive(:get_json).with("/api/v1/queues/dev%26status%3Dblocked/stages").and_return("queue" => {}, "stages" => [])
    allow(client).to receive(:get_json).with("/api/v1/work_items?queue=dev%26status%3Dblocked").and_return("work_items" => [])
    allow(client).to receive(:get_json).with("/api/v1/costs").and_return({})

    data = described_class.new(client: client, api_url: "http://example.test", queue_slug: "dev&status=blocked").call

    expect(data.queue_slug).to eq("dev&status=blocked")
  end

  def dashboard_client_with_work_items(work_items)
    instance_double(Cli::TaskRailApiClient).tap do |client|
      allow(client).to receive(:get_json).with("/api/v1/queues/development/stages").and_return("queue" => { "slug" => "development" }, "stages" => [])
      allow(client).to receive(:get_json).with("/api/v1/work_items?queue=development").and_return("work_items" => work_items)
      allow(client).to receive(:get_json).with("/api/v1/costs").and_return({})
    end
  end
end
