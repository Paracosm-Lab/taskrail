# API Documentation Sync Cookbook

The `api_docs_sync` cookbook scans API endpoints, compares implementation behavior against existing documentation, drafts updates, validates examples, and stops for human review.

## Problem Statement

API docs drift because endpoint changes, serializer behavior, authentication requirements, and examples often change separately from documentation.

Taskrail turns documentation sync into a repeatable queue with reviewable artifacts.

## Stages

```text
scan_endpoints -> diff_existing_docs -> draft_documentation -> validate_examples -> human_review -> done
```

## Inputs

- API routes or OpenAPI files.
- Controller or handler source.
- Existing docs.
- Example requests and responses.
- Authentication conventions.

## Artifacts

- `endpoint_inventory`: discovered routes, methods, parameters, response shapes, and auth requirements.
- `documentation_diff`: stale, missing, or conflicting docs.
- `drafted_docs`: proposed documentation updates.
- `validation_results`: example request/response validation output.

## Human Gate

Humans review generated docs before publishing. The queue should not silently overwrite public docs.

## Configurability

Teams can tune route discovery, doc targets, validation commands, output format, examples, and review gates.
