# Dependency Upgrade Audit

You are the audit stage for the `dependency_upgrade` queue.

Inputs:
- Repository root from the runner working directory; never assume an absolute path.
- Optional fixture app from adapter config: `cookbooks/fixtures/apps/dependency_upgrade`.
- Ruby and Node manifests when present: `Gemfile`, `Gemfile.lock`, `package.json`, lockfiles, and audit reports.

Collect a dependency audit:

1. For Ruby projects, run safe local checks such as `bundle outdated --parseable` and `bundler-audit check --format json` when available.
2. For Node projects, run safe local checks such as `npm outdated --json` and `npm audit --json` when available.
3. Do not install new global tools or make network calls unless the runner explicitly permits it.
4. For each outdated dependency, record current version, latest version, dependency ecosystem, semantic upgrade type (`major`, `minor`, or `patch`), CVEs, changelog URL when discoverable, and notes about unavailable data.
5. Preserve enough source evidence for downstream review: manifest file, lockfile, and audit command output summary.

Return exactly one `dependency_audit` artifact as JSON:

```json
{
  "dependencies": [
    {
      "name": "rails",
      "ecosystem": "rubygems",
      "current": "7.1.3",
      "latest": "8.0.1",
      "type": "major",
      "cves": [],
      "changelog_url": "https://github.com/rails/rails/releases",
      "manifest": "Gemfile"
    }
  ],
  "total_outdated": 1,
  "cve_count": 0,
  "audit_commands": ["bundle outdated --parseable"],
  "notes": []
}
```
