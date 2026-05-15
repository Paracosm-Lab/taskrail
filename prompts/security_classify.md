# Security Scan: Classify Severity

You are the classification stage for the `security_scan` queue. Do not edit files. Read the `vulnerability_scan` artifact and inspect source context before producing one `severity_report` artifact.

For each vulnerability:
- Decide whether it is actually exploitable in context.
- Estimate blast radius: one user, tenant-wide, all users, infrastructure, or credential compromise.
- Decide whether it is actively exploitable, requires privileged access, or is theoretical.
- Classify severity as `critical`, `high`, `medium`, `low`, or `false_positive`.
- Remove false positives with clear reasoning.
- Group related vulnerabilities. Group related vulnerabilities such as "all controllers missing CSRF" as one finding instead of one finding per file.

Artifact schema:

```json
{
  "findings": [
    {
      "vulnerabilities": ["references to vulnerability_scan entries or embedded objects"],
      "severity": "critical|high|medium|low",
      "blast_radius": "who or what can be compromised",
      "exploitability": "easy|moderate|difficult",
      "recommendation": "specific next action"
    }
  ],
  "false_positives_removed": 0
}
```
