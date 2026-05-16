require "rails_helper"
require "tmpdir"

def build_claim(stage_name: "test", working_directory: nil)
  queue = WorkQueue.create!(name: "Development #{SecureRandom.hex(4)}", slug: "development-#{SecureRandom.hex(4)}", stages: %w[build test review done])
  work_item = WorkItem.create!(title: "Test item", spec_url: "opaque spec", work_queue: queue, stage_name: stage_name)
  assignment = {
    "stage_config" => {
      "adapter_config" => {}
    }
  }
  assignment["stage_config"]["adapter_config"]["working_directory"] = working_directory if working_directory

  Claim.create!(work_item: work_item, agent_type: "fake", status: :active, assignment: assignment)
end

RSpec.describe Engine::Predicates::BranchCreated do
  it "passes when a branch artifact has a name and no workspace is configured" do
    claim = build_claim(stage_name: "build")
    artifact = Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => "sc/test" })

    result = described_class.new(claim: claim).call

    expect(result).to be_passed
    expect(result.evidence[:artifact_id]).to eq(artifact.id)
  end

  it "fails when no named branch artifact exists" do
    claim = build_claim(stage_name: "build")

    result = described_class.new(claim: claim).call

    expect(result).not_to be_passed
    expect(result.reason).to eq("missing branch artifact with name")
  end

  it "passes when the branch and commit exist in the configured workspace repository" do
    Dir.mktmpdir("branch-created") do |workspace|
      commit = initialize_git_repo(workspace)
      branch = "taskrail/test-branch"
      run_git(workspace, "checkout", "-b", branch)

      claim = build_claim(stage_name: "build", working_directory: workspace)
      artifact = Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => branch, "commit" => commit })

      result = described_class.new(claim: claim).call

      expect(result).to be_passed
      expect(result.evidence).to include(artifact_id: artifact.id, branch: branch, commit: commit)
    end
  end

  it "fails when the configured workspace is not a git repository" do
    Dir.mktmpdir("branch-created") do |workspace|
      claim = build_claim(stage_name: "build", working_directory: workspace)
      Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => "taskrail/missing" })

      result = described_class.new(claim: claim).call

      expect(result).not_to be_passed
      expect(result.reason).to eq("branch workspace is not a git repository")
    end
  end

  it "fails when the branch only exists outside the configured workspace repository" do
    Dir.mktmpdir("branch-created") do |workspace|
      initialize_git_repo(workspace)
      alt_git_dir = File.join(workspace, ".taskrail-git")
      run_git(workspace, "--git-dir=#{alt_git_dir}", "init")
      run_git(workspace, "--git-dir=#{alt_git_dir}", "--work-tree=#{workspace}", "checkout", "-b", "taskrail/alt")

      claim = build_claim(stage_name: "build", working_directory: workspace)
      Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => "taskrail/alt" })

      result = described_class.new(claim: claim).call

      expect(result).not_to be_passed
      expect(result.reason).to eq("branch artifact 'taskrail/alt' does not exist in workspace git repository")
    end
  end

  it "fails when the reported commit does not exist in the workspace repository" do
    Dir.mktmpdir("branch-created") do |workspace|
      initialize_git_repo(workspace)
      branch = "taskrail/test-branch"
      run_git(workspace, "checkout", "-b", branch)

      claim = build_claim(stage_name: "build", working_directory: workspace)
      Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => branch, "commit" => "0" * 40 })

      result = described_class.new(claim: claim).call

      expect(result).not_to be_passed
      expect(result.reason).to eq("branch artifact commit '#{'0' * 40}' does not exist in workspace git repository")
    end
  end

  it "fails when the reported commit does not match the branch tip" do
    Dir.mktmpdir("branch-created") do |workspace|
      initial_commit = initialize_git_repo(workspace)
      branch = "taskrail/test-branch"
      run_git(workspace, "checkout", "-b", branch)
      File.write(File.join(workspace, "README.md"), "changed\n")
      run_git(workspace, "add", "README.md")
      run_git(workspace, "commit", "-m", "Change readme")

      claim = build_claim(stage_name: "build", working_directory: workspace)
      Artifact.create!(claim: claim, work_item: claim.work_item, kind: "branch", data: { "name" => branch, "commit" => initial_commit })

      result = described_class.new(claim: claim).call

      expect(result).not_to be_passed
      expect(result.reason).to eq("branch artifact '#{branch}' does not point to commit '#{initial_commit}'")
    end
  end

  def initialize_git_repo(workspace)
    run_git(workspace, "init")
    run_git(workspace, "config", "user.email", "test@example.com")
    run_git(workspace, "config", "user.name", "Test User")
    File.write(File.join(workspace, "README.md"), "hello\n")
    run_git(workspace, "add", "README.md")
    run_git(workspace, "commit", "-m", "Initial commit")
    git_output(workspace, "rev-parse", "HEAD")
  end

  def run_git(workspace, *args)
    system("git", "-C", workspace, *args, out: File::NULL, err: File::NULL) || raise("git #{args.join(' ')} failed")
  end

  def git_output(workspace, *args)
    IO.popen(["git", "-C", workspace, *args], &:read).strip
  end
end
