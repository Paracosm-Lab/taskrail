require "rails_helper"

RSpec.describe "Admin settings", type: :request do
  around do |example|
    original = ENV["STUPIDCLAW_ADMIN_TOKEN"]
    ENV["STUPIDCLAW_ADMIN_TOKEN"] = "admin-secret"
    example.run
  ensure
    ENV["STUPIDCLAW_ADMIN_TOKEN"] = original
  end

  it "rejects missing admin auth" do
    put "/admin/maintenance", params: { enabled: true }, as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "updates maintenance with admin token" do
    put "/admin/maintenance",
      params: { enabled: true },
      headers: { "Authorization" => "Bearer admin-secret" },
      as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("maintenance" => true)
  end
end
