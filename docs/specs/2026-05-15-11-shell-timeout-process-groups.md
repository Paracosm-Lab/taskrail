# Spec: Shell timeout process cleanup (2026-05-15-11)

## Use case

Shell-backed adapters must stop all work they started when a timeout occurs. Killing only the direct shell process can leave child processes running and can cause reads to block if children inherit stdout or stderr.

## Scope

In scope:
- Process-group based shell execution
- Timeout cleanup for child processes
- Non-blocking output collection around timeout
- Tests for child-process cleanup

Out of scope:
- Container-level sandboxing
- CPU/memory cgroups
- Replacing shell adapters with a job runner

## Requirements

### 1) Run shell commands in their own process group

**Problem:** `ShellCommandRunner` kills `wait_thread.pid` on timeout, but shell commands can spawn child processes that survive after the parent shell is killed.

**Fix:**
- Start commands in a new process group.
- On timeout, send `TERM` to the process group.
- After a short grace period, send `KILL` to the process group.
- Handle already-exited processes without raising.

**Test:**
- A command that spawns `sleep` is fully terminated on timeout.
- The direct shell process and child process are gone after cleanup.
- Completed commands are not killed.

### 2) Avoid blocking reads after timeout

**Problem:** If child processes inherit stdout/stderr, `stdout_io.read` or `stderr_io.read` can block after the parent shell exits.

**Fix:**
- Read stdout/stderr concurrently while the command is running, or use non-blocking reads with bounded buffers.
- Ensure timeout paths return promptly even when descendants keep descriptors open.
- Add maximum output capture size to prevent memory growth.

**Test:**
- A command that writes continuously and times out returns within the timeout plus grace period.
- Captured stdout/stderr are truncated to the configured max size.
- Timeout result includes exit status `124` and a clear timeout message.

### 3) Preserve trace redaction and result shape

**Problem:** Changing process execution should not break adapter result consumers.

**Fix:**
- Keep `ShellCommandRunner::Result` fields:
  - `stdout`
  - `stderr`
  - `exit_status`
  - `duration_ms`
- Preserve existing trace redaction in `ShellScriptAdapter`.
- Include timeout information in stderr.

**Test:**
- Successful command result shape is unchanged.
- Failed command result shape is unchanged.
- Timed-out command result shape matches existing expectations.

### 4) Document limits

**Problem:** Operators need to know what shell timeouts and output limits mean.

**Fix:**
- Document timeout behavior for shell adapters.
- Document output truncation limits.
- Note that process-group cleanup is best effort and container isolation is still recommended for untrusted commands.

## Acceptance criteria

- [ ] Shell commands run in isolated process groups
- [ ] Timeout sends TERM then KILL to the process group
- [ ] Child processes do not survive timeout cleanup in tests
- [ ] Timeout path cannot block indefinitely on stdout/stderr reads
- [ ] Captured output is bounded
- [ ] Existing shell adapter specs still pass
