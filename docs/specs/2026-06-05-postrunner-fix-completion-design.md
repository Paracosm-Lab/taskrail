# Postrunner-Fix Pipeline Completion

## Goal

Close the remaining gaps between the shipped `postrunner-fix` queue infrastructure (PR #22) and a
runnable end-to-end pipeline. Five targeted changes — no new adapters or services.

## Scope

**In scope:**
- Fix `model_override` wiring for the `review` stage
- Add `GH_TOKEN` and `LINEAR_API_KEY` to Kamal production secrets
- Update the `fix` stage prompt so codex clones, fixes, and pushes the branch
- Update the `review` stage prompt so Claude fetches the diff before evaluating
- Confirm `rails db:seed` runs on deploy and Solid Queue dispatcher is active in production

**Out of scope:** ENG-173 (Postrunner) — that's a separate ticket and a prerequisite for the pipeline
to receive real work items. This spec only covers the TaskRail side.

## Changes

### 1. `model_override` in `postrunner_fix.yml`

`AssignmentBuilder` reads `stage_config.model_override` (a dedicated column on `stage_configs`),
not `adapter_config["model"]`. The `review` stage currently sets `model: claude-opus-4-6` inside
`adapter_config`, which is ignored.

**Fix:** move it to the stage level:

```yaml
review:
  adapter_type: inline_claude
  model_override: claude-opus-4-6   # ← here, not inside adapter_config
  ...
  adapter_config:
    command: claude
    args:
      - --print
    output_artifact_kind: review_report
    # model: removed from here
```

`db:seed` propagates `model_override` to the `stage_configs` row via `seeds.rb:28`.

### 2. Kamal production secrets

Two env vars needed in production:

| Var | Purpose |
|-----|---------|
| `GH_TOKEN` | Authenticates `gh` CLI calls from `github_pr_create`, `github_ci_poll`, `github_pr_merge` |
| `LINEAR_API_KEY` | Authenticates `LinearPollJob` GraphQL requests to Linear |

Add to `config/deploy.yml` `env.secret` list:

```yaml
env:
  secret:
    - RAILS_MASTER_KEY
    - TASKRAIL_DATABASE_PASSWORD
    - TASKRAIL_SERVICE_TOKEN
    - TASKRAIL_ADMIN_TOKEN
    - GITHUB_WEBHOOK_SECRET
    - GH_TOKEN        # ← add
    - LINEAR_API_KEY  # ← add
```

Add to `.kamal/secrets` (pull from ENV, same pattern as existing secrets):

```
GH_TOKEN=$GH_TOKEN
LINEAR_API_KEY=$LINEAR_API_KEY
```

Note: `.kamal/secrets` is also missing three entries that are already declared in `config/deploy.yml`
but not yet filled in: `TASKRAIL_SERVICE_TOKEN`, `TASKRAIL_ADMIN_TOKEN`, `GITHUB_WEBHOOK_SECRET`.
These must be added at the same time.

### 3. Fix stage prompt

The current prompt tells codex to clone and commit but does not tell it to push. `github_pr_create`
runs `gh pr create --head <branch>` which requires the branch to exist on the remote.

The updated prompt instructs codex to find the repository from its assignment context (the assignment
JSON is included in the prompt by `CodexAdapter`; prompts are passed as-is without interpolation):

```
You are fixing a CI tool finding. Your assignment context is included below. Find the `repository`
value in the work item tags — it identifies the GitHub repository to fix (format: "org/repo").

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

The `sync_artifacts` method in `CodexAdapter` extracts the branch name from the final response via
`ResponseParser` or from `metadata["branch"]`.

### 4. Review stage prompt

`inline_claude` runs `claude --print` which has full tool access. Claude can execute `gh pr diff`
to fetch the diff before evaluating. The PR number and repository are available in the assignment
context via `upstream_artifacts` (the `pull_request` artifact from the `open_pr` stage).

Prompts are passed as-is without interpolation, so the updated prompt instructs Claude to locate
the PR number and repository from its assignment context (which includes `upstream_artifacts`):

```
You are reviewing a pull request that fixes a CI tool finding. Your assignment context is included
below. Find the `pull_request` artifact in the `upstream_artifacts` array under Context — it
contains the PR number and repository.

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

### 5. Production deployment verification

Two items to confirm/add:

**`rails db:seed` on deploy** — the `postrunner-fix` queue and its stage configs are created by
`db/seeds.rb`, not migrations. Seeds do not run automatically on deploy (only `db:prepare` runs
via `bin/docker-entrypoint`, which handles migrations but not seeds). Add a Kamal post-deploy hook
to run seeds inside the container after each deploy.

In Kamal 2, hooks are executable files in `.kamal/hooks/`, not keys in `config/deploy.yml`.
Create `.kamal/hooks/post-deploy` (executable) on the deploy machine:

```sh
#!/bin/sh
kamal app exec --reuse "bin/rails db:seed"
```

**Solid Queue dispatcher** — `LinearPollJob` is a recurring job in `config/recurring.yml`. Solid
Queue's dispatcher process must be running in production for the schedule to fire. `config/queue.yml`
already includes a `dispatchers:` block at the `default` anchor that is inherited by all environments,
so no change is needed — just confirm the Kamal deploy starts the Solid Queue worker process.

## Testing

- Re-seed locally, confirm `review` stage config has `model_override: "claude-opus-4-6"` set
- Manually create a test work item in the `postrunner-fix` queue and run one engine tick through the `fix` stage prompt against a real repo to verify clone + push works
- Verify `GH_TOKEN` allows `gh pr create/checks/merge` against a test repo
- Verify `LINEAR_API_KEY` allows `LinearPollJob` to query the Linear API without error

## Dependencies

- ENG-173 (Postrunner) must ship before real work items flow in via `LinearPollJob`
- `GH_TOKEN` needs read/write access to all 7 service repos in the `MyScribbl` GitHub org
