# Spec: Security hardening (2026-05-15-3)

## Use case

Several input validation and access control gaps exist that could allow command injection, data pollution, or unauthorized webhook submission. These must be closed before production.

## Scope

In scope:
- Shell adapter working directory sandbox
- Command redaction in trace events
- GitHub webhook secret required (fail-closed)
- Stage name validation on work item creation
- Tag parameter sanitization
- Trace redaction pattern expansion

Out of scope:
- Rate limiting (separate spec)
- CORS configuration (no browser clients for API yet)
- Full RBAC / multi-tenant auth

## Requirements

### 1) Shell adapter sandbox

**Problem:** `ShellScriptAdapter` passes `working_directory` from adapter config to `ShellCommandRunner` with no validation. A malicious or misconfigured config could escape to arbitrary paths.

**Fix:**
- Validate `working_directory` resolves to a path within an allowed base directory (e.g., `/tmp/taskrail-workspaces/` or configurable via `TASKRAIL_WORKSPACE_ROOT`).
- Use `File.realpath` after resolution to catch symlink escapes.
- Reject and fail the claim if validation fails.

```ruby
def validate_working_directory!(dir)
  root = ENV.fetch("TASKRAIL_WORKSPACE_ROOT", "/tmp/taskrail-workspaces")
  resolved = File.realpath(dir)
  unless resolved.start_with?(root)
    raise SecurityError, "working_directory #{dir} escapes sandbox root #{root}"
  end
end
```

**Test:**
- Config with `working_directory: "/tmp/taskrail-workspaces/job-123"` — passes.
- Config with `working_directory: "/etc/passwd"` — raises SecurityError.
- Config with symlink pointing outside root — raises SecurityError.

### 2) Command redaction in traces

**Problem:** `ShellScriptAdapter#trace_event` includes the raw command string. Commands may contain inline secrets (e.g., `curl -H "Authorization: Bearer sk-..."` ).

**Fix:** Run the command string through the existing `safe_trace_summary` redaction before storing in trace events. Apply at the adapter level before the trace is persisted.

**Test:**
- Command containing `Bearer sk-12345` is stored as `Bearer [REDACTED]`.
- Command without secrets is stored unchanged.

### 3) GitHub webhook secret required

**Problem:** `GithubPrWebhooksController` only verifies the signature if `GITHUB_WEBHOOK_SECRET` is set. If unset, the endpoint accepts any payload — it's public.

**Fix:** If `GITHUB_WEBHOOK_SECRET` is not set, return 503 (service not configured) instead of accepting unverified payloads. Fail closed.

```ruby
def verify_signature!
  secret = ENV["GITHUB_WEBHOOK_SECRET"]
  unless secret
    head :service_unavailable
    return
  end
  # existing signature verification logic
end
```

**Test:**
- With secret set + valid signature → 200.
- With secret set + invalid signature → 401.
- With secret unset → 503.

### 4) Stage name validation on work item creation

**Problem:** `WorkItemsController#create` accepts any string for `stage_name`. If the stage doesn't exist in the queue's stage configs, the item is orphaned — the engine never picks it up.

**Fix:** After finding the queue, validate that `stage_name` (or the default first stage) exists in the queue's stage configs. Return 422 with a clear error if not.

```ruby
unless queue.stage_configs.exists?(stage_name: stage_name)
  render json: { error: "Stage '#{stage_name}' does not exist in queue '#{queue.slug}'" }, status: :unprocessable_entity
  return
end
```

**Test:**
- Create with valid stage → 201.
- Create with nonexistent stage → 422 with error message.
- Create with no stage (uses default first stage) → 201.

### 5) Tag parameter sanitization

**Problem:** `params.fetch(:tags, {}).to_unsafe_h` bypasses Rails strong parameters. Arbitrary nested structures can be injected.

**Fix:** Replace `to_unsafe_h` with explicit permitted keys, or validate that tags is a flat hash of string keys and string values:

```ruby
def sanitize_tags(raw_tags)
  return {} unless raw_tags.is_a?(ActionController::Parameters) || raw_tags.is_a?(Hash)
  raw_tags.to_h.each_with_object({}) do |(k, v), acc|
    acc[k.to_s] = v.to_s if k.is_a?(String) || k.is_a?(Symbol)
  end
end
```

**Test:**
- `{ "env" => "prod", "team" => "platform" }` — accepted as-is.
- `{ "nested" => { "bad" => "data" } }` — nested value is flattened to string.
- Empty tags — returns `{}`.

### 6) Expand trace redaction patterns

**Problem:** `sensitive_trace_key?` and `safe_trace_summary` miss common patterns:
- `x-api-key` (hyphenated)
- `apikey` (no separator)
- `aws_secret_access_key`, `aws_session_token`
- `private_key`, `signing_key`

**Fix:** Add these patterns to the regex in `sensitive_trace_key?` and `safe_trace_summary`:

```ruby
def sensitive_trace_key?(key)
  key.to_s.match?(/prompt|assignment|api[_-]?key|secret|password|token|authorization|credential|private[_-]?key|signing[_-]?key|session/i)
end
```

And in `safe_trace_summary`, expand the string-level pattern similarly.

**Test:**
- Hash with key `"x-api-key"` → redacted.
- Hash with key `"aws_secret_access_key"` → redacted.
- Hash with key `"stage_name"` → not redacted.
- String containing `"apikey=abc123"` → redacted.

## Acceptance criteria

- [ ] Shell adapter rejects working directories outside the sandbox root
- [ ] Trace events do not contain raw secrets from shell commands
- [ ] Webhook endpoint returns 503 when secret is not configured
- [ ] Work item creation rejects nonexistent stage names with 422
- [ ] Tags are sanitized to flat string key/value pairs
- [ ] Trace redaction catches x-api-key, apikey, aws_secret_access_key, private_key patterns
- [ ] All scenarios have passing specs
