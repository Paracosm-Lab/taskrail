module Api
  module V1
    class GithubPrWebhooksController < ApplicationController
      SUPPORTED_ACTIONS = %w[opened reopened synchronize ready_for_review].freeze

      def create
        event_action = params.require(:github_pr_webhook).require(:action)
        return render json: { ignored: true, action: event_action }, status: :accepted unless SUPPORTED_ACTIONS.include?(event_action)

        pull_request = params.require(:pull_request)
        repository = params.require(:repository)
        queue = WorkQueue.find_by!(slug: "pr_review")

        item = WorkItem.create!(
          work_queue: queue,
          title: "PR ##{pull_request.require(:number)}: #{pull_request.require(:title)}",
          spec_url: pull_request.require(:html_url),
          stage_name: queue.stages.first,
          status: :pending,
          tags: {
            repository: repository.require(:full_name),
            pull_request_number: pull_request.require(:number).to_s,
            branch: pull_request.require(:head).require(:ref),
            base_branch: pull_request.require(:base).require(:ref),
            head_sha: pull_request.require(:head).require(:sha)
          }
        )

        render json: {
          id: item.id,
          queue: queue.slug,
          stage_name: item.stage_name,
          status: item.status
        }, status: :created
      end
    end
  end
end
