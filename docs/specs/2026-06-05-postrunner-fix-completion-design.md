# Postrunner-Fix Pipeline Completion

## Goal

Close the remaining gaps between the shipped `postrunner-fix` queue infrastructure (PR #22) and a
runnable end-to-end pipeline. Four targeted changes — no new adapters or services.

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

Add both to `config/deploy.yml` (env section) and `.kamal/secrets` (fetched from the secret store).

### 3. Fix stage prompt

The current prompt tells codex to clone and commit but does not tell it to push. `github_pr_create`
runs `gh pr create --head <branch>` which requires the branch to exist on the remote.

The updated prompt also makes the clone URL explicit using the `repository` tag:

```
You are fixing a CI tool finding in the repository: https://github.com/{{ tags.repository }}

Steps:
1. Clone the repository: git clone https://github.com/{{ tags.repository }} repo && cd repo
2. Read the spec below carefully — it identifies the tool, rule, file, and line.
3. Apply the minimal fix. Do not refactor surrounding code.
4. Commit: git commit -am "fix: <short description>"
5. Push the branch to origin: git push origin HEAD
6. In your final response, include the branch name you pushed.

Branch name format: postrunner/{tool}-{short-slug}
```

The `sync_artifacts` method in `CodexAdapter` extracts the branch name from the final response via
`ResponseParser` or from `metadata["branch"]`.

### 4. Review stage prompt

`inline_claude` runs `claude --print` which has full tool access. Claude can execute `gh pr diff`
to fetch the diff before evaluating. The PR number and repository are available in the assignment
context via `upstream_artifacts` (the `pull_request` artifact from the `open_pr` stage).

Updated prompt:

```
You are reviewing a pull request that fixes a CI tool finding.

First, fetch the diff:
  gh pr diff {{ upstream_artifacts.pull_request.number }} --repo {{ work_item.tags.repository }}

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
`db/seeds.rb`, not migrations. The Kamal deploy must run `db:seed` after `db:migrate`. Add a
`post_deploy` hook if missing:

```yaml
# config/deploy.yml
hooks:
  post_deploy:
    - bundle exec rails db:seed
```

**Solid Queue dispatcher** — `LinearPollJob` is a recurring job in `config/recurring.yml`. Solid
Queue's dispatcher process must be running in production for the schedule to fire. Confirm
`config/solid_queue.yml` includes a dispatcher and that the Kamal deploy starts it.

## Testing

- Re-seed locally, confirm `review` stage config has `model_override: "claude-opus-4-6"` set
- Manually create a test work item in the `postrunner-fix` queue and run one engine tick through the `fix` stage prompt against a real repo to verify clone + push works
- Verify `GH_TOKEN` allows `gh pr create/checks/merge` against a test repo
- Verify `LINEAR_API_KEY` allows `LinearPollJob` to query the Linear API without error

## Dependencies

- ENG-173 (Postrunner) must ship before real work items flow in via `LinearPollJob`
- `GH_TOKEN` needs read/write access to all 7 service repos in the `MyScribbl` GitHub org
