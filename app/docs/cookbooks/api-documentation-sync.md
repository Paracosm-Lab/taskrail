# API Documentation Sync Cookbook

Source spec: ../specs/cookbook-03-api-documentation-sync.md
Queue slug: api_docs_sync

## What it does

Scans a target app for routes/controllers/serializers, compares the endpoint inventory to existing OpenAPI/Markdown docs, drafts missing or stale docs, validates examples, and blocks for human review.

## Stages

scan_endpoints -> diff_existing_docs -> draft_documentation -> validate_examples -> human_review -> done

## Inputs

- Repository path or checkout context from the work item.
- Framework type when known.
- Existing docs path(s) when known.

## Infrastructure

This cookbook intentionally does not define shared Docker Compose services. The validation stage is shell-script based and should run inside whatever worker container the shared cookbook infrastructure provides. Optional OpenAPI validators such as `npx @redocly/cli lint` can be added later by the shared infrastructure plan.

## Portability

Queue YAML uses `file://prompts/...` prompt references resolved from `Rails.root` by `db/seeds.rb`. Do not add absolute repo paths.
