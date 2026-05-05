require "rails_helper"

RSpec.describe "security scan vulnerable fixture" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/vulnerable_security_app") }

  it "contains representative security issues with portable paths" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/controllers/orders_controller.rb")).to exist
    expect(fixture_root.join("app/views/orders/show.html.erb")).to exist
    expect(fixture_root.join("app/services/legacy_exporter.rb")).to exist

    controller = fixture_root.join("app/controllers/orders_controller.rb").read
    expect(controller).to include('Order.where("id = ')
    expect(controller).to include("params[:id]")
    expect(controller).to include("skip_before_action :verify_authenticity_token")
    expect(controller).to include("render json: user.as_json")

    view = fixture_root.join("app/views/orders/show.html.erb").read
    expect(view).to include("html_safe")

    service = fixture_root.join("app/services/legacy_exporter.rb").read
    expect(service).to include("system")
    expect(service).to include("LEGACY_API_KEY")

    cors = fixture_root.join("config/initializers/cors.rb").read
    expect(cors).to include("origins '*'")

    serialized_paths = fixture_root.glob("**/*").select(&:file?).map(&:read).join("\n")
    expect(serialized_paths).not_to include(Rails.root.to_s)
    expect(serialized_paths).not_to include(["", "Users", ""].join("/"))
  end
end
