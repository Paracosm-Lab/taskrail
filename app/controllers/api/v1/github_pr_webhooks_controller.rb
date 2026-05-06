module Api
  module V1
    class GithubPrWebhooksController < ApplicationController
      SUPPORTED_ACTIONS = %w[opened reopened synchronize ready_for_review].freeze
      before_action :verify_webhook_signature!

      def create
        payload = request.request_parameters
        event_action = payload.fetch("action")
        return render json: { ignored: true, action: event_action }, status: :accepted unless SUPPORTED_ACTIONS.include?(event_action)

        pull_request = payload.fetch("pull_request")
        repository = payload.fetch("repository")
        queue = WorkQueue.find_by!(slug: "pr_review")

        item = WorkItem.create!(
          work_queue: queue,
          title: "PR ##{pull_request.fetch("number")}: #{pull_request.fetch("title")}",
          spec_url: pull_request.fetch("html_url"),
          stage_name: queue.stages.first,
          status: :pending,
          tags: {
            repository: repository.fetch("full_name"),
            pull_request_number: pull_request.fetch("number").to_s,
            branch: pull_request.fetch("head").fetch("ref"),
            base_branch: pull_request.fetch("base").fetch("ref"),
            head_sha: pull_request.fetch("head").fetch("sha")
          }
        )

        render json: {
          id: item.id,
          queue: queue.slug,
          stage_name: item.stage_name,
          status: item.status
        }, status: :created
      end

      private

      def verify_webhook_signature!
        secret = ENV["GITHUB_WEBHOOK_SECRET"].to_s
        return if secret.empty?

        signature = request.headers["X-Hub-Signature-256"].to_s
        return render(json: { error: "unauthorized", detail: "missing webhook signature" }, status: :unauthorized) if signature.empty?

        digest = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post.to_s)
        expected = "sha256=#{digest}"
        valid = ActiveSupport::SecurityUtils.secure_compare(signature, expected)
        return if valid

        render json: { error: "unauthorized", detail: "invalid webhook signature" }, status: :unauthorized
      rescue ArgumentError
        render json: { error: "unauthorized", detail: "invalid webhook signature" }, status: :unauthorized
      end
    end
  end
end
