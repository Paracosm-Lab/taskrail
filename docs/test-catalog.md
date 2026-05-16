# Test Catalog

This catalog records the automated and live E2E layers used to qualify Taskrail. The test plan defines release policy; this file records the practical test inventory and the latest known run evidence.

## Latest Full Pass

Latest local E2E sweep: 2026-05-15 local time.

| Layer | Command or flow | Latest result |
| --- | --- | --- |
| Cookbook E2E suite | `bundle exec rspec spec/e2e` | Passed: `56 examples, 0 failures` |
| Full Ruby suite | `bundle exec rspec` | Passed: `655 examples, 0 failures` |
| TUI suite | `cd tui && npm test` | Passed: `7 tests, 0 failures` |
| Brakeman | `bin/brakeman --no-pager --skip-files cookbooks/,test/fixtures/,spec/fixtures/ -x EOLRuby` | Passed: no warnings |
| Gitleaks | `gitleaks detect --source . --config .gitleaks.toml --verbose --no-banner` | Passed: no leaks, 213 commits scanned |
| Focused hardening specs | `bundle exec rspec spec/requests/security_spec.rb spec/requests/api/v1/api_hardening_spec.rb spec/db/database_hardening_spec.rb` | Passed: `14 examples, 0 failures` |
| RuboCop | `bin/rubocop --fail-level warning --except Layout` | Gate passed; reported convention-only autocorrectable offenses |

## Authentication And API

| Coverage | How to run | Notes |
| --- | --- | --- |
| Devise browser login enforcement | `bundle exec rspec spec/requests/devise_authentication_spec.rb` | Verifies unauthenticated web routes redirect and signed-in users can access queues/work items. |
| PAT creation and authorization | `bundle exec rspec spec/requests/personal_access_tokens_spec.rb` | Covers real `POST /users/sign_in`, `POST /personal_access_tokens`, one-time raw token display, scopes, revocation, and API auth. |
| Authenticated API smoke | Start Rails, create PAT, call `/api/v1/*` with `Authorization: Bearer <token>` | Latest live pass covered queues, stages, work item list/show, costs, digest, and SSE stream snapshot. |
| CLI against PAT-backed API | `TASKRAIL_API_URL=http://127.0.0.1:<port> TASKRAIL_API_TOKEN=<pat> bin/taskrail ...` | Latest live pass covered `doctor`, `dashboard --queue development`, `digest --since 24h`, and `costs`. |

## Adapter And Workflow Matrix

| Layer | Coverage | Latest evidence |
| --- | --- | --- |
| Fake workflow | `bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb` | Included in full Ruby suite. |
| Shell workflow | `bundle exec rspec spec/services/engine/shell_script_workflow_integration_spec.rb` | Included in full Ruby suite. |
| Inline Claude workflow | `bundle exec rspec spec/services/engine/inline_claude_workflow_integration_spec.rb` | Included in full Ruby suite with stubbed runner behavior. |
| Codex workflow | `bundle exec rspec spec/services/engine/codex_workflow_integration_spec.rb` | Included in full Ruby suite with Codex result normalization coverage. |
| Docker Compose adapter | `bundle exec rspec spec/adapters/adapters/docker_compose_adapter_spec.rb` | Included in full Ruby suite. Live fixture smoke also passed after WEBrick setup fix. |
| Real Claude adapter smoke | Rails runner with `Adapters::InlineClaudeAdapter` and authenticated `claude` CLI | Passed with expected response and persisted `agent_report` artifact. |
| Real Codex adapter smoke | Rails runner with `Adapters::CodexAdapter` and current `codex exec --json` | Passed after JSONL compatibility and final-message artifact parsing fixes. |

## Live E2E Runs

These runs exercise real local services and CLIs beyond unit/request specs.

| Scenario | Flow | Latest result |
| --- | --- | --- |
| Authenticated web/API/CLI smoke | Rails on `127.0.0.1:3334`, local Postgres, admin user, PAT-backed API and CLI calls | Passed. |
| Fake queue live workflow | API-created `development` item, repeated `Engine::Runner` ticks | Reached `done/completed`. |
| Shell queue live workflow | API-created shell-backed item, repeated engine ticks | Reached `done/completed`. |
| Docker Compose fixture | Fake services from `cookbooks/docker-compose.yml`, health checks, adapter execution | Passed; compose stack was torn down. |
| Safe real-agent workflow | Temporary queue with Claude intake, Codex read-only build, shell validation, Claude review | Work item `f6574f3e-4df2-4d18-acb2-9ca86333a53d` reached `done/completed`; artifacts included `agent_report`, `branch`, `test_results`, `lint`, and `coverage`. |
| Full feature-development workflow | Disposable workspace `/tmp/taskrail-workspaces/feature-development-full`, real Codex edit/build, shell validation, Claude review | Work item `7bbd368c-6204-4f4b-a046-31c9927c9038` reached `done/completed`; fixture spec passed with `1 example, 0 failures`. |
| Verified branch-artifact feature workflow | Disposable workspace `/tmp/taskrail-workspaces/feature-development-verified-2`, real Codex edit/build with normal workspace Git writes, shell validation, Claude review | Work item `b7bf066d-f443-40a8-b6b3-7aff2c7c8ce7` reached `done/completed`; `branch_created` verified branch `taskrail/b7bf066d-calendar-export-2` at commit `397fc786b1e36d16760b2a83eccc532938076813` in the workspace Git repository. |
| Production image smoke | `docker build -t taskrail:e2e-local .`, isolated Postgres container, app container in `RAILS_ENV=production` | Image built, `/health` returned 200, unauthenticated API returned 401, PAT-backed API worked, `bin/smoke-prod` passed, and a container-created `development` work item reached `done/completed`. |
| Web/API/engine user journey | `bundle exec rspec spec/e2e/web_user_journey_spec.rb` | Passed. Covers real Devise session login, web PAT creation, PAT-authenticated API work item creation, engine advancement through the fake adapter, and web UI verification of the completed item. |
| Seeded queue contract matrix | `bundle exec rspec spec/e2e/seeded_queue_contracts_spec.rb` | Passed: `24 examples, 0 failures`. Loads every queue YAML, forces deterministic fake adapters, creates a work item per queue, and verifies each queue reaches `done/completed` through its configured stages and predicates. |

## CI Evidence

| PR | Purpose | Relevant checks |
| --- | --- | --- |
| #6 | Support current Codex JSONL output | Push and PR Woodpecker checks passed. |
| #7 | Support structured agent workflow outputs | Push and PR Woodpecker checks passed. |
| #8 | Document branch artifact verification follow-up | Push and PR Woodpecker checks passed. |
| #10 | Verify branch artifacts against workspace Git | Push and PR Woodpecker checks passed; push pipeline `50` ran `sbom_upload` and the SBOM was verified on the QNAP NAS. |

`pull_request_closed` pipelines have repeatedly failed at the Woodpecker Postgres service with exit `137`. Those failures happen after merge and before app steps; they are tracked as CI infrastructure noise unless they start affecting push or PR gates.

## Known Notes

- Branch artifact verification is now enforced for workspace-backed stages. The original alternate `.taskrail-git` finding and resolution are recorded in `docs/specs/2026-05-15-blockers.md`.
- RuboCop currently reports convention-only autocorrectable offenses while still passing under `--fail-level warning`. Treat cleanup as separate from E2E readiness unless the fail level changes.
