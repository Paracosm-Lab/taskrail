require "rails_helper"

RSpec.describe "Devise authentication", type: :request do
  it "renders the sign-in page with the web layout" do
    WorkQueue.create!(name: "Development", slug: "development-sign-in", stages: %w[intake done])

    get new_user_session_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Log in")
    expect(response.body).to include("development-sign-in")
  end

  it "redirects unauthenticated web requests to sign in" do
    get "/"

    expect(response).to redirect_to(new_user_session_path)
  end

  it "allows authenticated users to view the web UI" do
    user = create(:user)
    WorkQueue.create!(name: "Development", slug: "development-auth", stages: %w[intake done])

    sign_in user
    get "/"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("development-auth")
  end

  it "keeps admin endpoints closed without admin token or admin PAT" do
    put "/admin/maintenance", params: { enabled: true }, as: :json

    expect(response).to have_http_status(:service_unavailable)
  end
end
