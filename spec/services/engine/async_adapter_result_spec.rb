require "rails_helper"

RSpec.describe Engine::AsyncAdapterResult do
  it "stores async submission metadata" do
    result = described_class.new(
      provider: "codex",
      external_id: "run-123",
      status: "submitted",
      metadata: { "branch" => "sc-123" },
      trace_events: [{ "event_type" => "codex_submit" }]
    )

    expect(result.provider).to eq("codex")
    expect(result.external_id).to eq("run-123")
    expect(result.status).to eq("submitted")
    expect(result.metadata["branch"]).to eq("sc-123")
    expect(result.trace_events.first["event_type"]).to eq("codex_submit")
  end
end
