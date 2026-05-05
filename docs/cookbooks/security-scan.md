# Security Scan Cookbook

The `security_scan` queue scans a repository or fixture app for OWASP-style vulnerabilities, classifies exploitability/severity, drafts patches for critical and high findings, runs tests, and requires security-experienced human review.

## Stages

`scan_vulnerabilities -> classify_severity -> draft_fixes -> run_tests -> human_review -> done`

## Fixture

The intentionally vulnerable fixture app lives at `test/fixtures/apps/vulnerable_security_app` and includes examples for SQL injection, command injection, XSS, hardcoded secrets, data exposure, missing CSRF, wildcard CORS, and dependency-audit signals.

## Focused verification

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/services/engine/security_scan_workflow_integration_spec.rb
```

## Follow-up queues

- Hardcoded secrets: `credential_rotation`
- Insecure dependencies: `dependency_upgrade`
- Systemic auth issues: `development`
