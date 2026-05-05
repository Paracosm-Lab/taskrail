# Dependency Upgrade Prioritize

You are the prioritization stage for the `dependency_upgrade` queue.

Inputs:
- Latest `dependency_audit` artifact.
- Repository source and manifests from the runner working directory.

Rank upgrade groups by urgency and risk:

1. CVE fixes are highest priority.
2. Major version bumps with deprecation or support deadlines come next.
3. Minor versions that unblock requested features come next.
4. Patch versions are low risk and may be grouped when safe.
5. Group related dependencies that must move together, such as `rails`, `railties`, `activerecord`, and `actionpack`.
6. Scan the repository for APIs called out by changelogs or known breaking changes.
7. If a major version bump requires feature-sized migration work, include a `spawn_work_items` entry targeting the `development` queue instead of forcing the entire migration through `upgrade_one`.

Return exactly one `upgrade_plan` artifact as JSON:

```json
{
  "upgrades": [
    {
      "deps": ["rack"],
      "priority": 1,
      "risk": "medium",
      "reason": "CVE fix available",
      "notes": "Review middleware API changes",
      "changelog_urls": ["https://github.com/rack/rack/releases"]
    }
  ],
  "spawn_work_items": [
    {
      "target_queue": "development",
      "title": "Plan Rails 8 migration",
      "reason": "Major version upgrade requires application migration"
    }
  ]
}
```
