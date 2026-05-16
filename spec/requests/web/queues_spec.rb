require "rails_helper"

RSpec.describe "Web::Queues", type: :request do
  before { sign_in create(:user) }

  let!(:queue) do
    WorkQueue.create!(
      name: "Security Scan",
      slug: "security_scan",
      stages: %w[scan classify done]
    )
  end

  describe "GET /" do
    it "returns 200 and lists queues" do
      get "/"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("security_scan")
    end
  end

  describe "GET /queues/:slug" do
    it "returns 200 for a valid queue" do
      get "/queues/security_scan"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("security_scan")
    end

    it "returns 404 for an unknown queue" do
      get "/queues/nonexistent"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /queues/:slug/board" do
    it "returns 200 and renders column names" do
      get "/queues/security_scan/board"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("scan")
      expect(response.body).to include("classify")
    end
  end
end
