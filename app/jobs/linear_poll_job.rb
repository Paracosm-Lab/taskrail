class LinearPollJob < ApplicationJob
  queue_as :default

  SERVICE_LABELS = %w[crm-service user-service chat-service memory-service enrichment-service notification-service agent-service].freeze

  def perform
    client = LinearClient.new(api_key: ENV.fetch("LINEAR_API_KEY", ""))
    queue = WorkQueue.find_by!(slug: "postrunner-fix")
    first_stage = queue.stages.first || "fix"
    issues = client.postrunner_issues

    issues.each do |issue|
      next if WorkItem.where("tags @> ?", { "linear_issue_id" => issue["id"] }.to_json).exists?

      labels = issue.dig("labels", "nodes")&.map { |l| l["name"] } || []
      next if labels.include?("postrunner-ignore")

      service = (labels & SERVICE_LABELS).first || "unknown-service"
      repo = "MyScribbl/#{service}"
      linear_url = "https://linear.app/myscribbl/issue/#{issue['identifier']}"

      WorkItem.create!(
        work_queue: queue,
        title: issue["title"],
        spec_url: linear_url,
        stage_name: first_stage,
        status: :pending,
        tags: { "linear_issue_id" => issue["id"], "linear_identifier" => issue["identifier"],
                "repository" => repo, "service_name" => service },
        metadata: { "spec_inline" => issue["description"] }
      )
    rescue ActiveRecord::RecordNotUnique
      # Another worker already created this item — skip
      next
    end
  end
end
