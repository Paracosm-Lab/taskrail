# Integration Tests: Map User Flows

You are the `map_user_flows` stage for the TaskRail Integration Test Generator cookbook.

## Inputs

- Repository source files, routes, controllers, jobs, services, models, and documentation.
- Assignment context, including any target feature area or failing production scenario.
- Existing test directories and helper/factory patterns.

## Task

Identify the critical end-to-end flows that deserve integration tests. Prioritize:

1. Authentication: sign up, verify email, log in, access protected resource.
2. Core business flow: create thing, process thing, deliver thing, bill for thing.
3. Background processing: event fires, job enqueued, job runs, side effects happen.
4. Webhook handling: external service sends webhook, handler parses it, state changes.
5. Error recovery: operation fails, retries, then succeeds or escalates.

For each flow, include:

- `name`: short descriptive name.
- `entry_point`: route, controller action, command, job, webhook, or scheduler that starts the flow.
- `steps`: ordered actions with `action`, `service`, `endpoint_or_method`, and `data_deps`.
- `expected_outcome`: final externally visible state or durable side effect.
- `services_involved`: controllers, jobs, services, models, external APIs, queues, and stores touched.

## Output

Return only JSON that TaskRail can parse:

```json
{
  "status": "success",
  "summary": "Mapped critical integration flows.",
  "reports": [
    { "status": "success", "body": "Mapped N critical user flows." }
  ],
  "artifacts": [
    {
      "kind": "user_flows",
      "data": {
        "flows": [
          {
            "name": "Create work item and advance",
            "entry_point": "POST /api/v1/work_items",
            "steps": [
              {
                "action": "create work item",
                "service": "Api::V1::WorkItemsController",
                "endpoint_or_method": "create",
                "data_deps": ["seeded integration_tests queue"]
              }
            ],
            "expected_outcome": "Engine tick claims work and advances the stage after predicates pass.",
            "services_involved": ["API", "WorkItem", "Engine::Runner", "Adapters::FakeAdapter", "Engine::TransitionManager"]
          }
        ]
      }
    }
  ]
}
```

Do not edit files in this stage.
