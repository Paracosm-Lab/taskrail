require "rails_helper"
require "json"
require "open3"
require "shellwords"

RSpec.describe "bin/generate-sentry-alerts" do
  let(:repo_root) { Rails.root }
  let(:script) { repo_root.join("bin/generate-sentry-alerts") }
  let(:fixtures_dir) { repo_root.join("test/fixtures/sentry") }
  let(:dsn) { "https://public-key@sentry.io/12345" }

  def run_script(*args, env: {})
    Open3.capture3(env, script.to_s, *args.map(&:to_s), chdir: repo_root.to_s)
  end

  it "ships the four expected Sentry event fixtures with valid JSON payloads" do
    expected = {
      "db_pool_timeout.json" => ["ActiveRecord::ConnectionTimeoutError", "crm-service"],
      "db_connection_bad.json" => ["PG::ConnectionBad", "crm-service"],
      "null_reference.json" => ["NoMethodError", "notification-service"],
      "rate_limit_thin.json" => ["HTTP::TimeoutError", "billing-service"]
    }

    expected.each do |filename, (exception_type, service)|
      payload = JSON.parse(fixtures_dir.join(filename).read)

      expect(payload.fetch("timestamp")).to eq("REPLACED_AT_SEND_TIME")
      expect(payload.dig("exception", "values", 0, "type")).to eq(exception_type)
      expect(payload.dig("tags", "service")).to eq(service)
    end
  end

  it "keeps the rate-limit fixture intentionally thin for instrumentation scoring" do
    payload = JSON.parse(fixtures_dir.join("rate_limit_thin.json").read)

    expect(payload).not_to have_key("contexts")
    expect(payload).not_to have_key("breadcrumbs")
    expect(payload.fetch("tags").keys).to contain_exactly("service", "environment")
  end

  it "dry-runs one requested alert with a fresh event id and timestamp" do
    stdout, stderr, status = run_script("--dsn", dsn, "--alert", "db-pool", "--dry-run")

    expect(status).to be_success, stderr
    envelopes = stdout.lines.grep(/^Payload: /).map { |line| JSON.parse(line.delete_prefix("Payload: ")) }
    expect(envelopes.length).to eq(1)
    payload = envelopes.first
    expect(payload.fetch("event_id")).to match(/\A[0-9a-f]{32}\z/)
    expect(payload.fetch("timestamp")).to match(/\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z/)
    expect(payload.dig("exception", "values", 0, "type")).to eq("ActiveRecord::ConnectionTimeoutError")
  end

  it "supports count and emits unique event ids for every generated payload" do
    stdout, stderr, status = run_script("--dsn", dsn, "--alert", "db-pool", "--count", "3", "--dry-run")

    expect(status).to be_success, stderr
    event_ids = stdout.lines.grep(/^Payload: /).map { |line| JSON.parse(line.delete_prefix("Payload: ")).fetch("event_id") }
    expect(event_ids.length).to eq(3)
    expect(event_ids.uniq.length).to eq(3)
  end

  it "constructs Sentry store curl requests from the DSN when not in dry-run mode" do
    fake_curl = Dir.mktmpdir do |dir|
      path = File.join(dir, "curl")
      File.write(path, <<~SH)
        #!/usr/bin/env bash
        printf '%s\n' "$@" >> "#{File.join(dir, "curl.args")}"
        exit 0
      SH
      File.chmod(0o755, path)
      stdout, stderr, status = run_script("--dsn", dsn, "--alert", "null-ref", env: { "PATH" => "#{dir}:#{ENV.fetch("PATH")}" })
      [stdout, stderr, status, File.read(File.join(dir, "curl.args"))]
    end

    stdout, stderr, status, curl_args = fake_curl
    expect(status).to be_success, stderr
    expect(stdout).to include("Sent null-ref")
    expect(curl_args).to include("https://sentry.io/api/12345/store/")
    expect(curl_args).to include("X-Sentry-Auth: Sentry sentry_version=7, sentry_key=public-key")
  end

  it "requires a DSN outside dry-run mode" do
    _stdout, stderr, status = run_script("--alert", "db-pool", env: { "SENTRY_DSN" => "" })

    expect(status).not_to be_success
    expect(stderr).to include("SENTRY_DSN")
  end
end
