require "rails_helper"

RSpec.describe "Web::Pipes", type: :request do
  before { sign_in create(:user) }

  describe "GET /pipes" do
    it "returns 200" do
      get "/pipes"
      expect(response).to have_http_status(:ok)
    end

    context "with a pipe" do
      let!(:from_queue) { WorkQueue.create!(name: "Security", slug: "security_scan", stages: %w[scan done]) }
      let!(:to_queue)   { WorkQueue.create!(name: "Dev", slug: "development", stages: %w[intake done]) }
      let!(:pipe) do
        Pipe.create!(
          name: "Security to Dev",
          slug: "security_to_dev",
          from_queue: from_queue,
          from_stage: "scan",
          to_queue: to_queue
        )
      end

      it "shows the pipe name" do
        get "/pipes"
        expect(response.body).to include("security_to_dev")
      end
    end
  end
end
