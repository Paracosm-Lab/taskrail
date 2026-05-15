# Troubleshooting

Use this guide when local Taskrail execution does not behave as expected.

## `bin/taskrail doctor` Fails

Check that the Rails app is running:

```bash
bin/rails server
curl http://localhost:3000/health
```

If the CLI points at the wrong server, set:

```bash
TASKRAIL_API_URL=http://localhost:3000 bin/taskrail doctor
```

## No Queues Appear

Seed queue definitions:

```bash
bin/rails db:seed
bin/taskrail queues
```

If the queue still does not appear, check the YAML under `config/queues/*.yml`.

## Work Item Stays Pending

Run the engine:

```bash
bin/rails runner 'Engine::Runner.new.call'
```

Check for active claims:

```bash
bin/taskrail status WORK_ITEM_ID --traces
```

## Work Item Stays Claimed

The claim may be async or stuck.

Run async polling:

```bash
bin/rails runner 'Engine::AsyncClaimChecker.new.call'
```

Inspect the claim in the work item status output.

## Predicate Keeps Failing

Check:

- Which predicate failed.
- Which artifact or report it expected.
- Whether the adapter emitted the expected artifact kind.
- Whether the queue YAML references the right predicate name.

## Missing Artifact

Confirm the adapter config has the expected `output_artifact_kind` and that the adapter result includes artifact data.

## Shell Adapter Fails

Run the command manually from the configured working directory. Then verify that the command exists inside the same environment where Rails runs.

## Codex or Claude Adapter Fails

Check:

- CLI installed and authenticated.
- Working directory exists.
- Model override is valid.
- Async poll command is configured if needed.
- Secrets are not required by the fake local flow.

## API Returns HTML

The CLI is probably pointed at the frontend instead of Rails. Set `TASKRAIL_API_URL` to the Rails server URL.

## Costs or Traces Are Empty

Fake and shell workflows may emit minimal cost data. Model-backed adapters should emit trace events and cost metadata when available.

## Reset Local State

For local development only:

```bash
bin/rails db:reset
bin/rails db:seed
```

Do not reset shared or production databases.
