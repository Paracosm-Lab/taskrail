require "rails_helper"

RSpec.describe Pipe do
  def make_queue(slug, stages)
    WorkQueue.create!(name: slug, slug: slug, stages: stages)
  end

  it "is valid with required fields" do
    q = make_queue("src-#{SecureRandom.hex(4)}", ["scan", "done"])
    t = make_queue("dst-#{SecureRandom.hex(4)}", ["intake", "done"])
    pipe = Pipe.new(name: "Test Pipe", slug: "test-pipe-#{SecureRandom.hex(4)}", from_queue: q, from_stage: "scan", to_queue: t)
    expect(pipe).to be_valid
  end

  it "is invalid when from_stage is not in the source queue" do
    q = make_queue("src2-#{SecureRandom.hex(4)}", ["scan", "done"])
    t = make_queue("dst2-#{SecureRandom.hex(4)}", ["intake", "done"])
    pipe = Pipe.new(name: "Test", slug: "test2-#{SecureRandom.hex(4)}", from_queue: q, from_stage: "nonexistent", to_queue: t)
    expect(pipe).not_to be_valid
    expect(pipe.errors[:from_stage]).to be_present
  end

  it "is invalid when to_stage is set but not in target queue" do
    q = make_queue("src3-#{SecureRandom.hex(4)}", ["scan", "done"])
    t = make_queue("dst3-#{SecureRandom.hex(4)}", ["intake", "done"])
    pipe = Pipe.new(name: "Test", slug: "test3-#{SecureRandom.hex(4)}", from_queue: q, from_stage: "scan", to_queue: t, to_stage: "nonexistent")
    expect(pipe).not_to be_valid
    expect(pipe.errors[:to_stage]).to be_present
  end

  it "is invalid when same-queue pipe targets an earlier stage" do
    q = make_queue("loop-#{SecureRandom.hex(4)}", ["stage_a", "stage_b", "stage_c", "done"])
    pipe = Pipe.new(name: "Loop", slug: "loop-#{SecureRandom.hex(4)}", from_queue: q, from_stage: "stage_b", to_queue: q, to_stage: "stage_a")
    expect(pipe).not_to be_valid
    expect(pipe.errors[:to_stage]).to be_present
  end

  it "is valid when same-queue pipe targets a later stage" do
    q = make_queue("fwd-#{SecureRandom.hex(4)}", ["stage_a", "stage_b", "stage_c", "done"])
    pipe = Pipe.new(name: "Forward", slug: "fwd-#{SecureRandom.hex(4)}", from_queue: q, from_stage: "stage_a", to_queue: q, to_stage: "stage_c")
    expect(pipe).to be_valid
  end
end
