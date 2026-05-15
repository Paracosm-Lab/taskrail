# Spec: CI pipeline hardening (2026-05-15-5)

## Use case

The Woodpecker CI pipeline is missing two gates required by the standards-remediation spec: secret scanning and SBOM generation. The type-check step is a no-op placeholder.

## Scope

In scope:
- Add gitleaks secret scanning step
- Add SBOM artifact generation step
- Resolve type-check placeholder (wire up or remove)
- Add Dockerfile HEALTHCHECK

Out of scope:
- License scanning (FOSSA, etc.)
- Performance/load testing in CI
- Multi-version Ruby test matrix

## Requirements

### 1) Secret scanning with gitleaks

**Problem:** No secret scanning in the CI pipeline. Committed secrets won't be caught until production.

**Fix:** Add a gitleaks step to `.woodpecker.yml` after the lint stage:

```yaml
secret-scan:
  image: zricethezav/gitleaks:latest
  commands:
    - gitleaks detect --source . --verbose --no-banner
  depends_on:
    - lint
```

Run on both push and pull_request events. Fail the pipeline if any secrets are detected.

**Test:**
- Commit a file with `AKIA...` pattern → pipeline fails at secret-scan step.
- Clean commit → step passes.

### 2) SBOM generation

**Problem:** Standards-remediation spec requires SBOM artifact generation. Not present in CI.

**Fix:** Add an SBOM step using `cyclonedx-ruby` or `syft`:

```yaml
sbom:
  image: anchore/syft:latest
  commands:
    - syft dir:. -o cyclonedx-json > sbom.json
  depends_on:
    - test-gate
```

Store `sbom.json` as a pipeline artifact. This runs after tests pass but doesn't block deployment — it's an audit artifact.

### 3) Type-check placeholder

**Problem:** The type-check step currently outputs a string saying "no sorbet/steep yet" and passes. This is misleading — either add real type checking or remove the step.

**Fix:** Remove the placeholder step entirely. Add a comment in `.woodpecker.yml`:

```yaml
# Type checking: not yet configured. Add Sorbet or Steep when warranted.
```

Don't ship a green step that checks nothing.

### 4) Dockerfile HEALTHCHECK

**Problem:** No `HEALTHCHECK` instruction in the Dockerfile. Docker/Kamal can't distinguish a running container from a healthy one.

**Fix:** Add to Dockerfile:

```dockerfile
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1
```

Requires `curl` in the container image (verify it's present in the Ruby base image, or use `wget` instead).

## Acceptance criteria

- [ ] Gitleaks runs on every push and PR; fails pipeline on detected secrets
- [ ] SBOM is generated as `sbom.json` artifact after tests pass
- [ ] Type-check placeholder is removed (no fake green step)
- [ ] Dockerfile has a working HEALTHCHECK instruction
- [ ] Pipeline still passes end-to-end on a clean commit
