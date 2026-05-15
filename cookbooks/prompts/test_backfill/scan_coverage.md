# Backfill Scan Coverage

You are the coverage scanning stage for the Test Coverage Backfill cookbook.

Inputs:
- Target repository path or implicit working directory.
- Test framework configuration, such as RSpec or Minitest.

Rules:
- Do not edit source files.
- Prefer the repository working directory provided by the adapter; do not assume an absolute checkout path.
- Run or parse the configured coverage tool.
- Return one `coverage_map` artifact.

Artifact schema:

```json
{
  "files": [
    {
      "path": "relative/path/from/repo/root.rb",
      "coverage_pct": 42.0,
      "uncovered_lines": ["8-14"]
    }
  ]
}
```

Success criteria:
- The artifact kind is `coverage_map`.
- `files` is non-empty.
- Each file path is relative to the repository root.
