require "rails_helper"

RSpec.describe "GET /api/v1/pipes", type: :request do
  def make_queue(slug, stages)
    WorkQueue.create!(name: slug, slug: "#{slug}-#{SecureRandom.hex(4)}", stages: stages)
  end

  it "returns paginated pipes" do
    src = make_queue("src", ["scan", "done"])
    dst = make_queue("dst", ["intake", "done"])
    Pipe.create!(name: "My Pipe", slug: "my-pipe-#{SecureRandom.hex(4)}", from_queue: src, from_stage: "scan", to_queue: dst)

    get "/api/v1/pipes"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.fetch("data").any? { |p| p["name"] == "My Pipe" }).to be true
    expect(body.fetch("pipes")).to eq(body.fetch("data"))
    expect(body.fetch("meta")).to include("total", "limit" => 50, "offset" => 0)
  end

  it "returns a single pipe by slug" do
    src = make_queue("src2", ["scan", "done"])
    dst = make_queue("dst2", ["intake", "done"])
    slug = "single-pipe-#{SecureRandom.hex(4)}"
    Pipe.create!(name: "Single Pipe", slug: slug, from_queue: src, from_stage: "scan", to_queue: dst)

    get "/api/v1/pipes/#{slug}"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["slug"]).to eq(slug)
    expect(body["from"]["queue"]).to eq(src.slug)
    expect(body["to"]["queue"]).to eq(dst.slug)
  end

  it "returns 404 for unknown pipe slug" do
    get "/api/v1/pipes/does-not-exist"
    expect(response).to have_http_status(:not_found)
  end
end
