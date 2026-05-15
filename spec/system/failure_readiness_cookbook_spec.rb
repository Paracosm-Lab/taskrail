require "rails_helper"
require "json"
require "yaml"
require "securerandom"

RSpec.describe "failure readiness cookbook" do
  let(:fixture_root) { Rails.root.join("test/fixtures/sentry") }

  def fixture(name)
    JSON.parse(fixture_root.join(name).read)
  end

  it "ships the four alert fixtures used by the CRM database outage drill" do
    expected = {
      "db_pool_timeout.json" => ["ActiveRecord::ConnectionTimeoutError", "crm-service"],
      "db_connection_bad.json" => ["PG::ConnectionBad", "crm-service"],
      "null_reference.json" => ["NoMethodError", "notification-service"],
      "rate_limit_thin.json" => ["HTTP::TimeoutError", "billing-service"]
    }

    expected.each do |filename, (exception_type, service)|
      payload = fixture(filename)

      expect(payload.fetch("platform")).to eq("ruby")
      expect(payload.fetch("level")).to eq("error")
      expect(payload.fetch("timestamp")).to eq("REPLACED_AT_SEND_TIME")
      expect(payload.dig("exception", "values", 0, "type")).to eq(exception_type)
      expect(payload.dig("tags", "service")).to eq(service)
      expect(payload.dig("tags", "environment")).to eq("staging")
    end
  end

  it "keeps CRM database alerts correlated enough for causal clustering" do
    pool = fixture("db_pool_timeout.json")
    refused = fixture("db_connection_bad.json")

    expect(pool.dig("tags", "service")).to eq("crm-service")
    expect(refused.dig("tags", "service")).to eq("crm-service")
    expect(pool.dig("tags", "region")).to eq(refused.dig("tags", "region"))
    expect(pool.dig("tags", "database_host")).to eq("crm-postgres.internal")
    expect(refused.dig("tags", "database_host")).to eq("crm-postgres.internal")
    expect(pool.dig("exception", "values", 0, "stacktrace", "frames").to_json).to include("sessions_controller.rb")
    expect(refused.dig("exception", "values", 0, "stacktrace", "frames").to_json).to include("database.yml")
  end

  it "keeps billing rate limit intentionally thin for instrumentation scoring" do
    rate_limit = fixture("rate_limit_thin.json")

    expect(rate_limit.dig("exception", "values", 0, "type")).to eq("HTTP::TimeoutError")
    expect(rate_limit.dig("exception", "values", 0, "value")).to eq("rate limit exceeded")
    expect(rate_limit).not_to have_key("contexts")
    expect(rate_limit).not_to have_key("breadcrumbs")
    expect(rate_limit.fetch("tags").keys).to contain_exactly("service", "environment")
  end

  it "seeds the operations queue as the failure-readiness pipeline" do
    load Rails.root.join("db/seeds.rb")

    queue = WorkQueue.find_by!(slug: "operations")
    expect(queue.stages).to eq(%w[
      ingest_signals
      cluster_failures
      assess_instrumentation
      map_runbooks
      draft_runbook
      human_review
      staging_validation
      publish_runbook
      done
    ])
    expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)

    ingest = queue.stage_configs.find_by!(stage_name: "ingest_signals")
    expect(ingest.adapter_type).to eq("inline_claude")
    expect(ingest.model_override).to eq("claude-haiku-4-5-20251001")
    expect(ingest.completion_criteria).to eq(["report_present"])
    expect(ingest.agent_prompt).to include("# Ops Ingest Signals")
    expect(ingest.agent_prompt).not_to start_with("file://")

    cluster = queue.stage_configs.find_by!(stage_name: "cluster_failures")
    expect(cluster.model_override).to eq("claude-sonnet-4-20250514")
    expect(cluster.completion_criteria).to eq(["clusters_created"])
    expect(cluster.adapter_config).to include("output_artifact_kind" => "clusters")

    assess = queue.stage_configs.find_by!(stage_name: "assess_instrumentation")
    expect(assess.completion_criteria).to eq(["assessment_complete"])
    expect(assess.adapter_config).to include("output_artifact_kind" => "instrumentation_assessment")
    expect(assess.agent_prompt).to include("spawn_work_items")
    expect(assess.agent_prompt).to include("development")

    map = queue.stage_configs.find_by!(stage_name: "map_runbooks")
    expect(map.completion_criteria).to eq(["runbook_mapped"])
    expect(map.adapter_config).to include("output_artifact_kind" => "runbook_mapping")

    draft = queue.stage_configs.find_by!(stage_name: "draft_runbook")
    expect(draft.model_override).to eq("claude-opus-4-20250514")
    expect(draft.completion_criteria).to eq(["runbook_drafted"])
    expect(draft.agent_prompt).to include("Observe")
    expect(draft.agent_prompt).to include("Mitigate")
    expect(draft.agent_prompt).to include("Verify")

    review = queue.stage_configs.find_by!(stage_name: "human_review")
    expect(review.adapter_type).to eq("fake")
    expect(review.timeout_seconds).to eq(86_400)

    staging = queue.stage_configs.find_by!(stage_name: "staging_validation")
    expect(staging.adapter_type).to eq("docker_compose")
    expect(staging.completion_criteria).to eq(["validation_passed"])
    expect(staging.adapter_config).not_to have_key("working_directory")

    serialized = Rails.root.join("config/queues/operations.yml").read
    expect(serialized).not_to include(Rails.root.to_s)
    expect(serialized).not_to include("/Users/")
    expect(serialized).to include("file://prompts/ops_ingest_signals.md")
  end

  it "models the CRM drill artifacts through the operations predicates" do
    load Rails.root.join("db/seeds.rb")
    queue = WorkQueue.find_by!(slug: "operations")
    item = WorkItem.create!(
      work_queue: queue,
      title: "Failure readiness drill: CRM database outage",
      spec_url: "test://crm-db-drill",
      stage_name: "cluster_failures"
    )

    cluster_claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    clusters = Artifact.create!(
      work_item: item,
      claim: cluster_claim,
      kind: "clusters",
      data: {
        "clusters" => [
          { "id" => "crm-postgres-unavailable", "severity" => "high", "alerts" => ["db_pool_timeout", "db_connection_bad"] },
          { "id" => "notification-nil-reference", "severity" => "medium", "alerts" => ["null_reference"] },
          { "id" => "billing-rate-limit", "severity" => "low", "alerts" => ["rate_limit_thin"] }
        ]
      }
    )

    cluster_result = Engine::Predicates::ClustersCreated.new(claim: cluster_claim).call
    expect(cluster_result).to be_passed
    expect(cluster_result.evidence).to include(artifact_id: clusters.id)

    item.update!(stage_name: "assess_instrumentation")
    assess_claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    assessment = Artifact.create!(
      work_item: item,
      claim: assess_claim,
      kind: "instrumentation_assessment",
      data: {
        "scores" => [
          { "cluster_id" => "crm-postgres-unavailable", "score" => 2.2, "verdict" => "thin" },
          { "cluster_id" => "notification-nil-reference", "score" => 2.0, "verdict" => "thin" },
          { "cluster_id" => "billing-rate-limit", "score" => 1.2, "verdict" => "thin" }
        ]
      }
    )

    assessment_result = Engine::Predicates::AssessmentComplete.new(claim: assess_claim).call
    expect(assessment_result).to be_passed
    expect(assessment_result.evidence).to eq({ artifact_id: assessment.id })

    item.update!(stage_name: "map_runbooks")
    map_claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    mapping = Artifact.create!(
      work_item: item,
      claim: map_claim,
      kind: "runbook_mapping",
      data: {
        "mappings" => [
          { "cluster_id" => "crm-postgres-unavailable", "status" => "missing" },
          { "cluster_id" => "notification-nil-reference", "status" => "missing" },
          { "cluster_id" => "billing-rate-limit", "status" => "missing" }
        ]
      }
    )

    mapping_result = Engine::Predicates::RunbookMapped.new(claim: map_claim).call
    expect(mapping_result).to be_passed
    expect(mapping_result.evidence).to include(artifact_id: mapping.id)
  end

  it "spawns development instrumentation fixes for thin alert clusters" do
    ops_queue = WorkQueue.create!(name: "Operations", slug: "ops-failure-readiness-#{SecureRandom.hex(4)}", stages: %w[assess_instrumentation map_runbooks done])
    ops_queue.stage_configs.create!(stage_name: "assess_instrumentation", adapter_type: "fake", completion_criteria: %w[report_present])
    ops_queue.stage_configs.create!(stage_name: "map_runbooks", adapter_type: "fake")
    dev_queue = WorkQueue.create!(name: "Development", slug: "development-#{SecureRandom.hex(4)}", stages: %w[intake build test done])

    item = WorkItem.create!(work_queue: ops_queue, title: "CRM failure drill", spec_url: "test://crm-db-drill", stage_name: "assess_instrumentation")
    claim = Claim.create!(work_item: item, agent_type: "fake", status: "completed", started_at: Time.current)
    Report.create!(
      work_item: item,
      claim: claim,
      stage_name: "assess_instrumentation",
      status: "success",
      body: {
        "spawn_work_items" => [
          {
            "queue_slug" => dev_queue.slug,
            "title" => "Improve crm-service database outage Sentry context",
            "spec_inline" => "Add request_id, tenant_id, database_host, pool stats, pg_stat summary, context, and breadcrumbs for ActiveRecord::ConnectionTimeoutError and PG::ConnectionBad paths.",
            "tags" => { "domain" => "failure_readiness", "cluster_id" => "crm-postgres-unavailable" }
          },
          {
            "queue_slug" => dev_queue.slug,
            "title" => "Improve notification-service nil reference alert context",
            "spec_inline" => "Add upstream dependency, lookup key, customer/account context, and breadcrumb evidence around nil lookup failures.",
            "tags" => { "domain" => "failure_readiness", "cluster_id" => "notification-nil-reference" }
          },
          {
            "queue_slug" => dev_queue.slug,
            "title" => "Improve billing-service rate limit instrumentation",
            "spec_inline" => "Replace misleading HTTP::TimeoutError with a rate-limit-specific error and add provider context, http_status, retry_after, payment IDs, idempotency key, and request breadcrumbs.",
            "tags" => { "domain" => "failure_readiness", "cluster_id" => "billing-rate-limit" }
          }
        ]
      }
    )

    stage_config = ops_queue.stage_configs.find_by!(stage_name: "assess_instrumentation")
    Engine::TransitionManager.new(work_item: item, claim: claim, stage_config: stage_config).call

    expect(item.reload.stage_name).to eq("map_runbooks")
    spawned = WorkItem.where(work_queue: dev_queue).order(:title)
    expect(spawned.count).to eq(3)
    expect(spawned.map(&:title)).to include(
      "Improve billing-service rate limit instrumentation",
      "Improve crm-service database outage Sentry context",
      "Improve notification-service nil reference alert context"
    )
    expect(spawned.map { |work_item| work_item.tags["domain"] }.uniq).to eq(["failure_readiness"])
    expect(spawned.map { |work_item| work_item.metadata["spec_inline"] }).to all(include("context"))
  end

  it "stores example runbooks with observe mitigate verify and escalation sections" do
    root = Rails.root.join("docs/runbooks/failure-readiness")

    postgres = root.join("crm-postgres-unavailable.md")
    billing = root.join("billing-rate-limit.md")
    expect(postgres).to exist
    expect(billing).to exist

    [postgres, billing].each do |path|
      content = path.read
      expect(content).to include("## Scope")
      expect(content).to include("## Observe")
      expect(content).to include("## Mitigate")
      expect(content).to include("## Verify")
      expect(content).to include("## Escalate")
      expect(content).to include("Human review required")
      expect(content).not_to include(Rails.root.to_s)
      expect(content).not_to include("/Users/")
    end

    expect(postgres.read).to include("pg_isready -h crm-postgres.internal -p 5432")
    expect(postgres.read).to include("idle_in_transaction")
    expect(billing.read).to include("Retry-After")
    expect(billing.read).to include("idempotency")
  end

  it "provides a Docker-friendly staging fixture for runbook validation" do
    root = Rails.root.join("spec/fixtures/failure_readiness/staging")

    expect(root.join("docker-compose.yml")).to exist
    expect(root.join("api/config.ru")).to exist
    expect(root.join("scripts/pg_observe.sh")).to exist
    expect(root.join("scripts/verify_recovery.sh")).to exist

    compose = YAML.load_file(root.join("docker-compose.yml"))
    expect(compose.fetch("services").keys).to include("failure-api", "failure-postgres")
    expect(root.join("docker-compose.yml").read).to include("${FAILURE_READINESS_API_PORT:-3938}")
    expect(root.join("docker-compose.yml").read).not_to include(Rails.root.to_s)

    expect(root.join("scripts/pg_observe.sh").read).to include("pg_isready")
    expect(root.join("scripts/verify_recovery.sh").read).to include("service_healthy")
  end

  it "documents how to run and interpret the failure readiness cookbook" do
    doc = Rails.root.join("docs/cookbooks/failure-readiness.md")
    expect(doc).to exist

    content = doc.read
    expect(content).to include("# Failure Readiness Cookbook")
    expect(content).to include("docs/cookbook-failure-readiness.md")
    expect(content).to include("bin/generate-sentry-alerts --dry-run")
    expect(content).to include("operations")
    expect(content).to include("human_review")
    expect(content).to include("spawn_work_items")
    expect(content).to include("docs/runbooks/failure-readiness")
    expect(content).not_to include(Rails.root.to_s)
    expect(content).not_to include("/Users/")
  end
end
