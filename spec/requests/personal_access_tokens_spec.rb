require "rails_helper"

RSpec.describe "Personal access tokens", type: :request do
  it "creates a token for the signed-in user and only shows it once" do
    user = create(:user)
    sign_in user

    post "/personal_access_tokens", params: { personal_access_token: { name: "CLI", scopes: %w[read write] } }

    expect(response).to redirect_to(personal_access_tokens_path)
    follow_redirect!
    expect(response.body).to include("trpat_")
    raw_token = response.body[/trpat_[A-Za-z0-9_-]+/]
    token = user.personal_access_tokens.sole
    expect(token.scopes).to eq(%w[read write])

    get "/personal_access_tokens"
    expect(response.body).not_to include(raw_token)
    expect(response.body).to include(token.token_prefix)
  end

  it "revokes only the signed-in user's tokens" do
    user = create(:user)
    other_user = create(:user)
    token, = PersonalAccessToken.generate!(user: user, name: "CLI", scopes: %w[read])
    other_token, = PersonalAccessToken.generate!(user: other_user, name: "Other", scopes: %w[read])
    sign_in user

    delete "/personal_access_tokens/#{token.id}"
    expect(token.reload).to be_revoked

    delete "/personal_access_tokens/#{other_token.id}"
    expect(response).to have_http_status(:not_found)
    expect(other_token.reload).not_to be_revoked
  end

  it "authenticates API requests with PAT scopes" do
    queue = WorkQueue.create!(name: "Development", slug: "development-pat", stages: %w[intake done])
    StageConfig.create!(work_queue: queue, stage_name: "intake", adapter_type: "fake")
    read_token, read_raw = PersonalAccessToken.generate!(user: create(:user), name: "Read", scopes: %w[read])
    _write_token, write_raw = PersonalAccessToken.generate!(user: create(:user), name: "Write", scopes: %w[read write])

    get "/api/v1/queues", headers: { "Authorization" => "Bearer #{read_raw}" }
    expect(response).to have_http_status(:ok)

    post "/api/v1/work_items",
      params: { title: "Denied", spec_url: "opaque", queue: queue.slug },
      headers: { "Authorization" => "Bearer #{read_raw}" }
    expect(response).to have_http_status(:unauthorized)

    post "/api/v1/work_items",
      params: { title: "Allowed", spec_url: "opaque", queue: queue.slug },
      headers: { "Authorization" => "Bearer #{write_raw}" }
    expect(response).to have_http_status(:created)
    expect(read_token.reload.last_used_at).to be_present
  end

  it "authenticates admin endpoints with admin-scoped PATs owned by admins" do
    _token, raw_token = PersonalAccessToken.generate!(user: create(:user, :admin), name: "Admin", scopes: %w[admin])

    put "/admin/log-level", params: { level: "info" }, headers: { "Authorization" => "Bearer #{raw_token}" }

    expect(response).to have_http_status(:ok)
  end
end
