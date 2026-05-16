# Test Plan

This plan keeps Taskrail testable without manual clicking. Every release candidate should pass the automated gates below before it is considered ready to merge or deploy.

For the concrete inventory of E2E layers, latest run evidence, live smoke scenarios, and known follow-ups, see [Test Catalog](./test-catalog.md).

## Scope

The plan covers:

- Web authentication and session handling.
- Personal access token creation, one-time token display, revocation, and API authorization.
- API authorization for read, write, and admin paths.
- Engine execution with fake, shell, Claude, Codex, and Docker Compose adapters.
- Dashboard stream payloads and TUI compatibility.
- CI gates for lint, security, Ruby specs, TUI tests, image build, and SBOM generation.

## Required Automated Gates

Run the full Ruby and TUI suites:

```bash
bundle exec rspec
cd tui && npm test
```

In CI, Woodpecker must complete these gates:

- `lint`
- `secret-scan`
- `security_scan`
- `test_ruby`
- `test_tui`
- `test`
- `docker_build_pr` on pull requests
- `docker_build_main` and `deploy_main` on pushes to `main`

`sbom` and `sbom_upload` are allowed to fail without blocking the release, but failures should be investigated because they affect artifact traceability.

## Authentication And PAT Automation

Authentication and token issuance must be tested through automated request specs, not manual browser checks.

Required specs:

```bash
bundle exec rspec spec/requests/devise_authentication_spec.rb spec/requests/personal_access_tokens_spec.rb
```

Coverage requirements:

- An unauthenticated web request redirects to the Devise sign-in page.
- A valid user can log in through the real Devise session endpoint.
- A logged-in session can create a PAT through `POST /personal_access_tokens`.
- The raw `trpat_` token is shown only immediately after creation.
- Later PAT index requests show the token prefix but not the raw token.
- Users can revoke only their own tokens.
- Read-scoped PATs can call read API endpoints.
- Read-only PATs cannot create work items.
- Write-scoped PATs can create work items.
- Admin-scoped PATs work for admin endpoints only when owned by admin users.
- Admin endpoints remain closed without an admin token or admin PAT.

The login-plus-PAT test is `spec/requests/personal_access_tokens_spec.rb` and must exercise this real flow:

```text
POST /users/sign_in
POST /personal_access_tokens
GET  /personal_access_tokens
```

## Local Smoke Sequence

Prepare the app:

```bash
docker compose up -d postgres
bin/rails db:prepare db:seed
EMAIL=tester@example.com PASSWORD='change-me' bin/rails taskrail:create_admin
```

Start the server:

```bash
bin/rails server
```

Automated smoke tests should use request specs or CLI/API calls with a PAT. Manual browser confirmation is optional and should not be treated as a release gate.

Create a PAT through the web flow, then run API checks:

```bash
export TASKRAIL_API_URL=http://localhost:3000
export TASKRAIL_API_TOKEN=<created-pat>
bin/taskrail queues
bin/taskrail stages development
bin/taskrail submit --queue development --title "Fake adapter smoke" --spec ./README.md
```

Run one engine tick:

```bash
bin/rails runner 'Engine::Runner.new.call'
```

Confirm the item moves forward:

```bash
bin/taskrail list --queue development
```

## Adapter Test Matrix

Run adapters from lowest dependency to highest dependency.

| Queue | Adapter coverage | Gate |
| --- | --- | --- |
| `development` | `fake` | Must pass in all environments. |
| `development-shell` | `shell_script` plus fake stages | Must pass locally and in CI-compatible shells. |
| `development-claude` | `inline_claude` plus shell test stage | Requires authenticated `claude` CLI. |
| `development-codex` | `inline_claude`, `codex`, shell test stage | Requires authenticated Claude and Codex CLIs. |
| Docker Compose cookbook queues | `docker_compose` | Requires Docker Compose and fixture availability. |

Automated checks:

```bash
bundle exec rspec spec/services/engine/fake_workflow_integration_spec.rb
bundle exec rspec spec/services/engine/shell_script_workflow_integration_spec.rb
bundle exec rspec spec/services/engine/inline_claude_workflow_integration_spec.rb
bundle exec rspec spec/services/engine/codex_workflow_integration_spec.rb
bundle exec rspec spec/adapters/adapters/docker_compose_adapter_spec.rb
```

The fake and shell paths are required release gates. Claude, Codex, and Docker Compose paths are required when the target environment advertises those agents as available.

## Dashboard And Stream Automation

Run dashboard payload and TUI tests:

```bash
bundle exec rspec spec/services/dashboard_payload_builder_spec.rb spec/requests/api/v1/workflow_api_spec.rb
cd tui && npm test
```

Coverage requirements:

- Stream responses include bounded work item snapshots.
- Stream cursors and heartbeats do not break existing dashboard clients.
- The TUI ignores heartbeat-only payloads.
- API authentication is enforced for stream endpoints in production-like configuration.

## Security And Hardening Automation

Run:

```bash
bin/rubocop --fail-level warning --except Layout
bin/brakeman --no-pager --skip-files cookbooks/,test/fixtures/,spec/fixtures/ -x EOLRuby
gitleaks detect --source . --config .gitleaks.toml --verbose --no-banner
bundle exec rspec spec/requests/security_spec.rb spec/requests/api/v1/api_hardening_spec.rb spec/db/database_hardening_spec.rb
```

Coverage requirements:

- Sensitive values are redacted from traces and logs.
- Rate limiting distinguishes authenticated and unauthenticated callers.
- API requests without valid credentials fail when authentication is required.
- Database constraints and indexes protect core workflow records.

## Exit Criteria

A release candidate is testable and ready for PR review when:

- Full Ruby and TUI suites pass.
- Login and PAT creation are covered by automated request specs.
- Fake and shell adapter workflows pass.
- External adapter tests are either passing or explicitly marked unavailable because their CLI/container dependency is absent.
- Woodpecker is green for the PR.
- Any non-blocking failures are documented in `docs/specs/2026-05-15-blockers.md` with the exact command, failure, and next step.
