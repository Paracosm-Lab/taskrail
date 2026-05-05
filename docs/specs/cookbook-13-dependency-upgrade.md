# Cookbook Spec: Dependency Upgrade Pipeline

**Category: Development**

## Use Case

Your Gemfile has 80 gems. 15 are outdated, 3 have known CVEs, and one major version bump has been sitting in the backlog for six months. Nobody wants to touch it because the last time someone upgraded a gem, it broke three things and took a day to fix.

StupidClaw upgrades one dependency at a time, runs the tests after each, catches breaking changes early, and produces a clean PR per upgrade. The boring, risky, essential maintenance that never gets prioritized.

## Queue: `dependency_upgrade`

### Stages

```
audit_dependencies → prioritize_upgrades → upgrade_one → run_tests → human_review → done
```

### Stage Details

**audit_dependencies** (Haiku)
- Adapter: `shell_script`
- Task: Run `bundle outdated`, `npm outdated`, or equivalent. Parse CVE databases (`bundler-audit`, `npm audit`). For each dependency: current version, latest version, changelog URL, CVE count, breaking change likelihood (major/minor/patch).
- Artifact: `dependency_audit` — `{ dependencies: [{ name, current, latest, type: "major"|"minor"|"patch", cves: [], changelog_url }], total_outdated, cve_count }`
- Predicate: `audit_produced`

**prioritize_upgrades** (Sonnet)
- Adapter: `inline_claude`
- Task: Rank upgrades by urgency:
  1. CVE fixes (security) — highest
  2. Major version bumps with deprecation deadlines
  3. Minor versions with features you're waiting on
  4. Patch versions (low risk, do in bulk)
  - Group related deps (e.g., `rails` + `railties` + `activerecord` upgrade together)
  - Estimate risk for each: check changelog for breaking changes, check if your code uses deprecated APIs
- Artifact: `upgrade_plan` — `{ upgrades: [{ deps: [], priority, risk, notes }] }`
- Predicate: `upgrade_plan_produced`

**upgrade_one** (Sonnet)
- Adapter: `inline_claude`
- Task: Take the highest-priority upgrade from the plan:
  - Update the Gemfile/package.json version
  - Run `bundle install` / `npm install`
  - Read the changelog for breaking changes
  - If breaking changes affect your code, draft the migration (update API calls, rename methods, etc.)
  - Create a branch with the changes
- Artifact: `upgrade_patches` — `{ dep_name, from_version, to_version, patches: [{ file, original, replacement }], branch_name }`
- Predicate: `upgrade_drafted`

**run_tests** (shell_script)
- Adapter: `shell_script`
- Predicate: `tests_passed` (existing)
- On failure: regress to `upgrade_one` with test output — the upgrade broke something, fix it

**human_review** (gate)
- One clean PR per upgrade. Reviewer sees: what changed, why, changelog link, test results.

### Queue Config

```yaml
name: Dependency Upgrade
slug: dependency_upgrade
stages:
  - audit_dependencies
  - prioritize_upgrades
  - upgrade_one
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 3
stage_configs:
  audit_dependencies:
    adapter_type: shell_script
    allowed_skills: [read_repo, run_audit]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [audit_produced]
    agent_prompt: file://prompts/deps_audit.md
    timeout_seconds: 300
    adapter_config:
      output_artifact_kind: dependency_audit
  prioritize_upgrades:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [upgrade_plan_produced]
    agent_prompt: file://prompts/deps_prioritize.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: upgrade_plan
  upgrade_one:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo, edit_files]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [upgrade_drafted]
    agent_prompt: file://prompts/deps_upgrade_one.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: upgrade_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply upgrade patches, run bundle install, run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review dependency upgrade.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `audit_produced` — dependency_audit artifact with at least one outdated dep
- `upgrade_plan_produced` — upgrade_plan artifact with prioritized list
- `upgrade_drafted` — upgrade_patches artifact with version change

### Recurring Use

Run weekly or monthly. Each run picks up the next upgrade in priority order. Over time, your dependency debt trends toward zero without anyone blocking out a "dependency upgrade sprint."

### Cross-Queue Spawn

When a major version bump requires significant code migration (e.g., Rails 7 → 8), spawn into the `development` queue as a proper feature-sized work item rather than trying to handle it in a single upgrade stage.
