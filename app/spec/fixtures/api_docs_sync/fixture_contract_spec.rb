require "rails_helper"

RSpec.describe "api docs sync fixture" do
  let(:root) { Rails.root.join("spec/fixtures/api_docs_sync/rails_api") }

  it "contains documented, missing, and stale endpoint examples" do
    routes = root.join("config/routes.rb").read
    controller = root.join("app/controllers/api/v1/widgets_controller.rb").read
    serializer = root.join("app/serializers/widget_serializer.rb").read
    openapi = root.join("docs/openapi.yml").read

    expect(routes).to include("resources :widgets")
    expect(controller).to include("def index")
    expect(controller).to include("def create")
    expect(controller).to include("def show")
    expect(controller).to include("Requires Bearer token")
    expect(serializer).to include("attributes :id, :name, :status, :created_at")

    expect(openapi).to include("/api/v1/widgets:")
    expect(openapi).to include("get:")
    expect(openapi).to include("/api/v1/widgets/{id}:")
    expect(openapi).not_to include("post:")
    expect(openapi).to include("legacy_status")
  end
end
