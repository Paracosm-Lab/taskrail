# Cookbook Spec: Security Scan Pipeline

**Category: Testing**

## Use Case

You've been shipping fast. Nobody's done a security review since launch. There are probably SQL injection vulnerabilities in the old code, a few endpoints missing auth checks, and at least one hardcoded API key that someone committed eight months ago and forgot about. You know you need a security audit but it's expensive, slow, and you keep putting it off.

StupidClaw scans your codebase for the OWASP top 10, hardcoded secrets, auth bypass patterns, and unsafe data handling. It categorizes by severity, drafts fixes for the worst ones, and tests them. Not a replacement for a professional pentest, but it catches the low-hanging fruit that accounts for most real-world breaches.

## Queue: `security_scan`

### Stages

```
scan_vulnerabilities → classify_severity → draft_fixes → run_tests → human_review → done
```

### Stage Details

**scan_vulnerabilities** (Sonnet)
- Adapter: `inline_claude`
- Input: repository path
- Task: Scan for common vulnerability patterns:
  - **Injection**: SQL injection (string interpolation in queries), command injection (`system()`, backticks with user input), LDAP injection
  - **Auth**: missing authentication on endpoints, broken access control (user A can access user B's data), hardcoded credentials, weak password requirements
  - **XSS**: unescaped user input in templates, `html_safe` on user data, `dangerouslySetInnerHTML`
  - **Secrets**: API keys, passwords, tokens in source code, `.env` files committed, credentials in config
  - **Data exposure**: sensitive fields in API responses (passwords, SSNs, tokens), verbose error messages exposing internals
  - **CSRF**: missing CSRF tokens on state-changing endpoints
  - **Dependencies**: known CVEs in dependencies (`bundler-audit`, `npm audit`)
  - **Insecure config**: debug mode in production config, CORS wildcard, missing security headers
  - For each: file, line, category, evidence, exploitability assessment
- Artifact: `vulnerability_scan` — `{ vulnerabilities: [{ category, file, line, evidence, exploitability: "easy"|"moderate"|"difficult", severity }] }`
- Predicate: `scan_completed`
- Why Sonnet: needs to understand code context to distinguish real vulnerabilities from false positives

**classify_severity** (Sonnet)
- Adapter: `inline_claude`
- Input: vulnerability_scan artifact, source code
- Task: For each vulnerability:
  - Is this actually exploitable in context? (e.g., a SQL injection in an admin-only endpoint behind VPN is lower risk than one on a public API)
  - What's the blast radius? (one user's data vs. the entire database)
  - Is it actively exploitable or theoretical?
  - Classify as `critical` / `high` / `medium` / `low` / `false_positive`
  - Remove false positives with reasoning
  - Group related vulnerabilities (e.g., "all controllers missing CSRF" is one finding, not 20)
- Artifact: `severity_report` — `{ findings: [{ vulnerabilities: [...], severity, blast_radius, exploitability, recommendation }], false_positives_removed: count }`
- Predicate: `severity_classified` (reuse)

**draft_fixes** (Sonnet)
- Adapter: `inline_claude`
- Input: severity_report (critical and high only), source code
- Task: Draft fixes:
  - SQL injection → parameterized queries
  - XSS → proper escaping, remove `html_safe`
  - Hardcoded secrets → environment variables, reference to secrets manager
  - Missing auth → add `before_action :authenticate!` or equivalent
  - Missing CSRF → add tokens
  - Insecure deps → version bumps (or spawn to dependency_upgrade queue)
- Artifact: `security_patches` — `{ patches: [{ file, original, replacement, vulnerability_ref, severity }] }`
- Predicate: `fixes_drafted` (reuse)

**run_tests** (shell_script)
- Predicate: `tests_passed` (existing)
- On failure: regress to `draft_fixes`

**human_review** (gate)
- Critical and high severity findings should be reviewed by someone with security experience, not just any engineer

### Queue Config

```yaml
name: Security Scan
slug: security_scan
stages:
  - scan_vulnerabilities
  - classify_severity
  - draft_fixes
  - run_tests
  - human_review
  - done
config:
  default_max_retries: 2
  default_timeout_seconds: 600
  default_escalation: block_and_notify
  max_regression_loops: 2
stage_configs:
  scan_vulnerabilities:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [scan_completed]
    agent_prompt: file://prompts/security_scan.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: vulnerability_scan
  classify_severity:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [severity_classified]
    agent_prompt: file://prompts/security_classify.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: severity_report
  draft_fixes:
    adapter_type: inline_claude
    model_override: claude-sonnet-4-20250514
    allowed_skills: [read_repo]
    forbidden_skills: [deploy]
    max_retries: 2
    completion_criteria: [fixes_drafted]
    agent_prompt: file://prompts/security_draft_fixes.md
    timeout_seconds: 600
    adapter_config:
      output_artifact_kind: security_patches
  run_tests:
    adapter_type: shell_script
    allowed_skills: [run_tests]
    forbidden_skills: [edit_files, deploy]
    max_retries: 1
    completion_criteria: [tests_passed]
    agent_prompt: Apply security patches and run the test suite. Report pass/fail.
    timeout_seconds: 600
  human_review:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Security review — critical and high findings require security-experienced reviewer.
    timeout_seconds: 86400
  done:
    adapter_type: fake
    max_retries: 0
    completion_criteria: [report_present]
    agent_prompt: Terminal state.
    timeout_seconds: 60
```

### New Predicates

- `scan_completed` — vulnerability_scan artifact exists

### Cross-Queue Spawn

- Hardcoded secrets → spawn into `credential_rotation` queue
- Insecure dependencies → spawn into `dependency_upgrade` queue
- Systemic auth issues → spawn into `development` queue

### Recurring Use

Run monthly or after every major feature ship. Track vulnerability count over time. The goal is trending toward zero critical/high findings.
