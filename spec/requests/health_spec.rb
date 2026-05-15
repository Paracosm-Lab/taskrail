require "rails_helper"

RSpec.describe "Health endpoint", type: :request do
  it "returns service health JSON" do
    get "/health"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body).to include("status" => "ok", "service" => "taskrail")
    expect(body).to have_key("maintenance")
  end
end
