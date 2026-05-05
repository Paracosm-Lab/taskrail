# Dependency Upgrade Cookbook

The Dependency Upgrade cookbook audits stale Ruby and Node dependencies, prioritizes safe upgrade groups, drafts one upgrade at a time, runs tests, and sends a clean review package to a human.

## Queue

`dependency_upgrade`: `audit_dependencies -> prioritize_upgrades -> upgrade_one -> run_tests -> human_review -> done`

## Artifacts

- `dependency_audit`: outdated dependencies, semantic upgrade type, CVEs, changelog links, and audit command notes.
- `upgrade_plan`: prioritized dependency groups with risk notes and optional `spawn_work_items` for feature-sized migrations.
- `upgrade_patches`: the selected dependency, version delta, branch name, manifest/code patches, test commands, and migration notes.
- `test_results`: focused test output after applying the drafted patches.

## Fixture

The deterministic fixture lives in `cookbooks/fixtures/apps/dependency_upgrade`.

Run the fixture audit without network calls:

```bash
ruby cookbooks/fixtures/apps/dependency_upgrade/bin/dependency-audit
```

Run the cookbook e2e spec:

```bash
PATH="$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH" bundle exec rspec spec/e2e/dependency_upgrade_cookbook_spec.rb
```

## Portability

All queue and fixture paths are repo-relative. The cookbook does not commit absolute checkout paths and does not require a dedicated Docker Compose file.
