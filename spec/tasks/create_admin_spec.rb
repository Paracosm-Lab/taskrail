require "rails_helper"
require "rake"

RSpec.describe "taskrail:create_admin" do
  before(:all) do
    Rails.application.load_tasks
  end

  after do
    Rake::Task["taskrail:create_admin"].reenable
  end

  it "creates an admin user from environment variables" do
    stub_const("ENV", ENV.to_hash.merge("EMAIL" => "Admin@Example.com", "PASSWORD" => "password123"))

    expect do
      Rake::Task["taskrail:create_admin"].invoke
    end.to change(User, :count).by(1)

    user = User.sole
    expect(user.email).to eq("admin@example.com")
    expect(user).to be_admin
  end
end
