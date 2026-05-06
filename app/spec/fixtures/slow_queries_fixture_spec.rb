require "rails_helper"

RSpec.describe "slow query fixture app" do
  let(:fixture_root) { Rails.root.join("test/fixtures/apps/slow_queries") }

  it "contains the expected query-health smells" do
    expect(fixture_root.join("README.md")).to exist
    expect(fixture_root.join("app/controllers/posts_controller.rb")).to exist
    expect(fixture_root.join("app/views/posts/index.html.erb")).to exist
    expect(fixture_root.join("app/services/wide_report_search.rb")).to exist
    expect(fixture_root.join("db/schema.rb")).to exist

    controller = fixture_root.join("app/controllers/posts_controller.rb").read
    view = fixture_root.join("app/views/posts/index.html.erb").read
    search = fixture_root.join("app/services/wide_report_search.rb").read
    schema = fixture_root.join("db/schema.rb").read

    expect(controller).to include("@posts = Post.all")
    expect(view).to include("post.author.name")
    expect(controller).to include("Post.where(status:")
    expect(search).to include("WideReport.select(\"*\")")
    expect(view).to include("post.comments.count")
    expect(schema).to include("create_table \"posts\"")
    expect(schema).not_to include("index_posts_on_status")
  end
end
