require "rails_helper"

RSpec.describe "development queue seed" do
  it "creates the development queue and stage configs" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "development")
    expect(queue.stages).to eq(%w[intake decompose build test review done])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly("intake", "decompose", "build", "test", "review", "done")

    build = queue.stage_configs.find_by!(stage_name: "build")
    expect(build.allowed_skills).to include("clone_repo", "create_branch", "edit_files", "run_tests")
    expect(build.forbidden_skills).to include("deploy", "merge_main", "mutate_database")
    expect(build.adapter_type).to eq("fake")

    test_stage = queue.stage_configs.find_by!(stage_name: "test")
    expect(test_stage.completion_criteria).to eq(%w[tests_passed lint_clean coverage_not_decreased])
    expect(test_stage.adapter_config).to eq({})
  end

  it "is idempotent" do
    2.times { load Rails.root.join("db/seeds.rb") }

    queue = WorkQueue.find_by!(slug: "development")
    expect(WorkQueue.where(slug: "development").count).to eq(1)
    expect(queue.stage_configs.count).to eq(6)
  end
end
