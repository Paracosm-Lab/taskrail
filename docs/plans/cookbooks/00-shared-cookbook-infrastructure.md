# Shared Cookbook Infrastructure Implementation Plan

> **For Hermes:** Use subagent-driven-development skill to implement this plan task-by-task.

**Goal:** Build the shared `cookbooks/` directory, fake Docker Compose services, README/run instructions, and verification guardrails that every StupidClaw cookbook example can reuse.

**Architecture:** Add a repo-root `cookbooks/` tree that is intentionally separate from production Rails config but easy for queue YAML to reference with Rails-root-relative paths. The shared infrastructure provides fake HTTP/log/worker/monitoring/staging services through one Compose file plus small deterministic scripts, and cookbook-specific implementations add only their own queue YAML, prompts, predicates, and fixture apps. Specs lock down portable queue prompt resolution and forbid absolute checkout paths.

**Tech Stack:** Rails 8.0.5, RSpec, YAML, Docker Compose, Ruby stdlib WEBrick/JSON, repo-root-relative `file://` prompts resolved by `db/seeds.rb`.

---

## Scope

Implement only shared infrastructure in this slice. Do not implement any individual cookbook queue such as `test_backfill`, `error_handling_audit`, or `chaos_monkey` beyond shared manifests/placeholders that make their later plans consistent.

Shared infrastructure should create these committed artifacts:

```text
cookbooks/
  README.md
  docker-compose.yml
  .env.example
  fake_services/
    README.md
    fake_service.rb
  fixtures/
    README.md
    apps/
      .keep
  queues/
    README.md
  prompts/
    README.md
  runbooks/
    README.md
```

If a later cookbook needs additional fixture content, it adds that content under `cookbooks/fixtures/apps/<cookbook_slug>/` in its own task.

## Directory conventions

- `cookbooks/queues/<slug>.yml`: cookbook queue YAML examples. These may be copied or symlinked into `config/queues/` only if a cookbook-specific plan explicitly requires seeding them.
- `cookbooks/prompts/<slug>/<stage>.md`: prompt files referenced by queue YAML using `file://cookbooks/prompts/<slug>/<stage>.md`.
- `cookbooks/fixtures/apps/<slug>/`: small target apps or source trees used by a cookbook. Never use absolute local paths in these fixture files.
- `cookbooks/runbooks/<slug>/`: fake or example operational runbooks used by readiness/chaos examples.
- `cookbooks/fake_services/`: reusable fake service implementation(s) used by Compose services.
- `cookbooks/docker-compose.yml`: shared fake external/staging infrastructure. Cookbook queue YAML should set `adapter_config.compose_file: cookbooks/docker-compose.yml` and omit `working_directory` unless a stage truly needs a different cwd. The adapter defaults `working_directory` to `Rails.root.to_s`.

## Shared fake services

The shared Compose file should define these service names because downstream cookbook specs reference them:

- `fake-sentry`: accepts Sentry-like event POSTs and exposes captured event JSON for polling stages.
- `fake-logs`: accepts and returns structured log entries.
- `fake-api`: generic external API target for docs, error-handling, logging, job, and query examples.
- `fake-worker`: deterministic background worker endpoint for job observability and queue examples.
- `fake-monitoring`: health/metrics/alerts endpoint for readiness and chaos examples.
- `fake-staging-app`: staging target that chaos examples can disrupt safely.

Use one tiny Ruby script, `cookbooks/fake_services/fake_service.rb`, parameterized by `FAKE_SERVICE_NAME` and `FAKE_SERVICE_PORT`. Each Compose service can run the same image/command with a different environment. The first implementation can use `ruby:3.3-alpine` and mount `./fake_services:/app:ro`; no custom Dockerfile is necessary.

Minimum fake service endpoints:

```text
GET  /health       -> { service, status: "ok" }
GET  /metrics      -> { service, requests, events, alerts }
GET  /events       -> { service, events: [...] }
POST /events       -> append JSON body and return { accepted: true, id }
GET  /logs         -> { service, logs: [...] }
POST /logs         -> append JSON body and return { accepted: true, id }
POST /reset        -> clear in-memory events/logs/alerts for deterministic tests
POST /chaos/:mode  -> for fake-staging-app only, toggles degraded/down/ok state
```

Keep the service intentionally fake. It should be deterministic and local-only, not production-grade.

## Implementation tasks

### Task 1: Add a failing spec for the shared cookbook directory contract

**Objective:** Prove the expected `cookbooks/` tree, README, and Compose file must exist before writing them.

**Files:**
- Create: `spec/cookbooks/shared_infrastructure_spec.rb`
- Later create: `cookbooks/README.md`
- Later create: `cookbooks/docker-compose.yml`
- Later create: `cookbooks/.env.example`
- Later create: `cookbooks/fake_services/README.md`
- Later create: `cookbooks/fixtures/README.md`
- Later create: `cookbooks/fixtures/apps/.keep`
- Later create: `cookbooks/queues/README.md`
- Later create: `cookbooks/prompts/README.md`
- Later create: `cookbooks/runbooks/README.md`

**Step 1: Write failing test**

```ruby
# spec/cookbooks/shared_infrastructure_spec.rb
require "rails_helper"
require "yaml"

RSpec.describe "shared cookbook infrastructure" do
  let(:root) { Rails.root.join("cookbooks") }

  it "defines the shared cookbook directory contract" do
    expect(root.join("README.md")).to exist
    expect(root.join("docker-compose.yml")).to exist
    expect(root.join(".env.example")).to exist
    expect(root.join("fake_services", "README.md")).to exist
    expect(root.join("fake_services", "fake_service.rb")).to exist
    expect(root.join("fixtures", "README.md")).to exist
    expect(root.join("fixtures", "apps", ".keep")).to exist
    expect(root.join("queues", "README.md")).to exist
    expect(root.join("prompts", "README.md")).to exist
    expect(root.join("runbooks", "README.md")).to exist
  end
end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb
```

Expected: FAIL because `cookbooks/README.md` and the rest of the contract do not exist.

### Task 2: Create the root cookbook documentation skeleton

**Objective:** Establish the directory conventions before adding executable fake services.

**Files:**
- Create: `cookbooks/README.md`
- Create: `cookbooks/.env.example`
- Create: `cookbooks/fixtures/README.md`
- Create: `cookbooks/fixtures/apps/.keep`
- Create: `cookbooks/queues/README.md`
- Create: `cookbooks/prompts/README.md`
- Create: `cookbooks/runbooks/README.md`
- Create: `cookbooks/fake_services/README.md`

**Step 1: Write minimal documentation content**

`cookbooks/README.md` must include:

```markdown
# StupidClaw Cookbooks

Cookbooks are executable examples for StupidClaw queues. Shared infrastructure lives here so each cookbook can focus on its queue, prompts, predicates, and fixture app instead of rebuilding fake services.

## Layout

- `docker-compose.yml` provides shared fake services.
- `queues/` contains cookbook queue YAML examples.
- `prompts/<cookbook_slug>/` contains prompt files referenced by queue YAML with `file://cookbooks/prompts/<cookbook_slug>/<stage>.md`.
- `fixtures/apps/<cookbook_slug>/` contains small target apps or source trees.
- `runbooks/<cookbook_slug>/` contains fake runbooks used by operations/chaos/readiness examples.
- `fake_services/` contains the reusable local fake service script.

## Running shared fake services

```bash
docker compose -f cookbooks/docker-compose.yml up --build
```

Reset a fake service between scenarios:

```bash
curl -s -X POST http://localhost:4010/reset
```

## Portability rules

- Do not commit absolute checkout paths.
- Use Rails-root-relative `file://cookbooks/prompts/...` prompt references.
- Prefer adapter defaults for `working_directory`; StupidClaw's Docker Compose adapter defaults to `Rails.root.to_s`.
- Cookbook queue YAML may reference `cookbooks/docker-compose.yml` as a Rails-root-relative compose file.
```

`cookbooks/.env.example` must document host ports without requiring real credentials:

```dotenv
FAKE_SENTRY_PORT=4010
FAKE_LOGS_PORT=4011
FAKE_API_PORT=4012
FAKE_WORKER_PORT=4013
FAKE_MONITORING_PORT=4014
FAKE_STAGING_APP_PORT=4015
```

Add short README files in `fixtures/`, `queues/`, `prompts/`, `runbooks/`, and `fake_services/` explaining the conventions from the Scope section.

**Step 2: Verify first spec still fails only on executable service/compose gaps**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb
```

Expected: still FAIL until `docker-compose.yml` and `fake_services/fake_service.rb` are added.

### Task 3: Add a failing spec for Compose service names and portable paths

**Objective:** Lock down the shared fake-service names and prevent absolute checkout paths from entering committed cookbook infra.

**Files:**
- Modify: `spec/cookbooks/shared_infrastructure_spec.rb`
- Later create: `cookbooks/docker-compose.yml`

**Step 1: Add tests**

Append to the spec:

```ruby
  it "defines docker-friendly fake services with Rails-root-relative mounts" do
    compose = YAML.safe_load_file(root.join("docker-compose.yml"))
    services = compose.fetch("services")

    expect(services.keys).to include(
      "fake-sentry",
      "fake-logs",
      "fake-api",
      "fake-worker",
      "fake-monitoring",
      "fake-staging-app"
    )

    serialized = compose.to_yaml
    expect(serialized).to include("./fake_services:/app:ro")
    expect(serialized).not_to include(Rails.root.to_s)
    expect(serialized).not_to include("/Users/")
  end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb
```

Expected: FAIL because `cookbooks/docker-compose.yml` does not exist yet.

### Task 4: Add the shared Docker Compose file

**Objective:** Provide the service names and local-only ports all cookbook queues can reference.

**Files:**
- Create: `cookbooks/docker-compose.yml`

**Step 1: Write minimal Compose content**

```yaml
services:
  fake-sentry:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-sentry
      FAKE_SERVICE_PORT: 4010
    ports:
      - "${FAKE_SENTRY_PORT:-4010}:4010"
    volumes:
      - ./fake_services:/app:ro

  fake-logs:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-logs
      FAKE_SERVICE_PORT: 4011
    ports:
      - "${FAKE_LOGS_PORT:-4011}:4011"
    volumes:
      - ./fake_services:/app:ro

  fake-api:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-api
      FAKE_SERVICE_PORT: 4012
    ports:
      - "${FAKE_API_PORT:-4012}:4012"
    volumes:
      - ./fake_services:/app:ro

  fake-worker:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-worker
      FAKE_SERVICE_PORT: 4013
    ports:
      - "${FAKE_WORKER_PORT:-4013}:4013"
    volumes:
      - ./fake_services:/app:ro

  fake-monitoring:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-monitoring
      FAKE_SERVICE_PORT: 4014
    ports:
      - "${FAKE_MONITORING_PORT:-4014}:4014"
    volumes:
      - ./fake_services:/app:ro

  fake-staging-app:
    image: ruby:3.3-alpine
    working_dir: /app
    command: ruby fake_service.rb
    environment:
      FAKE_SERVICE_NAME: fake-staging-app
      FAKE_SERVICE_PORT: 4015
    ports:
      - "${FAKE_STAGING_APP_PORT:-4015}:4015"
    volumes:
      - ./fake_services:/app:ro
```

Do not add a repo-root `working_directory` to any queue YAML as part of this task. Compose relative paths resolve from the Compose file directory, and the StupidClaw adapter already runs from `Rails.root`.

**Step 2: Verify compose parsing test still fails only for missing `fake_service.rb`**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb
```

Expected: FAIL because `cookbooks/fake_services/fake_service.rb` is not present yet; the Compose service-name test should now pass.

### Task 5: Add a failing spec for fake service behavior

**Objective:** Define the deterministic HTTP contract before implementing the fake service.

**Files:**
- Create: `spec/cookbooks/fake_service_spec.rb`
- Later create: `cookbooks/fake_services/fake_service.rb`

**Step 1: Write tests around a helper method, not a long-running server**

The fake service script should expose a small app object that tests can call without binding ports. Use Rack-like env hashes or plain helper methods. Keep the exact interface simple. Example spec shape:

```ruby
require "rails_helper"
require "stringio"
require Rails.root.join("cookbooks/fake_services/fake_service")

RSpec.describe Cookbooks::FakeService do
  subject(:service) { described_class.new("fake-sentry") }

  it "reports healthy status" do
    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/health")

    expect(status).to eq(200)
    expect(JSON.parse(body.join)).to include("service" => "fake-sentry", "status" => "ok")
  end

  it "stores and resets events deterministically" do
    event_body = StringIO.new({ message: "boom" }.to_json)
    post_env = { "REQUEST_METHOD" => "POST", "PATH_INFO" => "/events", "rack.input" => event_body }
    service.call(post_env)

    status, _headers, body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/events")
    expect(status).to eq(200)
    expect(JSON.parse(body.join).fetch("events")).to include(hash_including("message" => "boom"))

    service.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/reset", "rack.input" => StringIO.new("{}"))
    _status, _headers, reset_body = service.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/events")
    expect(JSON.parse(reset_body.join).fetch("events")).to eq([])
  end

  it "can toggle chaos state for the fake staging app" do
    staging = described_class.new("fake-staging-app")
    staging.call("REQUEST_METHOD" => "POST", "PATH_INFO" => "/chaos/down", "rack.input" => StringIO.new("{}"))

    status, _headers, body = staging.call("REQUEST_METHOD" => "GET", "PATH_INFO" => "/health")
    expect(status).to eq(503)
    expect(JSON.parse(body.join)).to include("service" => "fake-staging-app", "status" => "down")
  end
end
```

**Step 2: Verify RED**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/fake_service_spec.rb
```

Expected: FAIL because `cookbooks/fake_services/fake_service.rb` does not exist.

### Task 6: Implement the deterministic fake service script

**Objective:** Provide one reusable local HTTP fake that can run in Docker and in unit specs.

**Files:**
- Create: `cookbooks/fake_services/fake_service.rb`

**Step 1: Implement minimal code**

Implementation requirements:

- Define `Cookbooks::FakeService` with `#call(env)` for tests.
- Use only Ruby stdlib (`json`, `webrick`, `stringio` if needed). Do not add gems.
- Store events/logs/alerts in instance variables so specs are isolated.
- Return JSON content type for every response.
- When executed directly (`if $PROGRAM_NAME == __FILE__`), start WEBrick on `ENV.fetch("FAKE_SERVICE_PORT", "4010")` and mount the app.
- `/health` should return HTTP 503 only when state is `down`; otherwise 200.
- `/chaos/degraded`, `/chaos/down`, and `/chaos/ok` should update state for `fake-staging-app` and return a JSON payload documenting the mode.

**Step 2: Verify GREEN for fake service spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/fake_service_spec.rb
```

Expected: PASS.

### Task 7: Add shared queue/prompt portability expectations

**Objective:** Make cookbook-specific tasks prove their queue YAML and prompt files are portable before adding each cookbook.

**Files:**
- Modify: `spec/cookbooks/shared_infrastructure_spec.rb`
- Future cookbook tasks will add `config/queues/cookbook_*.yml` or `cookbooks/queues/*.yml` plus prompt files.

**Step 1: Add helper tests that are safe with no cookbook queues yet**

Append:

```ruby
  it "documents portable queue YAML expectations for cookbook-specific specs" do
    readme = root.join("README.md").read

    expect(readme).to include("file://cookbooks/prompts/")
    expect(readme).to include("Do not commit absolute checkout paths")
    expect(readme).to include("cookbooks/docker-compose.yml")
  end

  it "keeps shared cookbook files free of local absolute checkout paths" do
    shared_files = Dir[root.join("**", "*")].select { |path| File.file?(path) }
    offenders = shared_files.select do |path|
      content = File.read(path)
      content.include?(Rails.root.to_s) || content.include?("/Users/")
    end

    expect(offenders).to eq([])
  end
```

Future cookbook-specific seed specs should then follow this pattern:

```ruby
it "seeds the <slug> cookbook queue with resolved portable prompt files" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "<slug>")
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)

  queue.stage_configs.each do |stage_config|
    expect(stage_config.agent_prompt).not_to start_with("file://")
    expect(stage_config.agent_prompt).not_to include(Rails.root.to_s)
    expect(stage_config.agent_prompt).not_to include("/Users/")
  end
end
```

Future cookbook-specific YAML portability specs should also inspect YAML before seeding:

```ruby
yaml = YAML.safe_load_file(Rails.root.join("config/queues/<slug>.yml"))
serialized = yaml.to_yaml
expect(serialized).not_to include(Rails.root.to_s)
expect(serialized).not_to include("/Users/")
yaml.fetch("stage_configs").each_value do |stage|
  prompt = stage["agent_prompt"]
  next unless prompt.to_s.start_with?("file://")

  expect(Rails.root.join(prompt.delete_prefix("file://"))).to exist
end
```

**Step 2: Verify GREEN for shared infrastructure spec**

Run:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb
```

Expected: PASS once documentation, compose, and fake service exist.

### Task 8: Validate Docker Compose config

**Objective:** Confirm Docker can parse the shared Compose file without starting long-running services in the test suite.

**Files:**
- No new files unless Compose validation exposes a typo.

**Step 1: Run config validation**

Run:

```bash
docker compose -f cookbooks/docker-compose.yml config --quiet
```

Expected: exit 0.

If Docker is unavailable on the runner, do not fake success. Record the command and the Docker availability error in the implementation handoff, then rely on the YAML/RSpec validation until Docker is available.

### Task 9: Run focused and seed-related regression specs

**Objective:** Verify the new shared infra does not break existing queue seed prompt resolution.

**Files:**
- No new files unless tests reveal a real issue.

**Step 1: Run focused specs**

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec \
  spec/cookbooks/shared_infrastructure_spec.rb \
  spec/cookbooks/fake_service_spec.rb \
  spec/models/work_queue_seed_spec.rb
```

Expected: PASS.

**Step 2: Optional broader check**

If the focused suite is clean and time permits:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec
```

Expected: PASS. If the full suite is slow or has unrelated failures, keep the focused suite results in the handoff and name any unrelated failure clearly.

### Task 10: Commit the shared infrastructure implementation

**Objective:** Commit only the shared infrastructure files for this slice.

**Files expected in this commit:**

```text
cookbooks/.env.example
cookbooks/README.md
cookbooks/docker-compose.yml
cookbooks/fake_services/README.md
cookbooks/fake_services/fake_service.rb
cookbooks/fixtures/README.md
cookbooks/fixtures/apps/.keep
cookbooks/prompts/README.md
cookbooks/queues/README.md
cookbooks/runbooks/README.md
spec/cookbooks/fake_service_spec.rb
spec/cookbooks/shared_infrastructure_spec.rb
```

**Step 1: Check status**

```bash
git status --short
```

Expected: only the above files are modified/untracked for this implementation task, except pre-existing untracked docs/specs from other tasks. Do not stage unrelated files.

**Step 2: Stage only shared infrastructure files**

```bash
git add \
  cookbooks/.env.example \
  cookbooks/README.md \
  cookbooks/docker-compose.yml \
  cookbooks/fake_services/README.md \
  cookbooks/fake_services/fake_service.rb \
  cookbooks/fixtures/README.md \
  cookbooks/fixtures/apps/.keep \
  cookbooks/prompts/README.md \
  cookbooks/queues/README.md \
  cookbooks/runbooks/README.md \
  spec/cookbooks/fake_service_spec.rb \
  spec/cookbooks/shared_infrastructure_spec.rb
```

**Step 3: Commit**

```bash
git commit -m "feat: add shared cookbook infrastructure"
```

Record the commit hash in the kanban completion summary.

## How cookbook-specific plans plug in

Every later cookbook implementation plan should:

1. Depend on the shared infrastructure implementation task `t_c7c986d9`.
2. Place prompts under `cookbooks/prompts/<slug>/` and reference them with `file://cookbooks/prompts/<slug>/<stage>.md`.
3. Add queue YAML either under `config/queues/<slug>.yml` if it should seed automatically, or under `cookbooks/queues/<slug>.yml` if it is documentation/example-only.
4. Use `adapter_config.compose_file: cookbooks/docker-compose.yml` for Docker-backed stages and omit `working_directory` unless the adapter must run somewhere other than `Rails.root`.
5. Add fixture apps under `cookbooks/fixtures/apps/<slug>/` rather than `test/fixtures/apps/` unless a specific Rails spec requires `spec/fixtures` or `test/fixtures` conventions.
6. Add seed specs that verify all stage configs exist, `file://` prompts are resolved, prompt files exist, and no queued config contains absolute local paths.
7. Add predicate specs before predicate implementation, using actionable `PredicateResult` evidence and failure reasons.
8. Commit each cookbook slice separately after focused tests pass.

Known dependent implementation tasks:

- `t_c7c986d9` — Implement shared cookbook infrastructure.
- `t_baf6a8c9` — Implement cookbook 01-test-coverage-backfill.
- `t_bb9c7bb7` — Implement cookbook 02-error-handling-audit.
- `t_854b35a1` — Implement cookbook 03-api-documentation-sync.
- `t_6aae6e44` — Implement cookbook 05-dead-code-removal.
- `t_f8681cc8` — Implement cookbook 06-logging-consistency-audit.
- `t_631049ca` — Implement cookbook 07-database-query-health.
- `t_3a82b65a` — Implement cookbook 09-chaos-monkey / chaos-response.
- `t_0933b94c` — Implement cookbook 11-incident-readiness-scoring.
- `t_dfade4bf` — Implement cookbook 12-background-job-observability.

## Verification checklist for the shared infrastructure implementation

Before completing `t_c7c986d9`, verify:

- [ ] `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/shared_infrastructure_spec.rb` passes.
- [ ] `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/cookbooks/fake_service_spec.rb` passes.
- [ ] `PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/models/work_queue_seed_spec.rb` passes.
- [ ] `docker compose -f cookbooks/docker-compose.yml config --quiet` passes or Docker-unavailable error is recorded.
- [ ] `git status --short` confirms unrelated pre-existing untracked docs/specs were not staged.
- [ ] Commit hash is captured.

## Commit expectation for this planning task

This planning task should commit only this plan file:

```bash
git add docs/plans/cookbooks/00-shared-cookbook-infrastructure.md
git commit -m "docs: plan shared cookbook infrastructure"
```
