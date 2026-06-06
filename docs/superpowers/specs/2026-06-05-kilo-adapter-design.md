# Kilo Adapter Design

## Goal

Add a `kilo` adapter to TaskRail that shells out to the Kilo Code CLI (`@kilocode/cli`), enabling queue stages to use any of Kilo's 500+ supported models (Deepseek, Anthropic, OpenAI, etc.) as an alternative to the Codex adapter.

## Motivation

The Codex adapter is limited to OpenAI models and subject to per-model rate limits. When limits are hit, the entire pipeline stalls. Kilo Code CLI supports 500+ models across many providers, giving TaskRail the ability to route work to whichever model has available capacity — or to use specific models (e.g. Deepseek) that may be better suited for certain tasks.

## Architecture

Mirror the existing Codex pattern: `KiloAdapter` + `KiloCliSubmitter`, registered in `ClaimExecutor::ADAPTERS`. No changes to `BaseAdapter`, `AgentResult`, `TransitionManager`, or any other existing code beyond adding one entry to the ADAPTERS hash.

### Components

**`KiloCliSubmitter`** — `app/services/kilo_cli_submitter.rb`

Subprocess executor for the Kilo CLI. Mirrors `CodexCliSubmitter` structure (top-level in `app/services/`, not namespaced under `Engine`, matching the existing convention).

- Result struct: `Data.define(:stdout, :stderr, :exit_status, :duration_ms, :external_id, :metadata)` (includes `external_id` for struct parity with `CodexCliSubmitter::Result`, though KiloAdapter is sync-only and will not populate it)
- Spawns `kilo run --auto --format json` via `Open3.popen3`
- Prompt written to stdin (preferred over positional argument to avoid OS `ARG_MAX` limits with multi-paragraph prompts — discovery step should confirm stdin support, fall back to `--prompt-file` temp file if needed)
- Model specified via `--model provider/model` flag
- Working directory via `--dir <path>` flag
- Parallel threads for stdout/stderr collection
- Timeout enforced by the submitter via `Timeout.timeout()` with TERM → KILL escalation (same as CodexCliSubmitter)
- Parses stdout as JSON to extract structured results

**`KiloAdapter`** — `app/adapters/adapters/kilo_adapter.rb`

Extends `BaseAdapter`. Synchronous only (no async/polling mode).

`execute(assignment)` flow:
1. Extract stage config: `model`, `args`, `timeout_seconds`, `working_directory`, `output_artifact_kind`, `branch_prefix`
2. Build prompt via `CodexAssignmentPrompt` (reused — prompt format is adapter-agnostic)
3. Construct CLI command: base args from config + `--model` + `--dir` + prompt
4. Call `KiloCliSubmitter.new(...).call`
5. Parse result:
   - Exit 0 → `AgentResult.success()` with artifacts and report extracted from JSON output
   - Exit 1 → `AgentResult.failure()` with error details
   - Exit 124 or timeout → `AgentResult.timeout()`
6. Extract branch artifact from output (same pattern as CodexAdapter — look for branch name in structured output or final message text)

**Registration** — add `"kilo" => Adapters::KiloAdapter` to `ClaimExecutor::ADAPTERS` hash.

### CLI Interface

| Aspect | Codex | Kilo |
|--------|-------|------|
| Command | `codex exec --json` | `kilo run --auto --format json` |
| Prompt delivery | stdin | stdin (verify in discovery; fallback: temp file via pipe) |
| Model flag | `--model gpt-5.5` | `--model provider/model` |
| Working directory | Process cwd | `--dir <path>` |
| Output format | JSONL event stream | JSON event stream |
| Exit codes | 0=success | 0=success, 1=error, 124=timeout |
| File context | N/A | `--file <path>` (repeatable) |
| Agent persona | N/A | `--agent code\|ask\|plan\|debug` |

### Queue YAML Configuration

```yaml
stage_configs:
  fix:
    adapter_type: kilo
    max_retries: 2
    timeout_seconds: 300
    adapter_config:
      command: kilo
      args:
        - run
        - --auto
        - --format
        - json
      model: deepseek/deepseek-chat
      output_artifact_kind: branch
      branch_prefix: postrunner/
```

The `model` field uses Kilo's `provider/model` format. Examples:
- `deepseek/deepseek-chat`
- `anthropic/claude-sonnet-4-20250514`
- `openai/gpt-4o`

### Kilo CLI Setup

Kilo must be installed on the TaskRail server:

```bash
npm install -g @kilocode/cli
```

API keys are configured in `~/.config/kilo/kilo.jsonc` using `{env:VAR_NAME}` syntax, or via provider-specific environment variables. The exact configuration depends on which providers are enabled.

### Discovery Step

The Kilo CLI's `--format json` output schema has not been tested locally yet. Before building the parser, the implementation plan must include a step to:

1. Install Kilo CLI locally
2. Configure at least one provider (e.g. Deepseek)
3. Run `kilo run --auto --format json "create a file called hello.txt with the text hello world"` in a temp directory
4. Capture and document the exact JSON output structure
5. Verify prompt delivery via stdin (`echo "prompt" | kilo run --auto --format json`) — if stdin is not supported, test writing prompt to a temp file and piping it
6. Test `--agent code` flag to confirm it selects the coding persona (expose as optional `agent` field in `adapter_config`)
7. Build the parser to match the observed schema

This is the main unknown in the design. The adapter structure, registration, and subprocess management are all proven patterns from CodexAdapter.

### Artifact Extraction

Branch names are extracted from the Kilo output using the same strategy as CodexAdapter:

1. Check structured JSON output for branch/artifact fields
2. Fall back to regex scanning the final message text for `{"artifacts": [{"kind": "branch", ...}]}` blocks (agents are prompted to output this)
3. The `output_artifact_kind` and `branch_prefix` config fields control what to look for

### Error Handling

- Kilo not installed → `Open3.popen3` raises `Errno::ENOENT` → caught in adapter → `AgentResult.failure(report: { "error" => "kilo command not found" })`
- Timeout → submitter sends TERM, waits 5s, sends KILL → `AgentResult.timeout()`
- Non-zero exit → `AgentResult.failure()` with stderr in report
- Unparseable JSON output → `AgentResult.failure()` with raw stdout/stderr preserved

### What Does Not Change

- `BaseAdapter` interface
- `AgentResult` / `AsyncAdapterResult` structs
- `CodexAssignmentPrompt` (reused for prompt building)
- `TransitionManager` (adapter-agnostic)
- `ClaimExecutor` (only adds one ADAPTERS entry)
- Existing `CodexAdapter` / `CodexCliSubmitter` (untouched)

### File Summary

| File | Action |
|------|--------|
| `app/adapters/adapters/kilo_adapter.rb` | Create |
| `app/services/kilo_cli_submitter.rb` | Create |
| `app/services/engine/claim_executor.rb` | Modify (add ADAPTERS entry) |
| `test/adapters/kilo_adapter_test.rb` | Create |
| `test/services/engine/kilo_cli_submitter_test.rb` | Create |

### Testing

- Unit tests for `KiloCliSubmitter`: mock `Open3.popen3`, verify command construction, timeout handling, JSON parsing
- Unit tests for `KiloAdapter`: mock submitter, verify `AgentResult` construction for success/failure/timeout cases, artifact extraction
- Integration test: end-to-end with a real Kilo CLI call (skipped in CI, run manually)
