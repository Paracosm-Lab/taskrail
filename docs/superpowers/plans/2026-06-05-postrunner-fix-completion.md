# Postrunner-Fix Pipeline Completion Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close five gaps in the `postrunner-fix` pipeline so it can run end-to-end: fix the ignored `model_override`, wire production secrets, update both agent prompts, and add a db:seed post-deploy hook.

**Architecture:** All changes are configuration-only — no new Ruby classes or adapters. We edit `config/queues/postrunner_fix.yml`, `config/deploy.yml`, `.kamal/secrets`, and create `.kamal/hooks/post-deploy`. Each change is independently testable via the existing seed spec pattern.

**Tech Stack:** Rails 8 / Ruby 3.3, Kamal 2, Solid Queue, RSpec

---

## File Map

| File | Change |
|------|--------|
| `config/queues/postrunner_fix.yml` | Move `model_override` to stage level; rewrite `fix` and `review` prompts |
| `config/deploy.yml` | Add `GH_TOKEN` and `LINEAR_API_KEY` to `env.secret` |
| `.kamal/secrets` | Add 5 missing entries: `GH_TOKEN`, `LINEAR_API_KEY`, `TASKRAIL_SERVICE_TOKEN`, `TASKRAIL_ADMIN_TOKEN`, `GITHUB_WEBHOOK_SECRET` |
| `.kamal/hooks/post-deploy` | Create executable hook that runs `bin/rails db:seed` inside the container |
| `spec/models/work_queue_seed_spec.rb` | Add postrunner-fix seed spec |

---

## Task 1: Fix `model_override` in `postrunner_fix.yml`

`AssignmentBuilder` reads `stage_config.model_override` (a dedicated DB column), **not** `adapter_config["model"]`. The `review` stage currently sets `model: claude-opus-4-6` inside `adapter_config`, which is silently ignored. Seeds propagate `config["model_override"]` to the column at `db/seeds.rb:28`.

**Files:**
- Modify: `config/queues/postrunner_fix.yml:65-88`
- Test: `spec/models/work_queue_seed_spec.rb`

- [ ] **Step 1: Write the failing seed spec**

Open `spec/models/work_queue_seed_spec.rb` and add the following test at the bottom, before the final `end`.

Note: stages without a `completion_criteria:` key in the YAML (`open_pr`, `await_ci`, `merge`, `done`) will seed fine — `seeds.rb` passes `config.fetch("completion_criteria", [])` so they get an empty array, which is valid. You don't need to assert on those stages.

```ruby
it "seeds the postrunner-fix queue with correct adapter types and model_override" do
  load Rails.root.join("db/seeds.rb")

  queue = WorkQueue.find_by!(slug: "postrunner-fix")
  expect(queue.stages).to eq(%w[fix open_pr await_ci review merge done])
  expect(queue.stage_configs.pluck(:stage_name)).to contain_exactly(*queue.stages)

  fix = queue.stage_configs.find_by!(stage_name: "fix")
  expect(fix.adapter_type).to eq("codex")
  expect(fix.completion_criteria).to eq(["branch_created"])
  expect(fix.agent_prompt).to include("repository")
  expect(fix.agent_prompt).to include("git checkout -b")
  expect(fix.agent_prompt).to include("git push origin HEAD")
  expect(fix.agent_prompt).to include("branch name you pushed")

  review = queue.stage_configs.find_by!(stage_name: "review")
  expect(review.adapter_type).to eq("inline_claude")
  expect(review.model_override).to eq("claude-opus-4-6")
  expect(review.adapter_config).not_to have_key("model")
  expect(review.completion_criteria).to eq(["review_verdict"])
  expect(review.agent_prompt).to include("upstream_artifacts")
  expect(review.agent_prompt).to include("gh pr diff")
  expect(review.agent_prompt).to include('{"verdict": "approved"}')
  expect(review.agent_prompt).to include("request_changes")
end
```

This single test covers all five YAML changes — write it once, then implement Tasks 1-3 to make it go green incrementally.

- [ ] **Step 2: Run the test to confirm it fails**

```bash
cd /path/to/taskrail/app
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: FAIL — `review.model_override` is `nil` because the key is currently inside `adapter_config`.

- [ ] **Step 3: Fix `postrunner_fix.yml` — move `model_override` to stage level**

In `config/queues/postrunner_fix.yml`, the `review` stage currently looks like:

```yaml
  review:
    adapter_type: inline_claude
    max_retries: 0
    timeout_seconds: 120
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    completion_criteria:
      - review_verdict
    agent_prompt: |
      ...
    adapter_config:
      command: claude
      args:
        - --print
      model: claude-opus-4-6          # ← wrong place
      output_artifact_kind: review_report
```

Change it to:

```yaml
  review:
    adapter_type: inline_claude
    model_override: claude-opus-4-6   # ← correct place
    max_retries: 0
    timeout_seconds: 120
    escalation_target: block_and_notify
    allowed_skills: []
    forbidden_skills: []
    completion_criteria:
      - review_verdict
    agent_prompt: |
      ...
    adapter_config:
      command: claude
      args:
        - --print
      output_artifact_kind: review_report
```

Remove `model: claude-opus-4-6` from `adapter_config` entirely.

- [ ] **Step 4: Run the test to confirm it passes**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add config/queues/postrunner_fix.yml spec/models/work_queue_seed_spec.rb
git commit -m "fix: move model_override to stage level in postrunner_fix review stage"
```

---

## Task 2: Update `fix` stage prompt

The current `fix` prompt doesn't tell codex to create a branch or push to the remote. `github_pr_create` runs `gh pr create --head <branch>` which requires the branch to exist on the remote. The prompt also needs to direct codex to find the repository from its assignment context (prompts are passed as-is without interpolation).

The test assertions for this task are already in the spec written in Task 1 (`git checkout -b`, `git push origin HEAD`, `repository`, `branch name you pushed`). Run the failing spec before making changes, then implement.

**Files:**
- Modify: `config/queues/postrunner_fix.yml:29-33` (the `fix` stage `agent_prompt`)

- [ ] **Step 1: Run the spec to confirm the `fix` prompt assertions fail**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: FAIL on the `git checkout -b` and `git push origin HEAD` assertions.

- [ ] **Step 2: Replace the `fix` stage `agent_prompt` in `postrunner_fix.yml`**

Replace the current `agent_prompt` under `fix:`:

```yaml
    agent_prompt: |
      You are fixing a CI tool finding. The issue details are in the spec below.
      Clone the repository, read the flagged file, apply the fix, commit to a new branch.
      Branch name format: postrunner/{tool}-{short-description}
      Make the minimal change needed — do not refactor surrounding code.
```

With:

```yaml
    agent_prompt: |
      You are fixing a CI tool finding. Your assignment context is included below. Find the
      `repository` value in the work item tags — it identifies the GitHub repository to fix
      (format: "org/repo").

      Steps:
      1. Clone the repository: git clone https://github.com/<repository> repo && cd repo
         (replace <repository> with the value from your context)
      2. Create a new branch before making any changes:
         git checkout -b postrunner/<tool>-<short-slug>
         (derive tool and short-slug from the finding details in your context)
      3. Read the spec below carefully — it identifies the tool, rule, file, and line.
      4. Apply the minimal fix. Do not refactor surrounding code.
      5. Commit: git commit -am "fix: <short description>"
      6. Push the branch to origin: git push origin HEAD
      7. In your final response, include the branch name you pushed.
```

- [ ] **Step 3: Run the spec to confirm it passes (partially)**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: PASS on all `fix` prompt assertions. The `review` prompt assertions (`upstream_artifacts`, `gh pr diff`) will still fail — that's correct, Task 3 handles those.

- [ ] **Step 4: Commit**

```bash
git add config/queues/postrunner_fix.yml spec/models/work_queue_seed_spec.rb
git commit -m "fix: update postrunner-fix fix stage prompt with clone, branch, and push steps"
```

---

## Task 3: Update `review` stage prompt

The current `review` prompt tells Claude to "read the diff" but doesn't tell it how to fetch one. `inline_claude` runs `claude --print`, which has full tool access and can run shell commands. The prompt needs to direct Claude to find the PR artifact from its assignment context and use `gh pr diff`.

The assertions for this task (`upstream_artifacts`, `gh pr diff`, `{"verdict": "approved"}`, `request_changes`) are already in the spec written in Task 1. They should still be failing after Task 2.

**Files:**
- Modify: `config/queues/postrunner_fix.yml:74-82` (the `review` stage `agent_prompt`)

- [ ] **Step 1: Run the spec to confirm the `review` prompt assertions still fail**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: FAIL on the `upstream_artifacts` and `gh pr diff` assertions.

- [ ] **Step 2: Replace the `review` stage `agent_prompt` in `postrunner_fix.yml`**

Replace:

```yaml
    agent_prompt: |
      You are reviewing a pull request that fixes a CI tool finding.
      Read the diff carefully. Verify:
      1. The fix addresses the specific finding (tool, rule, file from the spec)
      2. The change is minimal and doesn't introduce new issues
      3. No unrelated changes were made
      If the fix is correct, respond with: {"verdict": "approved"}
      If the fix is wrong or incomplete, respond with: {"verdict": "request_changes", "feedback": "explanation"}
```

With:

```yaml
    agent_prompt: |
      You are reviewing a pull request that fixes a CI tool finding. Your assignment context is
      included below. Find the `pull_request` artifact in the `upstream_artifacts` array under
      Context — it contains the PR number and repository.

      First, fetch the diff using those values:
        gh pr diff <pr_number> --repo <repository>

      Then verify:
      1. The fix addresses the specific finding (tool, rule, file, line from the spec)
      2. The change is minimal — no unrelated modifications
      3. No new issues introduced

      Respond with exactly one of:
        {"verdict": "approved"}
        {"verdict": "request_changes", "feedback": "<concise explanation>"}
```

- [ ] **Step 3: Run the spec to confirm it passes**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb -e "postrunner-fix" --format documentation
```

Expected: PASS — all assertions in the test should now be green.

- [ ] **Step 4: Commit**

```bash
git add config/queues/postrunner_fix.yml spec/models/work_queue_seed_spec.rb
git commit -m "fix: update postrunner-fix review stage prompt to fetch diff via gh pr diff"
```

---

## Task 4: Add Kamal production secrets

`GH_TOKEN` and `LINEAR_API_KEY` are required by the GitHub adapters and `LinearPollJob` respectively. They are declared nowhere in the Kamal config today. Three other secrets (`TASKRAIL_SERVICE_TOKEN`, `TASKRAIL_ADMIN_TOKEN`, `GITHUB_WEBHOOK_SECRET`) are declared in `config/deploy.yml` under `env.secret` but missing from `.kamal/secrets`.

There are no automated tests for this task — it is a config-only change. Correctness is verified by a post-deploy manual check.

**Files:**
- Modify: `config/deploy.yml:44-49`
- Modify: `.kamal/secrets`

- [ ] **Step 1: Add `GH_TOKEN` and `LINEAR_API_KEY` to `config/deploy.yml`**

The current `env.secret` block in `config/deploy.yml`:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - TASKRAIL_DATABASE_PASSWORD
    - TASKRAIL_SERVICE_TOKEN
    - TASKRAIL_ADMIN_TOKEN
    - GITHUB_WEBHOOK_SECRET
```

Add the two new entries:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - TASKRAIL_DATABASE_PASSWORD
    - TASKRAIL_SERVICE_TOKEN
    - TASKRAIL_ADMIN_TOKEN
    - GITHUB_WEBHOOK_SECRET
    - GH_TOKEN
    - LINEAR_API_KEY
```

- [ ] **Step 2: Add all five missing entries to `.kamal/secrets`**

The current `.kamal/secrets` ends with:

```
KAMAL_REGISTRY_PASSWORD=$KAMAL_REGISTRY_PASSWORD
RAILS_MASTER_KEY=$(cat config/master.key)
TASKRAIL_DATABASE_PASSWORD=$TASKRAIL_DATABASE_PASSWORD
```

Append the five entries that pull from ENV (same pattern as `TASKRAIL_DATABASE_PASSWORD`):

```
TASKRAIL_SERVICE_TOKEN=$TASKRAIL_SERVICE_TOKEN
TASKRAIL_ADMIN_TOKEN=$TASKRAIL_ADMIN_TOKEN
GITHUB_WEBHOOK_SECRET=$GITHUB_WEBHOOK_SECRET
GH_TOKEN=$GH_TOKEN
LINEAR_API_KEY=$LINEAR_API_KEY
```

- [ ] **Step 3: Verify the YAML is valid**

```bash
ruby -e "require 'yaml'; YAML.load_file('config/deploy.yml'); puts 'OK'"
```

Expected: `OK`

- [ ] **Step 4: Commit**

```bash
git add config/deploy.yml .kamal/secrets
git commit -m "feat: wire all missing Kamal production secrets (GH_TOKEN, LINEAR_API_KEY, plus three previously declared but absent)"
```

---

## Task 5: Create `.kamal/hooks/post-deploy` for db:seed

The `postrunner-fix` queue and all its stage configs are created by `db/seeds.rb`, not migrations. Currently, `bin/docker-entrypoint` runs `db:prepare` (migrations only) — seeds never run on deploy. In Kamal 2, post-deploy actions are handled by an executable shell script at `.kamal/hooks/post-deploy` (not a key in `config/deploy.yml`).

The hook runs on the **deploy machine** (not inside the container), so it must use `kamal app exec` to run the Rails command inside the container.

**Files:**
- Create: `.kamal/hooks/post-deploy`

- [ ] **Step 1: Create the hook file**

Create `.kamal/hooks/post-deploy` with this content:

```sh
#!/bin/sh
set -e

kamal app exec --reuse "bin/rails db:seed"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x .kamal/hooks/post-deploy
```

- [ ] **Step 3: Verify the hook is executable and the shebang is correct**

```bash
head -1 .kamal/hooks/post-deploy
ls -la .kamal/hooks/post-deploy
```

Expected: `#!/bin/sh` on the first line, `-rwxr-xr-x` permissions (or similar with `x` bit set).

- [ ] **Step 4: Confirm the existing sample for reference**

```bash
cat .kamal/hooks/post-deploy.sample
```

The sample shows the hook environment variables available (`KAMAL_RECORDED_AT`, `KAMAL_PERFORMER`, etc.). Our hook doesn't use them, which is fine.

- [ ] **Step 5: Commit**

```bash
git add .kamal/hooks/post-deploy
git commit -m "feat: add post-deploy hook to run db:seed after every Kamal deploy"
```

---

## Task 6: Run full test suite and verify

- [ ] **Step 1: Run the full postrunner-fix seed spec**

```bash
bundle exec rspec spec/models/work_queue_seed_spec.rb --format documentation
```

Expected: All examples pass including the new "seeds the postrunner-fix queue" example.

- [ ] **Step 2: Run the queue validation rake task**

This CI step validates all queue YAMLs for structural correctness.

```bash
bundle exec rake queues:validate
```

Expected: No errors.

- [ ] **Step 3: Run the full RSpec suite to check for regressions**

```bash
bundle exec rspec
```

Expected: All tests green.

- [ ] **Step 4: Verify the local seed produces correct DB rows**

```bash
bundle exec rails db:seed
bundle exec rails runner "
  q = WorkQueue.find_by!(slug: 'postrunner-fix')
  r = q.stage_configs.find_by!(stage_name: 'review')
  puts 'model_override: ' + r.model_override.inspect
  puts 'adapter_config has model key: ' + r.adapter_config.key?('model').to_s
  f = q.stage_configs.find_by!(stage_name: 'fix')
  puts 'fix prompt includes git checkout: ' + f.agent_prompt.include?('git checkout -b').to_s
"
```

Expected output:
```
model_override: "claude-opus-4-6"
adapter_config has model key: false
fix prompt includes git checkout: true
```

- [ ] **Step 5: Commit any remaining changes** (if Step 4 prompted any fixes)

---

## Verification Checklist (manual, post-deploy)

These cannot be automated in RSpec and require a running production environment:

- [ ] `GH_TOKEN` allows `gh pr create/checks/merge` against a test repo in the MyScribbl org
- [ ] `LINEAR_API_KEY` allows `LinearPollJob` to query the Linear API without auth errors (check Solid Queue logs)
- [ ] After deploy, confirm `db:seed` ran: `kamal app exec --reuse "bin/rails runner \"puts WorkQueue.find_by(slug: 'postrunner-fix')&.stage_configs&.count\""`
- [ ] `config/queue.yml` has a `dispatchers:` block (already confirmed — no change needed)
