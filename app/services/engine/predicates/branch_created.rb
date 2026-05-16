require "open3"

module Engine
  module Predicates
    class BranchCreated
      def initialize(claim:)
        @claim = claim
      end

      def call
        artifact = @claim.artifacts.where(kind: "branch").detect { |item| item.data["name"].present? }
        return PredicateResult.fail(reason: "missing branch artifact with name") unless artifact

        workspace = working_directory
        return PredicateResult.pass(evidence: { artifact_id: artifact.id }) if workspace.blank?

        verify_branch_artifact(artifact, workspace)
      end

      private

      def working_directory
        @claim.assignment.dig("stage_config", "adapter_config", "working_directory").presence ||
          @claim.assignment.dig("stage", "adapter_config", "working_directory").presence
      end

      def verify_branch_artifact(artifact, workspace)
        branch_name = artifact.data.fetch("name")
        return PredicateResult.fail(reason: "branch workspace is not a git repository") unless primary_git_repository?(workspace)

        branch_rev = git_commit(workspace, branch_name)
        return PredicateResult.fail(reason: "branch artifact '#{branch_name}' does not exist in workspace git repository") if branch_rev.blank?

        expected_commit = artifact.data["commit"].presence
        if expected_commit.present?
          artifact_commit = git_commit(workspace, expected_commit)
          return PredicateResult.fail(reason: "branch artifact commit '#{expected_commit}' does not exist in workspace git repository") if artifact_commit.blank?
          return PredicateResult.fail(reason: "branch artifact '#{branch_name}' does not point to commit '#{expected_commit}'") unless branch_rev == artifact_commit
        end

        PredicateResult.pass(evidence: { artifact_id: artifact.id, branch: branch_name, commit: branch_rev })
      end

      def primary_git_repository?(workspace)
        return false unless File.directory?(workspace)
        return false unless File.exist?(File.join(workspace, ".git"))

        git_success?(workspace, "rev-parse", "--git-dir")
      end

      def git_commit(workspace, ref)
        stdout, status = git(workspace, "rev-parse", "--verify", "#{ref}^{commit}")
        return nil unless status&.success?

        stdout.strip.presence
      end

      def git_success?(workspace, *args)
        _stdout, status = git(workspace, *args)
        status&.success?
      end

      def git(workspace, *args)
        stdout, _stderr, status = Open3.capture3("git", "-C", workspace, *args)
        [stdout, status]
      rescue SystemCallError
        ["", nil]
      end
    end
  end
end
