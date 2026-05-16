require "rails_helper"

RSpec.describe "actual seeded cookbook jobs", type: :request do
  CookbookJob = Struct.new(:slug, :spec_path, keyword_init: true)

  COOKBOOK_JOBS = [
    CookbookJob.new(slug: "api_docs_sync", spec_path: "docs/specs/cookbook-03-api-documentation-sync.md"),
    CookbookJob.new(slug: "chaos_monkey", spec_path: "docs/specs/cookbook-09-chaos-monkey.md"),
    CookbookJob.new(slug: "chaos_response", spec_path: "docs/cookbooks/09-chaos-monkey.md"),
    CookbookJob.new(slug: "credential_rotation", spec_path: "docs/specs/cookbook-20-credential-rotation.md"),
    CookbookJob.new(slug: "data_integrity", spec_path: "docs/specs/cookbook-18-data-integrity-validator.md"),
    CookbookJob.new(slug: "dead_code_removal", spec_path: "docs/specs/cookbook-05-dead-code-removal.md"),
    CookbookJob.new(slug: "dependency_upgrade", spec_path: "docs/specs/cookbook-13-dependency-upgrade.md"),
    CookbookJob.new(slug: "development", spec_path: "docs/cookbooks/04-feature-development.md"),
    CookbookJob.new(slug: "development-claude", spec_path: "docs/cookbooks/04-feature-development.md"),
    CookbookJob.new(slug: "development-codex", spec_path: "docs/cookbooks/04-feature-development.md"),
    CookbookJob.new(slug: "development-shell", spec_path: "docs/cookbooks/04-feature-development.md"),
    CookbookJob.new(slug: "error_handling_audit", spec_path: "docs/specs/cookbook-02-error-handling-audit.md"),
    CookbookJob.new(slug: "incident_readiness", spec_path: "docs/specs/cookbook-11-incident-readiness-scoring.md"),
    CookbookJob.new(slug: "infrastructure_drift", spec_path: "docs/specs/cookbook-21-infrastructure-drift.md"),
    CookbookJob.new(slug: "integration_tests", spec_path: "docs/specs/cookbook-16-integration-test-generator.md"),
    CookbookJob.new(slug: "job_observability", spec_path: "docs/specs/cookbook-12-background-job-observability.md"),
    CookbookJob.new(slug: "logging_audit", spec_path: "docs/specs/cookbook-06-logging-consistency-audit.md"),
    CookbookJob.new(slug: "migration_safety", spec_path: "docs/specs/cookbook-14-migration-safety.md"),
    CookbookJob.new(slug: "operations", spec_path: "docs/cookbooks/failure-readiness.md"),
    CookbookJob.new(slug: "post_incident_replay", spec_path: "docs/specs/cookbook-19-post-incident-replay.md"),
    CookbookJob.new(slug: "pr_review", spec_path: "docs/specs/cookbook-15-pr-review-pipeline.md"),
    CookbookJob.new(slug: "query_health", spec_path: "docs/specs/cookbook-07-database-query-health.md"),
    CookbookJob.new(slug: "security_scan", spec_path: "docs/specs/cookbook-17-security-scan.md"),
    CookbookJob.new(slug: "test_backfill", spec_path: "docs/specs/cookbook-01-test-coverage-backfill.md")
  ].freeze

  before do
    load Rails.root.join("db/seeds.rb")
    StageConfig.update_all(adapter_type: "fake")
  end

  COOKBOOK_JOBS.each do |cookbook_job|
    it "runs a #{cookbook_job.slug} cookbook job through its seeded queue" do
      expect(Rails.root.join(cookbook_job.spec_path)).to exist

      post "/api/v1/work_items",
        params: {
          queue: cookbook_job.slug,
          title: "Run #{cookbook_job.slug} cookbook",
          spec_url: cookbook_job.spec_path
        }
      expect(response).to have_http_status(:created)

      work_item = WorkItem.find(JSON.parse(response.body).fetch("id"))
      max_ticks = work_item.work_queue.stages.length * 20

      max_ticks.times do
        Engine::Runner.new.call
        break if work_item.reload.completed? || work_item.blocked?
      end

      expect(work_item).to be_completed, failure_summary(work_item)
      expect(work_item.stage_name).to eq("done")
      expect(work_item.claims.completed.count).to be >= work_item.work_queue.stages.length - 1
      expect(work_item.transition_logs.pluck(:trigger)).to include("rule_satisfied")
      expect(work_item.reports.success.count).to be >= work_item.work_queue.stages.length - 1
    end
  end

  it "covers every configured cookbook queue" do
    configured_slugs = Rails.root.glob("config/queues/*.yml").map do |path|
      YAML.load_file(path).fetch("slug")
    end

    expect(COOKBOOK_JOBS.map(&:slug)).to match_array(configured_slugs)
  end

  def failure_summary(work_item)
    logs = work_item.transition_logs.order(:created_at).map do |log|
      "#{log.from_stage}->#{log.to_stage}: #{log.trigger} #{log.details}"
    end

    <<~SUMMARY
      expected #{work_item.work_queue.slug} cookbook job to complete, got status=#{work_item.status} stage=#{work_item.stage_name}
      transition logs:
      #{logs.join("\n")}
    SUMMARY
  end
end
