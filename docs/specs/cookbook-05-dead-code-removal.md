# Cookbook Spec: Dead Code & Unused Dependency Removal

## Use Case

Six months of fast shipping. Gems nobody uses. Helpers nobody calls. Routes that go nowhere. Feature modules that were replaced but never deleted. The codebase grows but the useful code doesn't.

StupidClaw scans for dead code and unused dependencies, verifies nothing references them, drafts removal PRs, runs the tests to confirm nothing breaks, and queues for review.

## Queue: `dead_code_removal`

### Stages

```
scan_references → verify_unused → draft_removals → run_tests → human_review → done
```

### Stage Details

**scan_references** (Haiku)
- Adapter: `inline_claude` or `shell_script`
- Input: repository path
- Task: Identify candidates for removal:
  - **Unused dependencies**: gems/packages in lockfile but never imported/required
  - **Unused files**: Ruby files, JS modules, CSS files with zero inbound references
  - **Dead methods**: public methods with no callers outside their own file
  - **Orphan routes**: routes mapped to controllers/actions that don't exist
  - **Stale migrations**: empty or no-op migrations that can be squashed
  - **Abandoned feature flags**: flags checked in code but marked 100% rolled out or removed from the flag service
- Artifact: `removal_candidates` — `{ dependencies: [], files: [], methods: [], routes: [], other: [] }`
- Predicate: `candidates_identified` — artifact exists
- Why Haiku: reference counting and import tracing, not reasoning

**verify_unused** (Sonnet)
- Adapter: `inline_claude`
- Input: removal_candidates artifact, source code
- Task: For each candidate, verify it's truly unused:
  - Check for dynamic references (metaprogramming, `send`, string interpolation)
  - Check for references in tests (test helpers, factories, fixtures)
  - Check for references in config files, rake tasks, scripts
  - Check for references in documentation or comments that suggest it's needed
  - Classify each as `safe_to_remove` / `probably_safe` / `needs_investigation`
  - Explain reasoning for each classification
- Artifact: `verified_removals` — `{ removals: [{ type, name, path, classification, reasoning }] }`
- Predicate: `removals_verified` — artifact exists with at least one `safe_to_remove` item
- Why Sonnet: needs to reason about dynamic references and metaprogramming

**draft_removals** (Sonnet)
- Adapter: `inline_claude`
- Input: verified_removals artifact (only `safe_to_remove` items)
- Task: Draft the removal changes:
  - Remove unused gem/package entries from Gemfile/package.json
  - Delete orphan files
  - Remove dead methods
  - Clean up orphan routes
  - Group related removals (e.g., a gem + all files that only existed to support it)
- Artifact: `removal_patches` — `{ patches: [{ action: "delete"|"modify", path, description }] }`
- Predicate: `removals_drafted` — artifact has at least one patch
- Why Sonnet: needs to understand dependency chains (removing a gem might break a file that imports it)

**run_tests** (shell_script)
- Adapter: `shell_script`
- Input: removal_patches artifact
- Task: Apply removals, run full test suite + linter, verify nothing breaks
- Artifact: `test_results`
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_removals` — something we thought was unused wasn't

**human_review** (gate)
- Adapter: `fake`
- Blocks for human approval

### Queue Config

```yaml
name: Dead Code Removal
slug: dead_code_removal
stages:
  - scan_references
  - verify_unused
  - draft_removals
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_references:
    adapter_type: inline_claude
    model_override: claude-haiku-4-5-20251001
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [candidates_identified]
    agent_prompt: file://prompts/deadcode_scan_references.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: removal_candidates
  verify_unused:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [removals_verified]
    agent_prompt: file://prompts/deadcode_verify_unused.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: verified_removals
  draft_removals:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [removals_drafted]
    agent_prompt: file://prompts/deadcode_draft_removals.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: removal_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply removal patches and run the full test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Review dead code removals before merge.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates Needed

- `candidates_identified` — checks for `removal_candidates` artifact
- `removals_verified` — checks for `verified_removals` with at least one `safe_to_remove` item
- `removals_drafted` — checks for `removal_patches` with at least one patch

### E2E Test Fixtures

Create a fixture app in `test/fixtures/apps/dead_code_app/` with:
- A Gemfile entry for a gem that's never required
- A helper module that's never included
- A route to a controller action that doesn't exist
- A method that's defined but never called
- A file that's never required or autoloaded

### Safety

The `verify_unused` stage is critical. Ruby's metaprogramming makes static analysis unreliable — `send(:method_name)`, `const_get`, `eval`. The verification step must explicitly check for dynamic references and err on the side of `needs_investigation` rather than `safe_to_remove`.
