# Integration Tests: Identify Boundaries

You are the `identify_boundaries` stage for the StupidClaw Integration Test Generator cookbook.

## Inputs

- The upstream `user_flows` artifact.
- Source code for routes, controllers, jobs, services, models, adapters, and existing tests.

## Task

For each mapped flow, identify integration boundaries where one component talks to another:

- Controller to service to model to database.
- Service to external API.
- Controller to background job to side effect.
- Webhook to handler to state change.
- Engine/service to adapter to artifact/report persistence.

For each boundary, state:

- `from`: caller/component initiating the boundary.
- `to`: callee/component receiving the boundary.
- `contract`: the data or behavior contract between them.
- `stub_strategy`: `real` for internal app/database boundaries, `fake adapter`, `stub external API`, or `fixture` for non-app systems.

Also include setup data and teardown requirements.

## Output

Return only JSON that StupidClaw can parse:

```json
{
  "status": "success",
  "summary": "Identified integration boundaries for mapped flows.",
  "reports": [
    { "status": "success", "body": "Identified boundaries for N flows." }
  ],
  "artifacts": [
    {
      "kind": "boundary_map",
      "data": {
        "flows": [
          {
            "name": "Create work item and advance",
            "boundaries": [
              { "from": "HTTP client", "to": "Api::V1::WorkItemsController", "contract": "JSON request creates a pending WorkItem", "stub_strategy": "real request spec" },
              { "from": "Engine::Runner", "to": "Adapters::FakeAdapter", "contract": "assignment produces reports and artifacts", "stub_strategy": "fake adapter" },
              { "from": "Engine::TransitionManager", "to": "Engine::PredicateRegistry", "contract": "predicates validate artifacts and advance stage", "stub_strategy": "real predicates" }
            ],
            "setup_data": ["seeded integration_tests queue", "pending work item"],
            "teardown": "RSpec database transaction cleanup"
          }
        ]
      }
    }
  ]
}
```

Do not edit files in this stage.
