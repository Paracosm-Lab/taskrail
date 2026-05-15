# PR Review Pipeline Fixture App

This tiny Rails-style fixture app gives the `pr_review` cookbook deterministic PR-review inputs.

It intentionally contains examples a PR review pipeline should identify:

- SQL injection fixture: `OrderSearch#unsafe_search` interpolates user input.
- missing authorization fixture: `OrdersController#destroy` lacks an ownership/admin check.
- Coverage fixture: request specs cover index/create but intentionally omit destroy.
- Architecture fixture: controller logic is small enough for deterministic review comments.

The fixture is file-only and docker-friendly. Do not add absolute checkout paths or machine-specific credentials.
